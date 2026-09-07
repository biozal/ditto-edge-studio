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

## Viewer Modes (Direct vs Expanded)

The presence viewer has two modes, toggled by the **Direct** switch (default ON,
`showDirectConnectedOnly`):

- **Direct mode** — only peers with a direct connection to the local device (the
  required filter above), laid out as a compact ring. Entering Direct mode
  fit-zooms the viewport (zoom-out only, never past the user's chosen zoom level).
- **Expanded mode** (Direct OFF) — the full mesh, including multi-hop (indirect)
  peers. The layout spreads rings 1.75× wider and packs each crowded BFS layer
  into multiple concentric visual rings (a later layer never starts until the
  previous one is complete), using measured pill widths so long device names don't
  overlap. This is the mode intended for large meshes (30+ devices).

**Focus mode** (Expanded mode only): tapping a remote peer re-lays-out that peer
at the centre with its direct neighbours on one orbit, magnifies to at least
1.25× (never past the fit for the neighbourhood), and dims the rest of the mesh
to a context backdrop. A top banner ("Focused on \<name\>") shows the exit button;
focus also exits on re-tap of the focused peer, empty-canvas tap, tapping a
dimmed context (non-orbit) peer, or a mode toggle; tapping another orbit peer
refocuses onto it, and tapping the local peer while it's in the orbit is a
no-op. Focus survives tab switches. In Direct mode a tap only dims (selection)
— it never re-lays out.

**Controls**: zoom spans 0.25×–2.0× magnification equivalent (SwiftUI camera
scale 0.5–4.0; Android `Transform` scale 0.25–2.0) via pinch/scroll/buttons; the
reset button recenters on the local peer at 100% and re-seats dragged peers (in
focus mode it only resets the focus zoom). The eye toggle hides the legend,
Direct toggle, and zoom cluster (reset and eye always remain; state survives
tab switches). The SwiftUI app additionally has a background-effects toggle for
the floating-squares layer, which also auto-pauses after 3 s idle.

The engines are kept in lockstep across platforms:
`SwiftUI/EdgeStudio/Components/PresenceViewer/NetworkLayoutEngine.swift`,
`android/.../ui/mainstudio/presence/PresenceGraphLayout.kt`, and the VS Code
extension's `src/presence/NetworkLayoutEngine.ts`.

## Cloud Server Exemption

Peers with `isDittoServer = true` (Ditto Cloud / Big Peer) are always directly connected
via WebSocket. They are added to peer cards via DQL (`system:data_sync_info`) rather than
presence graph filtering, so they are exempt from this filter on all platforms.

## Platform Field Name Reference

| Platform | SDK Version | Local Peer Key | Conn Endpoint 1 | Conn Endpoint 2 |
|----------|-------------|----------------|-----------------|-----------------|
| SwiftUI  | v5          | `localPeer.peerKeyString` | `peerKeyString1` | `peerKeyString2` |
| Android  | v4/v5       | `localPeer.peerKey` | `peer1` | `peer2` |

## Implementation Locations

| Platform | File | Change |
|----------|------|--------|
| SwiftUI  | `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift` | `registerSyncStatusObserver`, `registerConnectionsPresenceObserver`, `extractPeerEnrichment` |
| Android  | `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/SystemRepositoryImpl.kt` | `updatePresence` (peer list filter), `buildConnectionCounts` |
