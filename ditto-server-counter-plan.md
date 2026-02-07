# Ditto Server (Big Peer) Counter Implementation Plan

## Problem Statement

The recent presence graph filtering fix removed Ditto Server (Big Peer) from the sync status list because Big Peer connections don't appear in the presence graph. Additionally, we have no way to show Ditto Server connections in the connection status bar.

**Current Issues:**
1. Big Peer filtered out by presence graph check (doesn't exist in `remotePeers`)
2. No Ditto Server counter in status bar
3. Can't distinguish between regular peer connections and Big Peer connections

## Solution

Use the `is_ditto_server` flag from `system:data_sync_info` to:
1. Exempt Big Peer from presence graph filtering
2. Count Ditto Server connections separately
3. Display Ditto Server counter in status bar

## Data Structure

**system:data_sync_info example:**
```json
{
  "_id": "pkAocCgkMCL1-NLoI08Sis2wTjXrldlfhUhweNpvrK9-n5uKy_hAM",
  "documents": {
    "last_update_received_time": -1,
    "sync_session_status": "Connected",
    "synced_up_to_local_commit_id": 221
  },
  "is_ditto_server": true
}
```

**Key field:** `is_ditto_server: true` indicates Big Peer connection

## Implementation Plan

### 1. Update ConnectionsByTransport Model

**File:** `Models/ConnectionsByTransport.swift`

**Add Property:**
```swift
let dittoServer: Int  // Count of Big Peer connections
```

**Update Property Order:**
```swift
let accessPoint: Int
let bluetooth: Int
let dittoServer: Int    // NEW
let p2pWiFi: Int
let webSocket: Int
```

**Update CodingKeys:**
```swift
enum CodingKeys: String, CodingKey {
    case accessPoint = "AccessPoint"
    case bluetooth = "Bluetooth"
    case dittoServer = "DittoServer"    // NEW
    case p2pWiFi = "P2PWiFi"
    case webSocket = "WebSocket"
}
```

**Update Initializers:**
```swift
// Default init
init(accessPoint: Int = 0, bluetooth: Int = 0, dittoServer: Int = 0,
     p2pWiFi: Int = 0, webSocket: Int = 0) {
    self.accessPoint = accessPoint
    self.bluetooth = bluetooth
    self.dittoServer = dittoServer
    self.p2pWiFi = p2pWiFi
    self.webSocket = webSocket
}

// Dictionary init (from system:data_sync_info)
init(from dictionary: [String: Any]) {
    if let connectionsDict = dictionary["connections_by_transport"] as? [String: Any] {
        self.accessPoint = connectionsDict["AccessPoint"] as? Int ?? 0
        self.bluetooth = connectionsDict["Bluetooth"] as? Int ?? 0
        self.dittoServer = connectionsDict["DittoServer"] as? Int ?? 0  // NEW
        self.p2pWiFi = connectionsDict["P2PWiFi"] as? Int ?? 0
        self.webSocket = connectionsDict["WebSocket"] as? Int ?? 0
    } else {
        self.accessPoint = 0
        self.bluetooth = 0
        self.dittoServer = 0  // NEW
        self.p2pWiFi = 0
        self.webSocket = 0
    }
}
```

**Update Computed Properties:**

```swift
var totalConnections: Int {
    accessPoint + bluetooth + dittoServer + p2pWiFi + webSocket  // Include dittoServer
}

var activeTransports: [(name: String, count: Int, icon: String, color: Color)] {
    var transports: [(String, Int, String, Color)] = []

    if webSocket > 0 {
        transports.append(("WebSocket", webSocket, "network", .purple))
    }
    if bluetooth > 0 {
        transports.append(("Bluetooth", bluetooth, "dot.radiowaves.forward", .blue))
    }
    if p2pWiFi > 0 {
        transports.append(("P2P WiFi", p2pWiFi, "wifi.router", .pink))
    }
    if accessPoint > 0 {
        transports.append(("Access Point", accessPoint, "antenna.radiowaves.left.and.right", .green))
    }
    if dittoServer > 0 {  // NEW
        transports.append(("Ditto Server", dittoServer, "cloud.fill", .purple))
    }

    return transports
}
```

**Update Static Property:**
```swift
static let empty = ConnectionsByTransport()  // All zeros including dittoServer
```

### 2. Update SystemRepository - Sync Status Observer

**File:** `Data/Repositories/SystemRepository.swift`

**Method:** `registerSyncStatusObserver()` (lines 143-183)

**Current Filtering Logic (lines 171-177):**
```swift
// Filter out stale peers: only show peers currently in presence graph
guard let enrichment = peerLookup[peerId] else {
    // Peer not in presence graph - they've disconnected
    item.dematerialize()
    return nil
}
```

**New Filtering Logic:**
```swift
// Check if this is a Ditto Server (Big Peer) connection
let isDittoServer = dict["is_ditto_server"] as? Bool ?? false

// Filter out stale peers, BUT keep Ditto Server even if not in presence graph
// Big Peer doesn't appear in presence graph but is still a valid connection
if !isDittoServer {
    guard let enrichment = peerLookup[peerId] else {
        // Regular peer not in presence graph - they've disconnected
        item.dematerialize()
        return nil
    }
    let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
    item.dematerialize()
    return syncItem
} else {
    // Ditto Server - keep even if not in presence graph
    let enrichment = peerLookup[peerId]  // Optional enrichment (may be nil)
    let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
    item.dematerialize()
    return syncItem
}
```

**Or cleaner version:**
```swift
// Check if this is a Ditto Server (Big Peer) connection
let isDittoServer = dict["is_ditto_server"] as? Bool ?? false

// Look up peer enrichment data
let enrichment = peerLookup[peerId]

// Filter out stale peers, BUT keep Ditto Server even if not in presence graph
// Big Peer doesn't appear in presence graph but is still a valid connection
if !isDittoServer && enrichment == nil {
    // Regular peer not in presence graph - they've disconnected
    item.dematerialize()
    return nil
}

let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
item.dematerialize()
return syncItem
```

### 3. Add Ditto Server Counter Logic

**File:** `Data/Repositories/SystemRepository.swift`

**Add New Property (after line 12):**
```swift
private var dittoServerCount: Int = 0
```

**Update registerSyncStatusObserver() to track Big Peer count:**

After building `statusItems` array (around line 177), add:
```swift
// Count Ditto Server connections from sync status
let newDittoServerCount = statusItems.filter { statusItem in
    // Check if this status item is for a Big Peer
    // We need to pass isDittoServer flag through SyncStatusInfo
    // OR re-parse the original dict here
    // TODO: Determine best approach
}.count

// Update Ditto Server count if changed
if newDittoServerCount != dittoServerCount {
    dittoServerCount = newDittoServerCount
    // Trigger connections update
    await updateConnectionsWithDittoServer()
}
```

**OR BETTER APPROACH - Track during compactMap:**

```swift
// Track Ditto Server count while building status items
var newDittoServerCount = 0

let statusItems: [SyncStatusInfo] = results.items.compactMap { item in
    let jsonData = item.jsonData()
    guard let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let peerId = dict["_id"] as? String else {
        item.dematerialize()
        return nil
    }

    // Check if this is a Ditto Server (Big Peer) connection
    let isDittoServer = dict["is_ditto_server"] as? Bool ?? false
    if isDittoServer {
        newDittoServerCount += 1
    }

    // ... filtering logic ...
}

// Update connections count if Ditto Server count changed
if newDittoServerCount != dittoServerCount {
    dittoServerCount = newDittoServerCount
    await updateConnectionsWithDittoServer()
}

// Call sync status callback
await self.onSyncStatusUpdate?(statusItems)
```

### 4. Integrate Ditto Server Count with Presence Observer

**Current Flow:**
- Presence observer counts: WebSocket, Bluetooth, P2P WiFi, Access Point
- Updates `ConnectionsByTransport` via callback

**New Flow:**
- Presence observer counts peer connections (as before)
- Sync status observer counts Ditto Server connections
- Combine both counts into final `ConnectionsByTransport`

**Implementation Options:**

**Option A: Store dittoServerCount and merge in presence observer**
```swift
func registerConnectionsPresenceObserver() async throws {
    // ... existing code ...
    connectionsPresenceObserver = ditto.presence.observe { [weak self] presenceGraph in
        Task { [weak self] in
            guard let self else { return }

            // Count peer connections (existing logic)
            var totalAccessPoint = 0
            var totalBluetooth = 0
            var totalP2PWiFi = 0
            var totalWebSocket = 0

            for peer in presenceGraph.remotePeers {
                // ... count connections ...
            }

            // Create aggregated result including Ditto Server count
            let aggregated = ConnectionsByTransport(
                accessPoint: totalAccessPoint,
                bluetooth: totalBluetooth,
                dittoServer: await self.dittoServerCount,  // Get stored count
                p2pWiFi: totalP2PWiFi,
                webSocket: totalWebSocket
            )

            await self.onConnectionsUpdate?(aggregated)
        }
    }
}
```

**Option B: Separate method to update connections with current counts**
```swift
private func updateConnectionsWithCurrentCounts() async {
    // Get current peer connection counts (stored from last presence update)
    // Get current Ditto Server count (stored from last sync status update)
    // Combine and trigger callback
}
```

**Recommended: Option A** - Simple and clear

### 5. Handle Sync Disable

**Location:** `MainStudioView.swift` ViewModel

**When sync is disabled:**
- Reset `connectionsByTransport` to `.empty` (already done)
- SystemRepository should reset `dittoServerCount` to 0

**Add to SystemRepository:**
```swift
func stopObserver() {
    Task.detached(priority: .utility) { [weak self] in
        await self?.performObserverCleanup()
    }
}

private func performObserverCleanup() {
    syncStatusObserver?.cancel()
    syncStatusObserver = nil
    connectionsPresenceObserver = nil
    dittoServerCount = 0  // NEW: Reset Ditto Server count
}
```

### 6. Edge Cases and Considerations

**Case 1: Sync disabled → re-enabled**
- `dittoServerCount` resets to 0 on cleanup
- Next sync status update sets correct count
- ✅ Handled

**Case 2: Multiple Big Peer connections**
- Count all items where `is_ditto_server == true`
- ✅ Handled by filter().count

**Case 3: Big Peer disconnects**
- Removed from `system:data_sync_info` results
- Count decreases naturally
- ✅ Handled

**Case 4: Presence updates before sync status**
- Presence observer triggers with peer counts
- Uses stored `dittoServerCount` (may be 0 initially)
- Next sync status update corrects the count
- ✅ Acceptable delay

**Case 5: Sync status updates before presence**
- Sync status updates `dittoServerCount`
- Calls `updateConnectionsWithDittoServer()` which triggers callback
- ✅ Immediate update

**Case 6: App switch**
- Both observers re-register for new app
- Counts reset via cleanup
- ✅ Handled

## Implementation Steps

### Phase 1: Model Updates
1. ✅ Update `ConnectionsByTransport` model with `dittoServer` property
2. ✅ Update all initializers to include `dittoServer`
3. ✅ Update `totalConnections` computed property
4. ✅ Update `activeTransports` to include Ditto Server (cloud icon, purple)
5. ✅ Update `.empty` static property

### Phase 2: Sync Status Filtering
1. ✅ Add `is_ditto_server` check in sync status observer
2. ✅ Update filtering logic to exempt Big Peer
3. ✅ Track `dittoServerCount` during compactMap
4. ✅ Add `dittoServerCount` property to SystemRepository

### Phase 3: Integration
1. ✅ Update presence observer to include `dittoServerCount` in aggregation
2. ✅ Ensure both observers can trigger connection updates
3. ✅ Test with sync disabled → enabled → disabled flow

### Phase 4: Cleanup
1. ✅ Reset `dittoServerCount` in `performObserverCleanup()`
2. ✅ Verify app switch resets counts properly

### Phase 5: Testing
1. ✅ Manual test: Connect to Big Peer → verify count appears
2. ✅ Manual test: Disconnect Big Peer → verify count disappears
3. ✅ Manual test: Disable sync → verify Ditto Server removed from status bar
4. ✅ Manual test: Multiple Big Peer connections → verify count
5. ✅ Manual test: Mix of peer connections and Big Peer → verify all counts

## Files to Modify

1. **`Models/ConnectionsByTransport.swift`**
   - Add `dittoServer: Int` property
   - Update all initializers, computed properties, CodingKeys

2. **`Data/Repositories/SystemRepository.swift`**
   - Add `dittoServerCount: Int` property
   - Update `registerSyncStatusObserver()` filtering logic
   - Track Ditto Server count during compactMap
   - Update presence observer to include `dittoServerCount`
   - Reset count in `performObserverCleanup()`

3. **`Components/ConnectionStatusBar.swift`**
   - No changes needed (automatically picks up new transport type)

4. **`Views/MainStudioView.swift`**
   - No changes needed (already resets connections on app close)

## Visual Design

**Status Bar with Ditto Server:**
```
[🟢 Sync Active]  [🔵 Bluetooth 2]  [🩷 P2P WiFi 1]  [☁️ Ditto Server 1]       [🔗 4]
```

**Icon:** `cloud.fill` (SF Symbol)
**Color:** Purple (Big Peer color from Ditto Rainbow)
**Label:** "Ditto Server"

## Success Criteria

✅ Big Peer connections appear in sync status list (not filtered out)
✅ Ditto Server counter appears in status bar when connected to Big Peer
✅ Ditto Server counter shows correct count (handles multiple Big Peer connections)
✅ Ditto Server counter disappears when sync disabled or no Big Peer connected
✅ Regular peer filtering still works (removes disconnected non-Big-Peer peers)
✅ Status bar total count includes Ditto Server connections
✅ No threading warnings or memory leaks
✅ Build succeeds without errors

## Open Questions

**Q1: Can there be multiple Big Peer connections simultaneously?**
- **A:** Yes, count all items where `is_ditto_server == true`

**Q2: Should Big Peer count be separate from WebSocket count?**
- **A:** Yes, separate counter "Ditto Server" for clarity

**Q3: What if `is_ditto_server` flag is missing from response?**
- **A:** Default to `false` via `dict["is_ditto_server"] as? Bool ?? false`

**Q4: Should we show Big Peer in presence graph at all?**
- **A:** No, Big Peer doesn't appear in presence graph. Use sync status only.

**Q5: What happens if both sync status and presence update simultaneously?**
- **A:** Each triggers callback independently. Last update wins (acceptable).

## Alternative Approaches Considered

### Option 1: Add Big Peer to presence observer artificially
- **Pros:** Single source of truth
- **Cons:** Presence graph doesn't include Big Peer by design
- **Verdict:** ❌ Not possible

### Option 2: Only show Big Peer in sync status, not status bar
- **Pros:** Simpler implementation
- **Cons:** Incomplete information in status bar
- **Verdict:** ❌ User wants full visibility

### Option 3: Chosen approach - Dual tracking
- **Pros:** Accurate counts from proper sources
- **Cons:** Slightly more complex (two observers)
- **Verdict:** ✅ Most accurate and complete

## Testing Checklist

- [ ] Build succeeds
- [ ] Connect to Big Peer → appears in sync status list
- [ ] Connect to Big Peer → Ditto Server counter appears in status bar
- [ ] Multiple Big Peer connections → count shows correctly
- [ ] Disconnect Big Peer → removed from sync status and status bar
- [ ] Disable sync → Ditto Server counter removed
- [ ] Re-enable sync → Ditto Server counter reappears if connected
- [ ] Mix of peers and Big Peer → all counters correct
- [ ] App switch → counts reset and reload correctly
- [ ] Regular peer disconnect → still filtered out correctly
- [ ] Status bar total includes Ditto Server count

## Documentation Updates

**CLAUDE.md** - Update key features:
```markdown
- Connection status bar with real-time transport-level monitoring
  (WebSocket, Bluetooth, P2P WiFi, Access Point, Ditto Server)
```

**Code Comments** - Add to filtering logic:
```swift
// Check if this is a Ditto Server (Big Peer) connection
// Big Peer doesn't appear in presence graph but is still a valid connection
let isDittoServer = dict["is_ditto_server"] as? Bool ?? false
```
