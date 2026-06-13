# Presence Graph — Android Feature Plan

**Branch:** `release-1.0b5`  
**Author:** Aaron LaBeau  
**Date:** 2026-06-13  
**Status:** Draft — ready for engineering pick-up

---

## 1. Goal

Replace the `"Presence Viewer — Coming Soon"` placeholder in
`android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/PresenceSection.kt`
(line 144–148, the `else` branch of `PresenceContentSection`) with a real
**mesh-topology visualization** of the Ditto presence graph: local peer at
centre, directly connected remote peers in a radial layout, edges coloured by
transport type, and a tap-to-inspect interaction. The feature is a **developer
debug tool**; it is not a customer-facing network editor.

---

## 2. What the iOS App Shows

**Framework:** Custom SpriteKit scene — not a pre-packaged SDK viewer.  
**Files:**
- `SwiftUI/EdgeStudio/Components/PresenceViewerTab.swift` — thin wrapper; delegates to `PresenceViewerSK()`.
- `SwiftUI/EdgeStudio/Views/StudioView/Details/PresenceViewerSK.swift` — SwiftUI `View` that embeds a SpriteKit scene and wires up gestures.
- `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceNetworkScene.swift` — the full scene (739 lines).

**Entities rendered:**
- **Local peer node** — centred, visually distinguished (golden ring).
- **Remote peer nodes** — placed radially via BFS ring layout (`NetworkLayoutEngine`). Multihop peers (not directly connected) can optionally be shown.
- **Cloud node** — synthetic; added when `localPeer.isConnectedToDittoCloud` is `true`. Remote peer cloud status is explicitly *not* shown ("only the local peer's cloud connection is knowable via the presence graph" — `PresenceNetworkScene.swift` line 325).
- **Connection edges** — one line per `(pairKey, connectionType)` tuple, deduplicated. Multiple transport types on the same pair produce parallel offset lines (`offset: ±10 pt` per line).
- **RSSI:** Not rendered in the presence graph (available in `NetworkInterfaceInfo` but not wired into the scene).

**Interaction:** drag-a-node, pan camera (mouse/touch), scroll-wheel / pinch-to-zoom, hover highlight on macOS, connection legend overlay, "Direct Connected Only" toggle.

**Known iOS caveats documented in CLAUDE.md and implemented in `SystemRepositoryImpl.kt`:**

> **Presence Graph Pitfall:** `presenceGraph.remotePeers` returns the full mesh
> topology — **all peers in the network, including multihop peers**. A peer is
> "directly connected" only if the local device's `peerKey` is an endpoint of at
> least one of the peer's connections. Always filter to direct connections before
> building peer cards or counting transports.

The iOS app enforces this filter at the SpriteKit layer via `showDirectConnectedOnly`
(default `true`). Android already enforces it at the repository layer
(`SystemRepositoryImpl.kt` lines 88–97).

---

## 3. Available Data on Android Today

All flows the new view can consume are already produced by existing code. No
new SDK calls are required for P1/P2 delivery.

### 3a. Flows exposed via `PresenceContentSection` / `MainStudioViewModel`

| Flow | Type | Source file : line | Contains |
|------|------|--------------------|----------|
| `peersUiState` | `StateFlow<PeersUiState>` | `StudioSession.kt:133–138` | `localPeer: LocalPeerInfo?`, `remotePeers: List<SyncStatusInfo>` |
| `connectionsByTransport` | `StateFlow<ConnectionsByTransport>` | `StudioSession.kt:140–147` | Per-transport direct-connection counts (bluetooth, lan, p2pWifi, webSocket) |

`PresenceContentSection` already collects `peersUiState` at line 100 — the new
composable receives it as a parameter.

### 3b. Domain model detail

**`SyncStatusInfo`** (`domain/model/SyncStatusInfo.kt`)
- `peerId: String` — unique peer key (use as node ID)
- `deviceName: String?` — display label
- `osInfo: PeerOS` — iOS, Android, macOS, Linux, Windows, Unknown
- `dittoSdkVersion: String?`
- `isDittoServer: Boolean` — cloud server peer
- `connections: List<PeerConnectionInfo>` — direct connections to local peer only (already filtered in `SystemRepositoryImpl.kt` line 150–157)
- `syncedUpToLocalCommitId: Long?`, `lastUpdateReceivedTime: Double?` — useful in peer detail sheet

