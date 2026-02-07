# Sync Status Presence Filter Plan

## Problem Statement

The `registerSyncStatusObserver` function in SystemRepository queries `system:data_sync_info` which doesn't update frequently. This causes stale peer data to be displayed - peers that have disconnected still appear as connected because the DQL query hasn't updated yet.

**Current Flow:**
1. Query `system:data_sync_info` via store observer
2. Build peer lookup map from presence graph (`buildPeerLookupMap`)
3. Enrich query results with peer data
4. Return ALL results (including stale peers not in presence graph)

**Issue:**
- Peer shows as "connected" in sync status even after disconnecting
- `system:data_sync_info` is slow to update
- Confusing UX - status bar shows correct connection count, but peer list shows disconnected peers

## Solution

Filter out peers that don't exist in the current presence graph before returning results. If a peer ID from `system:data_sync_info` isn't in the presence graph lookup map, it means they're no longer connected and should be excluded.

## Implementation Plan

### File to Modify

**`Data/Repositories/SystemRepository.swift`** - Update `registerSyncStatusObserver()` method

### Current Code Flow (Lines 140-180)

```swift
func registerSyncStatusObserver() async throws {
    // ... setup ...

    syncStatusObserver = try ditto.store.registerObserver(
        query: "SELECT * FROM system:data_sync_info ORDER BY ..."
    ) { [weak self] results in
        Task { [weak self] in
            guard let self else { return }

            // Build peer lookup map from presence graph
            let peerLookup = await self.buildPeerLookupMap(ditto: ditto)

            // Create enriched SyncStatusInfo instances
            let statusItems: [SyncStatusInfo] = results.items.compactMap { item in
                let jsonData = item.jsonData()
                guard let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let peerId = dict["_id"] as? String else {
                    item.dematerialize()
                    return nil
                }

                // Look up peer enrichment data
                let enrichment = peerLookup[peerId]

                let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
                item.dematerialize()
                return syncItem
            }

            // Call callback with ALL items
            await self.onSyncStatusUpdate?(statusItems)
        }
    }
}
```

### Proposed Changes

**Add presence check before including peer in results:**

```swift
let statusItems: [SyncStatusInfo] = results.items.compactMap { item in
    let jsonData = item.jsonData()
    guard let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let peerId = dict["_id"] as? String else {
        item.dematerialize()
        return nil
    }

    // NEW: Check if peer exists in current presence graph
    guard let enrichment = peerLookup[peerId] else {
        // Peer not in presence graph - they've disconnected
        // Don't include in results
        item.dematerialize()
        return nil
    }

    // Peer is present - include in results with enrichment
    let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
    item.dematerialize()
    return syncItem
}
```

### Key Changes

1. **Change from:**
   ```swift
   let enrichment = peerLookup[peerId]  // Optional enrichment
   let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
   ```

2. **Change to:**
   ```swift
   guard let enrichment = peerLookup[peerId] else {
       // Peer not present - skip this result
       item.dematerialize()
       return nil
   }
   let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
   ```

### Logic Explanation

**Before:**
- All peers from `system:data_sync_info` are shown
- Enrichment is optional (can be `nil` if peer not in graph)
- Shows stale/disconnected peers

**After:**
- Only peers in presence graph are shown
- Enrichment is required (guard ensures peer is present)
- Filters out stale/disconnected peers automatically

### Why This Works

**Presence Graph as Source of Truth:**
- Presence graph is real-time (updated via `ditto.presence` API)
- If peer is in presence graph → they're currently connected
- If peer NOT in presence graph → they've disconnected (even if `system:data_sync_info` hasn't updated)

**Filter Mechanism:**
- `buildPeerLookupMap()` builds map from `presenceGraph.remotePeers`
- Lookup map contains only currently connected peers
- Guard statement filters out any peer ID not in the map
- Result: Only show peers that are actually connected RIGHT NOW

## Benefits

✅ **Accurate peer status** - Only show currently connected peers
✅ **Real-time filtering** - Presence graph is updated immediately
✅ **Solves stale data issue** - Compensates for slow `system:data_sync_info` updates
✅ **Consistent UX** - Status bar connection count matches peer list
✅ **Simple fix** - Single guard statement, no API changes
✅ **No breaking changes** - `SyncStatusInfo` initialization remains the same

## Testing Plan

### Manual Testing Scenarios

1. **Connect peer via WebSocket:**
   - ✅ Peer appears in sync status list
   - ✅ Status bar shows WebSocket connection count

