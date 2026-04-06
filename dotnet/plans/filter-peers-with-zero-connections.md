# Plan: Filter Out Peers with Zero Active Connections in .NET Peer List

## Status: Proposed

## Problem

In the .NET version, peer cards are rendered for peers that have **0 active connections** (i.e., peers found in `system:data_sync_info` DQL results but with no direct connection to the local device in the presence graph). The SwiftUI version filters these out so only peers with at least one active direct connection are shown.

---

## Root Cause Analysis

### SwiftUI: Presence-First Approach

`SystemRepository.swift` registers a **presence observer** (`ditto.presence.observe`). Inside the callback it:

1. Filters `presenceGraph.remotePeers` to only peers that share at least one direct connection with the local device:
   ```swift
   let connectedPeers = presenceGraph.remotePeers.filter { peer in
       peer.connections.contains {
           $0.peerKeyString1 == localPeerKeyString || $0.peerKeyString2 == localPeerKeyString
       }
   }
   ```
2. Uses this filtered list as the **authoritative source** of which peers exist.
3. Queries DQL (`system:data_sync_info`) for sync metrics and merges them in — enrichment only, not the source of truth.
4. Any peer not in the filtered presence list is **never shown**, regardless of what DQL says.
5. For Cloud Servers (which may not appear in the presence graph), it still checks `SyncSessionStatus != "Not Connected"` before including them.

### .NET: DQL-First Approach (Current)

`SystemRepository.cs` registers a **DQL observer** on `system:data_sync_info`. This is the primary data source. It then:

1. Iterates every row from DQL (all peers that have ever been seen).
2. Calls `MergeSyncInfoWithPresenceGraph` to look up presence data — but this is enrichment, not a gate.
3. Only filters by `IsConnected` (`SyncSessionStatus == "Connected"`) for add/remove logic.

**The bug**: DQL can return rows where `SyncSessionStatus == "Connected"` but where the peer's connections in the presence graph do NOT include the local device as an endpoint. This happens with multihop peers (indirectly connected). These peers pass the `IsConnected` check and get cards rendered with `ActiveConnections = []` or `ActiveConnections = null`.

---

## Proposed Fix

Add a **presence-graph filter** in `MergeSyncInfoWithPresenceGraph` and in the update loop within `RegisterPeerCardObservers`. The fix is intentionally minimal: keep the DQL-first architecture (the Ditto v4 .NET SDK may not expose a presence observer API), but add the same "must have at least one direct connection" gate that SwiftUI uses.

### Change 1: `MergeSyncInfoWithPresenceGraph` — add presence filter gate

In the section that handles non-server peers, after looking up the presence peer, add a check:
- If the peer has **no direct connections** (i.e., no connection where `PeerKey1 == localPeerKey || PeerKey2 == localPeerKey`), treat the peer as not directly connected and return `null` (or a sentinel).

Return `null` from `MergeSyncInfoWithPresenceGraph` when:
- The peer is **not** a Ditto Cloud Server, AND
- The peer's `ActiveConnections` list (after filtering to direct connections) is empty or null.

Signature change:
```csharp
private static PeerCardInfo? MergeSyncInfoWithPresenceGraph(
    SyncStatusInfo syncInfo,
    DittoPresenceGraph presenceGraph,
    string localPeerKey)
```

Return `null` for the case where a DQL entry has no direct presence connections.

### Change 2: `RegisterPeerCardObservers` — skip null peer cards

In the LINQ pipeline that builds `peerCardUpdates`, filter out null results:
```csharp
var peerCardUpdates = extractedItems
    .Select(x => MergeSyncInfoWithPresenceGraph(x, presenceGraph, presenceGraph.LocalPeer.PeerKey))
    .Where(x => x != null)   // ← add this
    .ToList();
```

And update the `currentIds` set to only include IDs from non-null cards (or use the filtered list).

### Change 3: Handle Cloud Servers consistently with SwiftUI