**`PeerConnectionInfo`** (`domain/model/SyncStatusInfo.kt:31–34`)
- `id: String`
- `type: ConnectionType` — Bluetooth, LAN, P2PWiFi, WebSocket, Unknown

**`LocalPeerInfo`** (`domain/model/LocalPeerInfo.kt`)
- `peerId`, `deviceName`, `sdkLanguage`, `sdkPlatform`, `sdkVersion`

**`ConnectionType`** edge colours (proposed palette, matches iOS legend):
- Bluetooth → `Color(0xFF4E9BFF)` (blue)
- LAN → `Color(0xFF4CAF50)` (green)
- P2PWiFi → `Color(0xFFFF9800)` (amber)
- WebSocket → `Color(0xFF9C27B0)` (purple)
- Unknown → `MaterialTheme.colorScheme.outline`

### 3c. Data NOT yet exposed — gaps for P3+

| Gap | What's missing | Proposed fix |
|-----|---------------|--------------|
| Cloud connection flag | `SyncStatusInfo.isDittoServer == true` covers cloud *server* peers added from DQL metrics, but the raw `DittoPresenceGraph.localPeer.isConnectedToDittoCloud` boolean is not surfaced | Add `isCloudConnected: Boolean` to `LocalPeerInfo` and populate it in `SystemRepositoryImpl.updatePresence()` from `graph.localPeer` |
| Hop count / multihop peers | `SystemRepositoryImpl` filters to direct peers only; full mesh topology is discarded | Add a `rawRemotePeers: List<SyncStatusInfo>` overload to `PeersUiState.Active` if the toggle is desired (optional, defer) |
| RSSI per peer | Not exposed in `SyncStatusInfo` | Not needed for P1/P2; available in `NetworkInterfaceInfo` for the local WiFi link only |

---

## 4. Recommended Approach

### Option (a) — Use `live.ditto:dittopresenceviewer` (Maven Central)

**Maven verdict:** `live.ditto:dittopresenceviewer:3.0.1` **exists** on Maven Central
(latest as of 2026-06-13, `.aar`, MIT licence). However, inspection of its POM
reveals a **hard dependency on `androidx.webkit`** — the viewer is
**WebView-based** (renders a bundled JavaScript graph via a `WebView`), not a
native Compose/Canvas implementation. Additional concerns:

- Latest version (3.0.1) was published November 2024; it depends on Ditto SDK
  `[4.5.0,)` — compatible with our Ditto 5.0.1, but the transitive Kotlin
  stdlib pin (`kotlin-stdlib-jdk8:1.8.10`) predates Kotlin 2.x and introduces
  a version conflict with our Kotlin 2.3.21 build.
- The WebView rendering cannot match Material 3 theming, dark mode, or
  the RAL brand palette without opaque hacks.
- No Compose-native interaction model (no semantics, no TalkBack integration).

**Do not use this artifact.**

### Option (b) — Custom Compose Canvas visualization (RECOMMENDED)

Build a pure-Kotlin/Compose `PresenceGraphView` using `Canvas` + positioned
`Box` composables. Consumes `PeersUiState` directly from the existing flow.
Fully themeable, no WebView, no extra dependency, full a11y control.

### Option (c) — Embed via `AndroidView`

`DittoPresenceViewer` is a Compose-first `.aar`, not a `UIView`/`NSView` — the
`AndroidView` wrapper approach is not applicable here.

**Recommendation: Option (b).** The existing repository layer already exposes
every data field needed; a Compose `Canvas` approach delivers a native,
themeable, a11y-friendly graph with zero new dependencies.

---

## 5. Design for Option (b)

### 5a. File layout

| File | Action | Notes |
|------|--------|-------|
| `ui/mainstudio/PresenceGraphView.kt` | **Create** | Top-level composable; owns `Canvas` + node composables |
| `ui/mainstudio/PresenceGraphLayout.kt` | **Create** | Pure-function radial layout algorithm; no Compose imports → fully unit-testable |
| `domain/model/PresenceGraphState.kt` | **Create** | `data class PeerNode(id, label, os, isLocal, isCloud, connections)` and `data class PeerEdge(fromId, toId, type)` — derived from `PeersUiState.Active` |
| `ui/mainstudio/PresenceSection.kt` | **Modify** | Replace `else` branch (lines 138–149) with `PresenceGraphView(peersUiState)` |

