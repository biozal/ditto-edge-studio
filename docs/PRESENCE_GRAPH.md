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

**Peer search** (Presence Viewer tab): the search box rides in the Peers/Viewer
tab row so the canvas keeps its full height. It matches peers by device name or
peer key, case-insensitively, over the **full mesh** — a multi-hop peer is
findable while Direct is ON, because picking it is exactly how the user jumps the
graph over to it. While a query is active, matching peers and every connection
touching a match stay at full opacity and everything else takes the same dim a
click selection gives; search is the **weakest** dim source, so an explicit focus
and a tap-to-isolate selection both win over it. Results list in a card that
floats over the canvas (typing never reflows the graph); picking one focuses that
peer exactly like clicking its pill, flipping Direct off first when needed, and
re-picking the focused peer toggles focus off. Enter/Search focuses the first
non-local hit. The local device is listed but never focusable. Escape (macOS) and
Back (Android) unwind the innermost context first — an open detail card, then the
query — leaving the focus view alone. Query and dimming survive a tab switch.

> ⚠️ **`null` and "empty set" are different states.** `null`
> (`searchMatchKeys` / `searchMatchIds`) means the box is empty: no dimming at
> all. An **empty set** means an active query with no hits, which deliberately
> dims the whole graph — "nothing here" is useful feedback. Conflating the two is
> the defect this distinction exists to prevent, so the decision is made in
> exactly one place per platform (`PresencePeerSearch.matchIds` on Android, the
> view model's `pushSearchMatchesToScene` on SwiftUI).

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

### Peer search

| Platform | File | Role |
|----------|------|------|
| SwiftUI  | `Components/PresenceViewer/PresencePeerSearch.swift` | Candidates, matching, key truncation (Foundation-pure) |
| SwiftUI  | `Components/PresenceViewer/PresencePeerSearchField.swift` | The box + results card (a leaf, so the query never becomes a `MainStudioView.body` dependency) |
| SwiftUI  | `Components/PresenceViewer/PresenceNetworkScene.swift` | `setSearchMatches`, `restingAlpha` precedence, `focusPeer` |
| SwiftUI  | `Views/StudioView/Details/PresenceViewerSK.swift` | Query/pending-focus state, `focusSearchResult`, `handleEscape` |
| SwiftUI  | `Views/StudioView/Details/DetailViews.swift` | Header-row wiring (outside `ViewThatFits` — see the note there) |
| Android  | `ui/mainstudio/presence/PresencePeerSearch.kt` | Candidates, matching, `matchIds` (Compose-free) |
| Android  | `ui/mainstudio/presence/PresencePeerSearchBar.kt` | The box + results card |
| Android  | `ui/mainstudio/presence/PresenceGraphState.kt` | `PresenceFocusPlanner.litPeerIds` / `litEdgeAnchors` — the dim precedence |
| Android  | `ui/mainstudio/presence/PresenceGraphView.kt` | `searchMatchIds` dimming, pending-focus consumption |
| Android  | `ui/mainstudio/PresenceSection.kt` | Header-row wiring, pick routing, Back handling |
| Android  | `viewmodel/MainStudioViewModel.kt` | `presenceSearchQuery`, `presencePendingFocusPeerId` |
