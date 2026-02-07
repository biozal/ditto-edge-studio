# Connection Status Bar - Presence Graph Update Plan

## Context

The current implementation uses a Ditto store observer on `__small_peer_info` which doesn't provide real-time updates. We need to switch to the presence graph API (`ditto.presence.observe()`) which provides live connection updates.

Additionally, we need to add a counter for Big Peer (Ditto Server) connections.

## Current Implementation Issues

1. **Static Data**: `__small_peer_info` query doesn't update dynamically with connection changes
2. **Missing Big Peer**: No counter for Ditto Server (Big Peer) connections
3. **Observer Pattern**: Using store observer instead of presence observer

## Presence Graph API Benefits

- **Real-time updates**: `ditto.presence.observe()` triggers callbacks on connection changes
- **Direct access**: `presenceGraph.remotePeers` provides live peer information
- **Connection details**: Each peer has `connections` array with type information

## Implementation Plan

### 1. Update ConnectionsByTransport Model

**File:** `Models/ConnectionsByTransport.swift`

**Changes:**
- Add `dittoServer: Int` property (for Big Peer connections)
- Update `CodingKeys` to map `"DittoServer"` (if needed for backward compatibility)
- Update initializers to include `dittoServer` parameter
- Update `totalConnections` to include `dittoServer`
- Add Ditto Server to `activeTransports` array with cloud icon and purple color
  - Icon: `"cloud.fill"` (SF Symbol)
  - Color: `.purple` (Big Peer color from Ditto Rainbow)
  - Name: `"Ditto Server"`

**New Property Order:**
```swift
let accessPoint: Int
let bluetooth: Int
let dittoServer: Int  // NEW
let p2pWiFi: Int
let webSocket: Int
```

### 2. Update SystemRepository

**File:** `Data/Repositories/SystemRepository.swift`

**Remove:**
- `connectionsObserver: DittoStoreObserver?` property
- `registerConnectionsObserver()` method that queries `__small_peer_info`
- Store observer cleanup in `performObserverCleanup()`

**Add:**
- `connectionsPresenceObserver: DittoPresenceObserver?` property
- `registerConnectionsPresenceObserver()` method using `ditto.presence.observe()`
- Presence observer cleanup in `performObserverCleanup()` and `deinit`

**New Method Signature:**
```swift
func registerConnectionsPresenceObserver() async throws
```

**New Method Logic:**
1. Get ditto instance from `dittoManager.dittoSelectedApp`
2. Register presence observer: `ditto.presence.observe { presenceGraph in ... }`
3. Inside callback:
   - Initialize counters: `accessPoint`, `bluetooth`, `dittoServer`, `p2pWiFi`, `webSocket`
   - Iterate through `presenceGraph.remotePeers`
   - For each peer, access `peer.connections` array
   - For each connection, check `connection.type` and increment appropriate counter
   - Check if peer is Big Peer (see detection logic below)
   - Create `ConnectionsByTransport` with aggregated counts
   - Call `onConnectionsUpdate` callback with aggregated result

**Big Peer Detection Logic:**
Big Peer connections are typically identified by:
- Connection type containing "webSocket" or similar
- Peer having specific metadata or flags
- **Check existing code**: The `extractPeerEnrichment` method already processes peers - look for patterns that indicate Big Peer

**Existing Code Reference:**
Lines 94-109 in SystemRepository already iterate through `peer.connections` and convert connection types. The `convertConnectionType` method (lines 20-35) handles type conversion. Use this same pattern but count by type instead of creating enrichment data.

### 3. Update MainStudioView ViewModel

**File:** `Views/MainStudioView.swift`

**Changes:**
- Update observer registration call in init (around line 1337):
  - Change from: `try await SystemRepository.shared.registerConnectionsObserver()`
  - Change to: `try await SystemRepository.shared.registerConnectionsPresenceObserver()`

**No other changes needed** - the callback and property assignments remain the same.

### 4. Update ConnectionStatusBar Component

**File:** `Components/ConnectionStatusBar.swift`

**No changes needed** - the component already iterates through `connections.activeTransports` and displays them dynamically. The new Ditto Server transport will automatically appear when the model is updated.

### 5. Testing Plan