No ViewModel is needed: `PresenceGraphView` accepts `PeersUiState` as a
parameter (pure UI; state is already owned by `PresenceContentSection` via
`viewModel.peersUiState`).

### 5b. Data shape mapping

```kotlin
// domain/model/PresenceGraphState.kt
data class PeerNode(
    val id: String,          // SyncStatusInfo.peerId / LocalPeerInfo.peerId
    val label: String,       // deviceName ?: "Unknown"
    val os: PeerOS,
    val isLocal: Boolean,
    val isCloud: Boolean,    // SyncStatusInfo.isDittoServer
    val sdkVersion: String?,
    val connections: List<PeerConnectionInfo>,  // edge list for this peer
)

data class PeerEdge(
    val fromId: String,
    val toId: String,
    val type: ConnectionType,
)

// Derived in PresenceGraphView from PeersUiState.Active:
fun PeersUiState.Active.toGraphState(): Pair<List<PeerNode>, List<PeerEdge>>
```

### 5c. Rendering: Compose `Canvas` vs node composables

**Use Compose `Canvas` for edges; use positioned `Box` composables for nodes.**

Rationale:
- Edges (lines/curves) are most natural in `Canvas` — stroke paths, per-transport
  colour, offset parallel lines for multi-transport pairs.
- Nodes need text labels, OS icons, and tap targets — these are easiest as
  `Box` composables placed in a `Layout` at calculated positions.
- Separating the two layers mirrors the iOS `connectionsLayer` / `peerNodesLayer`
  z-ordering and keeps each concern independently testable.

The host composable is a `Box(Modifier.fillMaxSize())` with:
1. A `Canvas` filling the full bounds — draws all edges.
2. A `Layout` over the same bounds — places a `PeerNodeChip` at each calculated
   position, enabling normal Compose semantics and click handling.

### 5d. Layout algorithm

Implemented as a pure Kotlin function in `PresenceGraphLayout.kt`:

```
fun calculateRadialLayout(
    localId: String,
    nodes: List<PeerNode>,
    bounds: Size,
    ringRadiusDp: Float = 120f,
): Map<String, Offset>
```

Rules:
- **≤ 20 peers:** BFS ring layout — local peer at `bounds.center`; all direct
  peers placed evenly on a circle of radius `ringRadiusDp` dp. Cloud peer, if
  present, is placed at `(center.x, center.y - ringRadiusDp * 1.5)` (top
  centre, distinct from peer ring).
- **21–50 peers:** Two concentric rings — ring 0 = first 10 by sort order,
  ring 1 = remainder. Outer ring radius = `ringRadiusDp * 1.8`.
- **> 50 peers:** Fall back to a scrollable `LazyColumn` of `RemotePeerCard`
  items (identical to `ConnectedPeersScreen` but without network-interface
  cards). Display a banner: `"Too many peers for graph view (N) — showing list"`.
- Positions are recalculated when node count changes; animated with
  `animateFloatAsState` / `Animatable` (0.35 s ease-in-out).

**Thresholds (explicit):** graph mode ≤ 50 peers; list fallback > 50 peers.

### 5e. Interaction

| Gesture | Behaviour |
|---------|-----------|
| Tap a node | Opens `PeerDetailSheet` (a `ModalBottomSheet`) showing `RemotePeerCard` / `LocalPeerCard` content for that peer |
| Long-press background | Not implemented (debug tool, not an editor) |
| Pinch-to-zoom | `transformable(rememberTransformableState)` on the host `Box`; scale clamped to `0.5f..2.5f` |
| Two-finger pan | Same `TransformableState` as zoom |
| Keyboard — Tab | Focus cycles through peer nodes in insertion order |
| Keyboard — Enter/Space | Activates focused node (opens detail sheet) |
| Hover (large-screen pointer) | `Modifier.hoverable` + `indicationInteraction` — highlights node border |

**Semantics for TalkBack:**
```kotlin
Modifier.semantics {
    contentDescription = "${node.label}, ${node.os.displayName}, " +
        "${node.connections.size} connection(s)"
    role = Role.Button
}
```

---

## 6. Phasing

### P1 — Static layout + nodes (independently shippable)