2. **Disconnect peer:**
   - ✅ Peer immediately disappears from sync status list (don't wait for DQL update)
   - ✅ Status bar connection count decrements immediately

3. **Connect multiple peers:**
   - ✅ All connected peers appear in list
   - ✅ Counts are accurate

4. **Rapid connect/disconnect:**
   - ✅ List updates immediately with presence changes
   - ✅ No stale peers linger in the list

5. **App switch:**
   - ✅ New app shows only its connected peers
   - ✅ No carryover of stale data

### Verification Checks

- Monitor console for errors during peer filtering
- Verify no memory leaks with observer lifecycle
- Check that `item.dematerialize()` is called for filtered peers
- Ensure UI updates smoothly without flashing

## Edge Cases

### What if ALL peers are filtered out?

**Current behavior:** Show empty state "No Sync Status Available"
**After fix:** Same behavior - empty array triggers empty state
**Result:** ✅ No change needed

### What if peerLookup is empty?

**Scenario:** No peers in presence graph
**Result:** All items filtered out → empty array → empty state
**Behavior:** ✅ Correct (no peers connected)

### What if peerId format doesn't match?

**Current code:** Already handles this gracefully
**Matching:** Uses `peerId` from DQL as key in lookup map
**Result:** ✅ Should match correctly (both use `peer.peerKeyString`)

### What about local peer?

**Scenario:** Local device should not appear in remote peers
**Current behavior:** `remotePeers` excludes local peer
**Result:** ✅ Local peer correctly excluded

## Implementation Steps

1. **Read current implementation** (SystemRepository.swift lines 140-180)
2. **Modify compactMap closure** to add guard statement
3. **Test with connected peer** → verify peer appears
4. **Test with disconnected peer** → verify peer disappears immediately
5. **Test rapid connect/disconnect** → verify no stale data
6. **Verify build** succeeds
7. **Update documentation** if needed

## Code Location

**File:** `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Data/Repositories/SystemRepository.swift`

**Method:** `registerSyncStatusObserver()` (starts at line 140)

**Specific section to modify:** Lines ~160-173 (the compactMap closure)

## Risks and Considerations

### Potential Issues

1. **Over-filtering:** What if presence graph updates slower than DQL?
   - **Mitigation:** Presence graph is real-time via observer, should be faster than DQL
   - **Risk:** Low - presence updates are immediate

2. **Missing enrichment data:** What if we want to show peers without enrichment?
   - **Current design:** Enrichment is optional in `SyncStatusInfo`
   - **New design:** Enrichment becomes required (presence = connected)
   - **Risk:** Low - if peer is present, enrichment data should exist

3. **Peer ID mismatch:** What if peer IDs don't match between systems?
   - **Current code:** Already using same ID (`peer.peerKeyString`)
   - **Risk:** Low - established pattern

### Performance Impact

- **Additional check:** One dictionary lookup per peer (O(1))
- **Impact:** Negligible - lookup is fast
- **Benefit:** Cleaner UI, no stale data rendering

## Success Criteria

✅ Disconnected peers immediately removed from sync status list
✅ Status bar connection count matches peer list count
✅ No threading warnings or memory leaks
✅ Build succeeds without errors
✅ Empty state handles zero connected peers correctly
✅ No visual glitches or UI flashing during updates

## Alternative Approaches Considered

### Option 1: Add "connected" flag to SyncStatusInfo
- **Pros:** Keep all peers, mark as connected/disconnected
- **Cons:** More complex UI logic, still shows disconnected peers
- **Verdict:** ❌ Doesn't solve core issue

### Option 2: Use only presence graph, ignore DQL
- **Pros:** Always accurate, real-time
- **Cons:** Loses sync session data from DQL
- **Verdict:** ❌ Loses valuable information

### Option 3: Filter in UI layer instead of repository
- **Pros:** Separation of concerns
- **Cons:** Multiple views need same logic, harder to maintain
- **Verdict:** ❌ Repository is better place for data consistency

### Option 4: Chosen approach - Filter at repository level
- **Pros:** Clean, simple, source of truth in one place
- **Cons:** Makes enrichment mandatory (acceptable trade-off)
- **Verdict:** ✅ Best balance of simplicity and correctness

## Documentation Updates

**CLAUDE.md** - No changes needed (internal implementation detail)

**Code Comments** - Add comment explaining presence filtering:
```swift
// Filter out stale peers: only show peers currently in presence graph
// This prevents showing disconnected peers when system:data_sync_info is slow to update
guard let enrichment = peerLookup[peerId] else {
    item.dematerialize()
    return nil
}
```

## Next Steps

1. ✅ Review plan with user
2. Implement guard statement in `registerSyncStatusObserver`
3. Add explanatory comment
4. Build and verify
5. Manual testing with connect/disconnect scenarios
6. Verify consistency between status bar and peer list