**Manual Testing:**
1. Launch app with sync disabled → verify "Sync Disabled" shows
2. Enable sync → verify "Sync Active" shows
3. Connect peer via WebSocket → verify WebSocket counter increments
4. Connect to Ditto Server (Big Peer) → verify Ditto Server counter appears with cloud icon
5. Connect peer via Bluetooth → verify Bluetooth counter increments
6. Disconnect peers → verify counters decrement in real-time
7. Switch between apps → verify counters reset and load new app's connections
8. Monitor console for memory leaks or observer cleanup warnings

**Verification:**
- Presence observer should trigger callbacks on connection/disconnection events
- Counters should update immediately (not require polling)
- No threading warnings in console
- Observer properly cleaned up on app close

## Implementation Notes

### Connection Type Mapping

Based on existing `convertConnectionType` method (SystemRepository.swift lines 20-35):

```swift
private func convertConnectionType(_ dittoType: DittoConnectionType) -> ConnectionType {
    let typeString = "\(dittoType)"

    if typeString.contains("bluetooth") {
        return .bluetooth
    } else if typeString.contains("accessPoint") {
        return .accessPoint
    } else if typeString.contains("p2pWiFi") || typeString.contains("p2pwifi") {
        return .p2pWiFi
    } else if typeString.contains("webSocket") || typeString.contains("websocket") {
        return .webSocket
    } else {
        return .unknown(typeString)
    }
}
```

**For counting connections:**
- Count each connection type across all peers
- Don't double-count connections (each connection represents one link)
- Big Peer detection: Check if peer metadata or connection indicates server connection

### Big Peer Identification

**Option 1: Check Peer Metadata**
- Look for `peer.identityServiceMetadata` or other server indicators
- Check if peer has special flags or properties

**Option 2: Check Connection Properties**
- WebSocket connections to known server endpoints
- Connections with specific characteristics (connection ID patterns, etc.)

**Option 3: Use Existing Patterns**
- Review existing `extractPeerEnrichment` code for clues
- Check if DittoSwift SDK provides explicit Big Peer identification

**Recommended Approach:**
Start with checking for WebSocket connections that have server-like characteristics. May need to consult DittoSwift SDK documentation or test with live connections to determine exact detection method.

### Memory Management

**Critical:**
- Store presence observer in property: `connectionsPresenceObserver`
- Cancel observer in `deinit` and `performObserverCleanup()`
- Use `[weak self]` in closures to prevent retain cycles
- Use `Task { @MainActor in ... }` for UI updates in callback

### Threading

- Presence observer callback runs on background thread
- Wrap `onConnectionsUpdate` call in `Task { @MainActor in ... }`
- Matches existing pattern from `syncStatusObserver` (lines 152-178)

## Files to Modify

1. `Models/ConnectionsByTransport.swift` - Add `dittoServer` property
2. `Data/Repositories/SystemRepository.swift` - Replace store observer with presence observer
3. `Views/MainStudioView.swift` - Update observer registration call
4. `Components/ConnectionStatusBar.swift` - No changes (automatic via model update)

## Success Criteria

- ✅ Connection counters update in real-time when peers connect/disconnect
- ✅ Ditto Server counter appears with cloud icon when Big Peer is connected
- ✅ All transport types (WebSocket, Bluetooth, P2P WiFi, Access Point, Ditto Server) display correctly
- ✅ Status bar uses Ditto Rainbow colors (Purple for both WebSocket and Ditto Server)
- ✅ No memory leaks or threading warnings
- ✅ Clean observer cleanup on app close
- ✅ Counters reset properly when switching apps

## Open Questions

1. **Big Peer Detection**: What is the exact method to identify a Big Peer connection in DittoSwift SDK?
   - Need to test with live Big Peer connection
   - May need to check peer properties or connection metadata
   - Could consult DittoSwift SDK source code or documentation

2. **Connection Counting**: Should we count:
   - Total connections across all peers? (current approach)
   - Unique connected peers by transport type?
   - Both?

3. **WebSocket vs Ditto Server**: Are these mutually exclusive or can they overlap?
   - If WebSocket to Big Peer, count as "Ditto Server" only?
   - Or count in both categories?

## Next Steps

1. Review plan with user for approval
2. Implement ConnectionsByTransport model changes
3. Implement SystemRepository presence observer
4. Test with live connections to determine Big Peer detection method
5. Update MainStudioView registration call
6. Manual testing with various connection scenarios
7. Update documentation if needed