- Create `PresenceGraphLayout.kt` with the radial/ring layout function.
- Create `domain/model/PresenceGraphState.kt` with `PeerNode`/`PeerEdge` types
  and `PeersUiState.Active.toGraphState()`.
- Create `PresenceGraphView.kt`: node composables placed at calculated positions,
  no edges yet, no interaction. List fallback for > 50 peers.
- Replace placeholder in `PresenceSection.kt` lines 138–149.
- Unit tests for layout function (see §7).
- Compose UI test asserting node count from fake state.

**Definition of done:** Placeholder is gone. Peer nodes appear at correct
positions with labels. No edges. Passes `./gradlew check`.

### P2 — Edge transports + colour legend (independently shippable after P1)

- Add `Canvas` edge layer to `PresenceGraphView`.
- Implement parallel-offset lines for multi-transport pairs.
- Add colour legend overlay (matching iOS bottom-left legend).
- Add `ConnectionType`-to-`Color` mapping in theme layer.
- Add cloud peer node (requires the `isCloudConnected` gap fix from §3c — add
  `isCloudConnected: Boolean` to `LocalPeerInfo` and populate in
  `SystemRepositoryImpl.updatePresence()`).

**Definition of done:** Edges are drawn, coloured, and labelled. Cloud node
appears when connected. Legend is legible in both light and dark mode.

### P3 — Interaction + a11y (independently shippable after P2)

- Pinch/pan `TransformableState`.
- Tap-to-open `PeerDetailSheet`.
- Keyboard navigation (Tab/Enter).
- `Modifier.semantics` on each node.
- "Direct Connected Only" toggle (matching iOS) — reuses existing
  `SystemRepositoryImpl` filter; toggle just controls whether multihop peers
  from a future raw-graph flow are shown, defaulting to direct-only.
- Full a11y audit on Samsung tablet + Pixel 10a.

**Definition of done:** TalkBack can navigate all nodes. Tap opens detail sheet.
Pinch zoom works on touch devices. Keyboard navigation works in desktop windowing.

---

## 7. Test Strategy

### Unit tests (pure Kotlin, no Android, no Compose — `app/src/test/`)

File: `PresenceGraphLayoutTest.kt`

| Test | Assertion |
|------|-----------|
| `singlePeer_localOnly` | Layout produces exactly 1 position; local peer at `bounds.center` |
| `fivePeers_allInBounds` | All 5 positions are within `[0, bounds.width] × [0, bounds.height]` |
| `twentyPeers_ring0Only` | All 20 remote peers placed on single ring; no peer overlaps local peer |
| `twentyOnePeers_twoRings` | 21 peers → outer ring used; inner ring ≤ 10 entries |
| `fiftyOnePeers_fallback` | Returns `null` (or sentinel) indicating list fallback |
| `edgesMatchConnections` | `toGraphState()` produces exactly `N` edges from `N` `PeerConnectionInfo` items |
| `localPeerAtCentre` | After layout, local peer offset == `bounds.center` (±1f tolerance) |

### Compose UI test (instrumented — `app/src/androidTest/`)

File: `PresenceGraphViewTest.kt`

```kotlin
@Test
fun fivePeers_showsFiveNodeLabels() {
    val state = PeersUiState.Active(
        localPeer = fakeLocalPeer(),
        remotePeers = List(5) { i -> fakeSyncStatusInfo("peer-$i", "Device $i") },
    )
    composeTestRule.setContent {
        EdgeStudioTheme { PresenceGraphView(peersUiState = state) }
    }
    (0..4).forEach { i ->
        composeTestRule.onNodeWithText("Device $i").assertIsDisplayed()
    }
}

@Test
fun fiftyOnePeers_showsListFallbackBanner() { ... }

@Test
fun emptyState_showsOnlyLocalPeer() { ... }
```

**Device matrix:**

| Device | Serial | Test type | Notes |
|--------|--------|-----------|-------|
| Samsung Galaxy Tab R5GL15XPVGA | R5GL15XPVGA | Visual verification only (NOT wipe-safe) | Primary device; confirm layout at large width |
| Pixel 10a | 58300DLCR0000L | `connectedAndroidTest` (wipe-safe) | Run instrumented Compose test here |
| Pixel Tablet | benchmark rig | Visual + performance | Confirm 60 fps with 20-peer graph |

