# Presence Graph: Direct Connection Filtering

## The Pitfall

`presenceGraph.remotePeers` returns the **full mesh topology** — every peer visible in
the Ditto network, including peers the local device has never directly communicated with
(multihop peers). **Never use it unfiltered** for peer cards or transport-count aggregation.

### Why It Matters

In a 3-device mesh (A ↔ B ↔ C where A and C are not directly linked):
- Device A's `remotePeers` contains **both B and C**
- A has no direct connection to C — all traffic flows through B
- Without filtering, device A shows 2 peer cards (inflated) and counts C's transports

## The Required Filter Pattern

A peer is "directly connected" if the **local device's peer key is an endpoint** of at
least one of that peer's connections.

### Swift (SwiftUI — SDK v5)

```swift
let localPeerKey = presenceGraph.localPeer.peerKeyString

// Filter to directly connected peers only
let directPeers = presenceGraph.remotePeers.filter { peer in
    peer.connections.contains {
        $0.peerKeyString1 == localPeerKey || $0.peerKeyString2 == localPeerKey
    }
}

// Filter connections within a peer (for per-peer transport counts)
let directConnections = peer.connections.filter {
    $0.peerKeyString1 == localPeerKey || $0.peerKeyString2 == localPeerKey
}
```

Connection endpoint field names (SDK v5): `peerKeyString1` / `peerKeyString2`

### Kotlin (Android — SDK v4/v5)

```kotlin
val localPeerKey = graph.localPeer.peerKey

// Filter to directly connected peers only
val directPeers = graph.remotePeers.filter { peer ->
    peer.connections.any { conn -> conn.peer1 == localPeerKey || conn.peer2 == localPeerKey }
}

// Filter connections within a peer (for per-peer transport counts)
val directConnections = peer.connections.filter { conn ->
    conn.peer1 == localPeerKey || conn.peer2 == localPeerKey
}
```

Connection endpoint field names (SDK v4/v5): `peer1` / `peer2`

### C# (.NET — SDK 4.13.0)

```csharp
var localPeerKey = presenceGraph.LocalPeer.PeerKeyString;

// Filter connections within a peer (for transport counts)
var directConnections = peer.Connections
    .Where(c => c.PeerKeyString1 == localPeerKey || c.PeerKeyString2 == localPeerKey);
```

Connection endpoint field names (SDK 4.13.0): `PeerKeyString1` / `PeerKeyString2`
⚠️ Verify these property names compile against the installed SDK version. If they are
not available, use `presenceGraph.LocalPeer.Connections` to obtain the set of directly
connected remote peer keys as a fallback.

## Cloud Server Exemption

Peers with `isDittoServer = true` (Ditto Cloud / Big Peer) are always directly connected
via WebSocket. They are added to peer cards via DQL (`system:data_sync_info`) rather than
presence graph filtering, so they are exempt from this filter on all platforms.

## Platform Field Name Reference

| Platform | SDK Version | Local Peer Key | Conn Endpoint 1 | Conn Endpoint 2 |
|----------|-------------|----------------|-----------------|-----------------|
| SwiftUI  | v5          | `localPeer.peerKeyString` | `peerKeyString1` | `peerKeyString2` |
| Android  | v4/v5       | `localPeer.peerKey` | `peer1` | `peer2` |
| .NET     | 4.13.0      | `LocalPeer.PeerKeyString` | `PeerKeyString1`* | `PeerKeyString2`* |

*Verify against installed SDK version.

## Implementation Locations

| Platform | File | Change |
|----------|------|--------|
| SwiftUI  | `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift` | `registerSyncStatusObserver`, `registerConnectionsPresenceObserver`, `extractPeerEnrichment` |
| Android  | `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/SystemRepositoryImpl.kt` | `updatePresence` (peer list filter), `buildConnectionCounts` |
| .NET     | `dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | `PublishConnectionCounts`, `MergeSyncInfoWithPresenceGraph` |