SwiftUI also guards Cloud Servers: skip (and don't count) servers where `SyncSessionStatus == "Not Connected"`:
```swift
let isNotConnected = syncSessionStatus == "Not Connected"
guard !isNotConnected else { continue }
```

The .NET server branch in `MergeSyncInfoWithPresenceGraph` currently returns a card regardless of `SyncSessionStatus`. Update the server branch in `RegisterPeerCardObservers` (or in the merge method) to return `null` when `syncInfo.Documents.SyncSessionStatus == "Not Connected"`.

### Change 4: Also remove stale cards for IDs no longer in the filtered result set

Currently, the removal loop uses `currentIds` which is built from **all** DQL results (before the null filter). After filtering, a peer with 0 direct connections would:
- Not be in `peerCardUpdates` (filtered out), but
- Still be in `currentIds` — so existing stale cards won't be cleaned up.

Fix: Build `currentIds` from the **filtered** `peerCardUpdates` list instead of from `extractedItems`.

---

## Files to Modify

| File | Change |
|------|--------|
| `dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | Main logic — all 4 changes above |

No interface changes or model changes are needed.

---

## Detailed Code Changes

### `SystemRepository.cs` — `RegisterPeerCardObservers`

**Before** (lines ~175–206):
```csharp
var peerCardUpdates = extractedItems
    .Select(x => MergeSyncInfoWithPresenceGraph(x, presenceGraph, presenceGraph.LocalPeer.PeerKey))
    .ToList();

// Build lookup of current IDs from query results
var currentIds = new HashSet<string>(extractedItems.Select(x => x.Id));
```

**After**:
```csharp
var peerCardUpdates = extractedItems
    .Select(x => MergeSyncInfoWithPresenceGraph(x, presenceGraph, presenceGraph.LocalPeer.PeerKey))
    .Where(x => x != null)
    .Select(x => x!)
    .ToList();

// Build lookup of current IDs from FILTERED results (mirrors SwiftUI presence-first approach:
// only peers with at least one direct connection are authoritative)
var currentIds = new HashSet<string>(peerCardUpdates.Select(x => x.Id));
```

### `SystemRepository.cs` — `MergeSyncInfoWithPresenceGraph`

**Before** (return type `PeerCardInfo`):
```csharp
private static PeerCardInfo MergeSyncInfoWithPresenceGraph(...)
```

**After** (return type `PeerCardInfo?`):
```csharp
private static PeerCardInfo? MergeSyncInfoWithPresenceGraph(...)
```

**In the Server branch** — guard against "Not Connected":
```csharp
if (syncInfo.IsDittoServer)
{
    // Skip (and do NOT count) servers that are not currently connected — mirrors SwiftUI behavior
    if (syncInfo.Documents.SyncSessionStatus == "Not Connected")
        return null;

    return new PeerCardInfo { ... };
}
```

**In the Remote peer WITH presence data branch** — guard against 0 direct connections:
```csharp
var directConnections = remotePeer.Connections
    .Where(c => c.PeerKey1 == localPeerKey || c.PeerKey2 == localPeerKey)
    .GroupBy(c => c.ConnectionType.ToString())
    .Select(g => g.First())
    .Select(c => new PeerConnectionInfo { ... })
    .ToList();

// Mirror SwiftUI: only show peers with at least one direct connection
if (directConnections.Count == 0)
    return null;

return new PeerCardInfo
{
    ...
    ActiveConnections = directConnections,
    ...
};
```

**In the Remote peer WITHOUT presence data branch** — always return null (no presence = not directly connected):
```csharp
// Remote peer NOT in presence graph = not directly connected to us.
// SwiftUI would never show this peer (it starts from filtered presence).
// Return null to suppress the card.
return null;
```

---

## Testing

After making the changes, verify:
1. Peers with direct connections still appear correctly.
2. Peers visible only via multihop (no direct connection) do NOT appear.
3. Ditto Cloud Server cards disappear when their `SyncSessionStatus` transitions to "Not Connected".
4. The `dittoServerCount` passed to `PublishConnectionCounts` still only counts servers that are connected — check that `CountDittoServerCount` is also updated to count from `peerCardUpdates` (not `extractedItems`) after the filter.
5. Existing unit tests pass.

### Note on `dittoServerCount`

The current code counts Ditto Servers from `extractedItems` (before the null filter):
```csharp
var dittoServerCount = extractedItems.Count(x => x.IsDittoServer);
```

After applying the fix, this should count from the filtered results instead, to match SwiftUI:
```csharp
var dittoServerCount = peerCardUpdates.Count(x => x.IsDittoServer);
```

This ensures the connection count in the status bar doesn't include disconnected Cloud Servers.

---

## Summary of Behaviour Change

| Scenario | Before Fix | After Fix (matches SwiftUI) |
|----------|-----------|----------------------------|
| Multihop peer (0 direct connections) | Card shown with "Connected" | No card shown |
| Remote peer not in presence graph | Card shown with no connections | No card shown |
| Cloud Server with "Not Connected" status | Card shown | No card shown |
| Normal directly-connected peer | Card shown ✅ | Card shown ✅ |
| Local peer | Always shown ✅ | Always shown ✅ |