Per project device rules: `ANDROID_SERIAL=58300DLCR0000L ./gradlew connectedAndroidTest`
for all instrumented runs. Do **not** run `connectedAndroidTest` against the Samsung
tablet (holds real database configurations).

---

## 8. Known Risks

### Presence-graph data-shape pitfall (already mitigated in repository)

`presenceGraph.remotePeers` returns **all peers in the mesh, not just directly
connected ones** (documented in root `CLAUDE.md`, "Presence Graph Pitfall";
enforced in `SystemRepositoryImpl.kt` lines 88–97). `PeersUiState.Active.remotePeers`
already contains only direct peers. The graph composable must **not** re-fetch
from `DittoPresenceGraph` directly — it must consume the `PeersUiState` flow to
stay consistent with the filtering already in place.

### Performance with large meshes

SpriteKit (iOS) runs the scene at 60 fps with continuous SKAction updates. A
Compose `Canvas` redraws on every state change — with `animateFloatAsState` for
peer positions, each animation tick triggers a full recomposition of the Canvas.
Mitigation: keep the `Canvas` in a separate `key()`-stable composable; use
`remember { }` for the edge path calculations; cap animation to `Animatable`
with `tween(350)`. Benchmark the 20-peer case on Pixel Tablet before shipping P2.

### `dittopresenceviewer` version mismatch (already ruled out)

`live.ditto:dittopresenceviewer:3.0.1` (the only published artifact) depends on
`kotlin-stdlib-jdk8:1.8.10` and Compose BOM `2024.06.00`, both older than this
project's Kotlin 2.3.21 / Compose BOM `2026.05.01`. Even if adopted, the
WebView-based rendering would not honour Material 3 theming or the RAL palette.
The artifact is **not used** in this plan.

### What we explicitly do NOT build

- Network editor / peer kick / forcible disconnect controls.
- RSSI heatmap or signal-strength colouring (data not in `SyncStatusInfo`).
- Multihop graph (full mesh beyond direct peers) — out of scope; toggle is
  wired to existing direct-only filter.
- Any changes to `ConnectedPeersScreen` (Tab 0) — the two tabs remain distinct
  views with no code sharing beyond shared domain models.

---

## 9. References

### Android files cited

| File | Purpose |
|------|---------|
| `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/PresenceSection.kt` | Placeholder location (lines 138–149 to replace) |
| `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ConnectedPeersScreen.kt` | Peer list (Tab 0); must not be duplicated |
| `android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioSession.kt` | `peersUiState` and `connectionsByTransport` flows (lines 133–147) |
| `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/SystemRepositoryImpl.kt` | Presence observation, direct-peer filter (lines 88–97), `DittoPresenceGraph` usage |
| `android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/SyncStatusInfo.kt` | `SyncStatusInfo`, `PeerConnectionInfo`, `ConnectionType`, `PeerOS` |
| `android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/LocalPeerInfo.kt` | Local peer model |
| `android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/ConnectionsByTransport.kt` | Transport counts |
| `android/app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/ConnectedPeersScreenTest.kt` | Pattern for Compose UI tests to follow |

### SwiftUI counterpart files

| File | Purpose |
|------|---------|
| `SwiftUI/EdgeStudio/Components/PresenceViewerTab.swift` | SwiftUI entry wrapper |
| `SwiftUI/EdgeStudio/Views/StudioView/Details/PresenceViewerSK.swift` | SwiftUI/SpriteKit host |
| `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceNetworkScene.swift` | Full SpriteKit scene (reference for layout algorithm, edge deduplication, interaction patterns) |

### SDK / external references

- Ditto SDK 5.0 `DittoPresenceGraph` / `DittoPeer` — used in `SystemRepositoryImpl.kt`; no direct use from UI layer.
- `live.ditto:dittopresenceviewer:3.0.1` on Maven Central — **not adopted**; WebView-based, Kotlin 1.8 dependencies, incompatible with project's Kotlin 2.3 + Compose BOM 2026.
- Ditto Android Tools source: https://github.com/getditto/DittoAndroidTools (reference only).
- CLAUDE.md root — "Presence Graph Pitfall" warning.
- `docs/android/ARCHITECTURE.md` — layer rules (UI must not call SDK directly).
