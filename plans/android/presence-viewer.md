# Android Presence Viewer — SwiftUI Parity Plan (No Background Particles)

**Target file (after approval):** `plans/android/presence-viewer.md`
**Supersedes:** `plans/android/presence-graph.md` (the older Canvas-only plan)
**Branch:** `release-1.0b5`
**Author:** Aaron LaBeau
**Date:** 2026-06-15

---

## Context

The Android Edge Studio currently renders `"Presence Viewer — Coming Soon"` in `PresenceSection.kt:138–149`. iOS (`PresenceViewerSK`) ships a fluent SpriteKit visualization with BFS ring layout, Bézier edges with per-transport dash patterns, drag-a-node with real-time edge updates, pinch/scroll zoom, hover highlights, and (in iOS only) an animated 160-diamond background.

**Decision:** the animated background is **not** ported. The graph itself ports to full iOS parity. The background is replaced with a solid `MaterialTheme.colorScheme.surface` color. This trims the perf hot-path entirely and lets us lean on idiomatic Compose animation APIs instead of a bespoke frame-loop.

Hard constraints (re-confirmed by user):
- **Single PR** — no phasing.
- **minSdk 28** (Android 9 Pie / 2018-era hardware) — must run fluently on Galaxy S9 / Pixel 3a class devices.
- **Full iOS parity** for everything except the particle background.

Outcome: replace the placeholder with a `PresenceGraphView` composable that visually and behaviorally matches `PresenceViewerSK` (minus the starry background), inside the project's existing Compose + Material 3 stack with zero new dependencies.

---

## Drawing-Framework Decision

The user asked: "Skia, or something better?"

**Recommendation: Compose `Canvas` / `Modifier.drawBehind`. No new dependency. No `AndroidView`. No bespoke frame loop.**

Rationale:

- **Compose Canvas already IS Skia.** Compose draws through `RenderNode` → HWUI → Skia → GPU. There is no "use Skia directly" alternative on Android that delivers more performance than what `drawBehind` already gives you — Skia is the backend.
- **Alternatives ruled out (sharper without particles):**
  - `AndroidView` wrapping a custom `View.onDraw` — the ~5% perf gain when continuously redrawing falls to **0%** since the scene is idle most of the time. Lose Compose theme/semantics/Material integration for nothing.
  - `GLSurfaceView` / OpenGL ES — overkill in the original plan, more overkill now.
  - `SurfaceView` + render thread — the thing you'd render on the other thread no longer exists.
  - `RuntimeShader` / AGSL — minSdk 33; blocked by our minSdk 28.
  - `GraphicsLayer.record` — minSdk 30; blocked.
  - `live.ditto:dittopresenceviewer:3.0.1` — WebView-based, Kotlin 1.8 stdlib pin conflicts with our Kotlin 2.3.21.
  - Game engines (libGDX, Korge) — third-party deps, license/governance overhead, vast mismatch with the rest of the project.
- **Animation strategy:** standard Compose APIs — `Animatable` for per-peer enter/exit and layout-transition tweens, `animateFloatAsState` for the simple cases, `rememberInfiniteTransition` for the selected-edge glow pulse. These only recompose during active animations; idle cost is zero.

Performance budget on Galaxy S9 (Snapdragon 845, 2018):
- 16.6 ms/frame at 60 Hz.
- **Idle (no interaction, no animations): ~0 ms.** Canvas does not redraw when no observed state changes.
- **During drag (worst case):** 25 `drawRoundRect` (peer pills) + 50 `drawPath` Bézier edges with `PathEffect.dashPathEffect` ≈ **3.5 ms/frame**. Plenty of headroom.
- **During topology change tween (500 ms):** 25 peers + 50 edges + per-peer animation state ≈ **4.0 ms/frame**. Still inside budget.

No `FrameTimeProbe`, no kinematic integrator, no continuous render loop. The S9-class headroom is now so generous that the auto-scale safety net is unnecessary.

---

## Architecture

### File layout

| File | Action | Purpose |
|------|--------|---------|
| `ui/mainstudio/presence/PresenceGraphView.kt` | **Create** | Top-level composable. Owns gesture state, transform state, per-peer animation state. Renders edges and nodes via `drawBehind`. |
| `ui/mainstudio/presence/PresenceGraphLayout.kt` | **Create** | Pure-Kotlin BFS ring-layout algorithm. No Compose imports → unit-testable on JVM. |
| `ui/mainstudio/presence/PresenceGraphRenderer.kt` | **Create** | `DrawScope` extension functions: `drawEdge`, `drawPeerNode`. Pure functions of state + DrawScope. |
| `ui/mainstudio/presence/PresenceGraphState.kt` | **Create** | `PeerNode`, `PeerEdge`, `Transform` data classes. `PeersUiState.Active.toGraphModel(): PresenceGraphModel` projection. |
| `ui/mainstudio/presence/ConnectionStyles.kt` | **Create** | Per-`ConnectionType` color + `PathEffect.dashPathEffect` constants. Single source of truth replacing the hardcoded gradients in `RemotePeerCard.kt:285–301`. |
| `ui/mainstudio/PresenceSection.kt` | **Modify** | Replace the `else` branch (lines 138–149) with `PresenceGraphView(peersUiState)`. Pass through the existing `showDirectConnectedOnly` toggle from `MainStudioViewModel`. |
| `domain/model/LocalPeerInfo.kt` | **Modify** | Add `isCloudConnected: Boolean`. |
| `data/repository/SystemRepositoryImpl.kt` | **Modify** | In `updatePresence()`, populate `LocalPeerInfo.isCloudConnected` from `graph.localPeer.isConnectedToDittoCloud` (matches iOS — only the local peer's cloud status is knowable). |
| `viewmodel/MainStudioViewModel.kt` | **Modify** | Add `showDirectConnectedOnly: StateFlow<Boolean>` and `toggleDirectConnectedOnly()`. Default `true`. |
| `plans/android/presence-graph.md` | **Delete** | Superseded by this plan once committed at `plans/android/presence-viewer.md`. |

**Removed vs. the prior draft:** `FrameTimeProbe.kt` (no longer needed without particles).

### Data flow

```
DittoPresenceGraph (SDK callback, IO thread)
   ↓
SystemRepositoryImpl.updatePresence()   ← already exists; add isCloudConnected
   ↓
StudioSession.peersUiState (StateFlow<PeersUiState>)   ← unchanged
   ↓
PresenceSection.PresenceContentSection (collectAsStateWithLifecycle)
   ↓
PresenceGraphView(peersUiState, showDirectConnectedOnly)
   ├─ PeersUiState.Active.toGraphModel() → PresenceGraphModel(nodes, edges)
   ├─ calculateRadialLayout(model) → Map<peerId, Offset>          [PresenceGraphLayout.kt]
   ├─ rememberPeerAnimations(model) → Map<peerId, Animatable>     [Compose stdlib]
   └─ Canvas / drawBehind { drawEdges(); drawNodes(); }
```

The graph view is pure UI — no ViewModel state of its own beyond ephemeral gesture/transform state held in `remember`. Filter state lives in `MainStudioViewModel` (mirrors iOS).

---

## Visual Layers (back to front)

### Layer 1 — Background

`Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface))`. That's it.

(Removed in this revision: the iOS `FloatingSquaresLayer` of 160 drifting/pulsing/spinning diamonds.)

### Layer 2 — Edges (`connectionsLayer` equivalent)

For each `PeerEdge`, draw a quadratic Bézier from `fromPos` to `toPos`:

- **Control point:** perpendicular offset = `min(distance × 0.15, 60.dp)`. For "arcOutward" edges (peer-to-peer, neither endpoint is local), push radially outward from origin instead (matches `ConnectionLine.swift` lines that route around the node cluster).
- **Stroke:** 2 dp default, 3 dp when highlighted.
- **Dash patterns** (single source of truth in `ConnectionStyles.kt`, matching iOS `ConnectionLine.swift` exactly):

  | Transport | Color (light) | Color (dark) | Dash (px) |
  |-----------|---------------|--------------|-----------|
  | Bluetooth | `#0066D9` | `#3D8FE8` | `[3, 2]` |
  | LAN (AccessPoint) | `#0D8540` | `#1FA858` | `[16, 3]` |
  | P2P WiFi | `#C71A38` | `#E04657` | `[6, 3]` |
  | WebSocket | `#D97A00` | `#F09518` | `[10, 3, 2, 3]` |
  | Cloud | `#7326B8` | `#9445D6` | `[8, 4]` + decorative circles |

- **Multi-transport pairs:** deduplicate by `(sortedPairKey, type)` (same as iOS `seenPairTypes`). When N>1 lines exist between the same pair, distribute parallel offsets evenly (`±10 dp` for N=2, even step for N>2).
- **Cloud edges:** in addition to the dashed stroke, draw small filled circles (radius 3 dp, alpha 0.8) sampled along the curve every 40 dp using `PathMeasure.getPosTan()`.
- **Highlighted edges (when an endpoint peer is selected):** full alpha, 3 dp stroke, plus an alpha pulse between 0.8 and 1.0 at 1.5 Hz driven by `rememberInfiniteTransition` — **only active while at least one peer is selected**. When the user deselects, the infinite transition is cancelled by removing it from composition, so idle cost is zero.

`PathEffect.dashPathEffect(intervals, phase)` is allocated once per `ConnectionType` in `remember { }`. `Path` objects are kept in a per-edge pool keyed by edge id and reset (`reset()` + `moveTo` + `quadraticTo`) when an endpoint moves — not allocated per frame.

### Layer 3 — Peer nodes (`peerNodesLayer` equivalent)

Each peer is rendered as a pill (rounded-rect with corner radius = height / 2):

- **Local peer** ("Me"): blue fill (`MaterialTheme.colorScheme.primary`), white text "Me".
- **Remote peer**: green fill (`#0D8540`), white text = device name.
- **Cloud peer** (synthetic): purple fill (`#7326B8`), text "Ditto Cloud".
- **Font:** `FontFamily.SansSerif`, weight 700, size 9.sp (matches iOS Helvetica-Bold 9pt).
- **Pill sizing:** measured once per peer via `TextMeasurer.measure(text)` cached in `remember(text)`. Width = `textWidth + 22.5 dp`, height = 22.5 dp.
- **Appearance animation:** new peer starts at scale 0.5 + alpha 0 at the center; uses two `Animatable<Float>` (`scale`, `alpha`) `launch`ed in a `LaunchedEffect(peerId)` to animate to `(1.0, 1.0)` over 400 ms with `tween(easing = FastOutSlowInEasing)`. Position is tweened separately via a third `Animatable<Offset>` so layout transitions reuse the same machinery.
- **Disappearance:** triggered when a peer leaves the model. We keep the peer in a `mutableStateMapOf` until its exit animation completes (scale → 0.5, alpha → 0, position → center over 300 ms ease-in), then remove.
- **Highlight (selected/hovered):** scale animates to 1.1× over 150 ms ease-out via `animateFloatAsState`.

Tap targets and a11y are provided by a **parallel Layout layer**: invisible `Box`es positioned at the same coordinates with `Modifier.semantics { contentDescription = ...; role = Role.Button }`. This keeps drawing fast (no per-node composables in the draw path) while preserving TalkBack and keyboard focus.

---

## Layout Algorithm (port of `NetworkLayoutEngine`)

`PresenceGraphLayout.kt`:

```kotlin
data class LayoutResult(
    val positions: Map<String, Offset>,   // peerId → position (origin = center)
    val ringAssignments: Map<Int, List<String>>,
    val ringRadii: Map<Int, Float>,
)

fun calculateRadialLayout(
    localPeerId: String,
    nodes: List<PeerNode>,
    edges: List<PeerEdge>,
    bounds: Size,
): LayoutResult
```

Behavior (line-for-line port of iOS `NetworkLayoutEngine.swift`):

1. Local peer at `Offset(0, 0)` (ring 0).
2. BFS from local peer assigns each reachable neighbor to the next ring outward.
3. **Ring 1** (direct neighbors): sort by inter-peer edge count (greedy double-ended path), distribute evenly around 360°, starting at 90°.
4. **Ring N (N ≥ 2)** (multi-hop): each peer placed at the angle of its BFS parent ± a small spread (capped at 60° total) so the BFS-parent edge runs radially outward, not diagonally.
5. **Disconnected peers:** assigned to the outermost ring.
6. **Cloud peer** (synthetic, only present if `localPeer.isCloudConnected`): placed at the top center, at `1.5 × ringRadius_1` above origin.

Constants (matching iOS):
- `baseRadius` = 123.75 dp
- `radiusIncrement` = 101.25 dp per outer ring
- `minAngularSeparation` = 15°
- Ring radii lifted by overlap-avoidance: `max(formula, peerDiameter + 20 dp)`.

Output positions are translated by `bounds.center` for actual canvas coordinates.

### Layout deferral during interaction

Matches iOS: when the user is actively dragging or panning (`isUserInteracting = true`), incoming presence updates are stored but their layout recompute is deferred until `pointerInteractionEnded`. Without this, dragging a node while a sync update arrives causes the node to teleport out from under the user's finger.

---

## Interaction Model

| Gesture | Behavior | Implementation |
|---------|----------|----------------|
| Tap a peer | Peer scales 1.1×; all incident edges enter highlighted state | `Modifier.pointerInput` + `detectTapGestures(onTap)` on the parallel semantics layer |
| Drag a peer | Peer follows finger; incident edges update each frame | `detectDragGestures(onDragStart, onDrag)` with hit-test against the layout positions |
| Pan background | Camera translates | `detectDragGestures` on the canvas (when the touchDown didn't hit a peer) — updates `Transform.offset` |
| Pinch zoom (2-finger) | Camera scales 0.5×–2.5× | `detectTransformGestures { _, _, zoom, _ → transform.scale *= zoom }` |
| Scroll wheel (desktop windowing) | Camera scales 0.5×–2.5× | `awaitPointerEvent` filtered to `PointerEventType.Scroll` |
| Hover (cursor / Chromebook) | Peer enters highlight state | `awaitPointerEvent` filtered to `PointerType.Mouse` and `PointerEventType.Move` |
| Keyboard Tab | Focus cycles through peers | Compose semantics on the parallel layer |
| Keyboard Enter/Space | Activates focused peer (= tap) | Standard a11y handler on each semantics Box |

`Transform` is a single `data class Transform(val offset: Offset, val scale: Float)` held in `remember { mutableStateOf(Transform.Identity) }`. All edge/node coordinates are multiplied by `scale` and added to `offset` inside `drawBehind` — updating `Transform` invalidates the draw layer but doesn't recompose children.

Zoom controls (+/–/percentage chip in the bottom-right corner) update the same `Transform`.

---

## Performance Strategy (Galaxy S9 / Pixel 3a budget)

1. **Idle = zero work.** With no continuous background, the canvas does not redraw unless `Transform`, a peer's `Animatable`, or a `PeerEdge` change. Compose's snapshot system gives this for free.
2. **Animations use standard Compose APIs.** `Animatable` for tweens, `animateFloatAsState` for simple cases, `rememberInfiniteTransition` only for the highlight-glow pulse and only while a peer is selected.
3. **Pool what's reused.**
   - One `Path` per edge, reset when endpoints move.
   - One `Paint` per `ConnectionType` + one per peer state.
   - `PathEffect.dashPathEffect` is `remember`ed per type.
4. **No `Color()` allocations in `drawBehind`.** Pre-resolved into `Color` instances at composition time (theme-aware via `MaterialTheme.colorScheme`).
5. **`TextMeasurer` per peer**, cached in `remember(deviceName)` so pill width is measured once per peer until the name changes.
6. **No `LazyColumn` fallback for > 50 peers** — different from the old plan. The viewer scales to ~200 nodes at 60 fps on minSdk 28 hardware (each peer is ~120 µs to draw). Past 200, the BFS layout itself becomes unreadable visually long before it becomes slow. Just keep drawing; users can pinch-out to see more.
7. **Off-screen culling.** Edges and peers fully outside the visible viewport (after transform) are skipped in `drawBehind`. Adds ~5 lines, saves a measurable fraction on small windows / partial visibility.

The headroom on S9 is now so generous that the prior plan's `FrameTimeProbe` adaptive scaling is unnecessary and has been removed.

---

## Repository Gap to Close

The iOS scene reads `localPeer.isConnectedToDittoCloud` directly. The Android `LocalPeerInfo` model currently has no equivalent field.

**Add** to `domain/model/LocalPeerInfo.kt`:
```kotlin
val isCloudConnected: Boolean,
```

**Populate** in `data/repository/SystemRepositoryImpl.kt` inside `updatePresence()`:
```kotlin
val local = LocalPeerInfo(
    peerId = graph.localPeer.peerKeyString,
    deviceName = graph.localPeer.deviceName,
    sdkLanguage = …,
    sdkPlatform = …,
    sdkVersion = …,
    isCloudConnected = graph.localPeer.isConnectedToDittoCloud,  // ADD
)
```

Per iOS comment in `PresenceNetworkScene.swift:323–325`: remote peer cloud status is **not** knowable via the presence graph — only the local device's connection. The graph shows exactly one cloud edge, from local → synthetic cloud node, when this flag is true.

---

## "Direct Connected Only" Toggle (iOS parity)

`SystemRepositoryImpl.kt:88–97` already filters `remotePeers` to direct connections only — so the *peer list* is always direct-only. The toggle only affects whether **remote-to-remote edges** (peer A ↔ peer B, neither of which is local) are drawn in the graph.

State lives in `MainStudioViewModel`:
```kotlin
private val _showDirectConnectedOnly = MutableStateFlow(true)
val showDirectConnectedOnly: StateFlow<Boolean> = _showDirectConnectedOnly.asStateFlow()
fun toggleDirectConnectedOnly() { _showDirectConnectedOnly.value = !_showDirectConnectedOnly.value }
```

`PresenceGraphView` consumes it and applies an edge filter inside `toGraphModel()`. UI: a Material 3 `Switch` in the top-right overlay (same position as iOS), label "Direct Connected", caption "Show only edges that involve this device".

---

## Replacement of the Placeholder

In `PresenceSection.kt` `PresenceContentSection`, replace lines 138–149 (the `else` branch of the `selectedTabIndex` `when`):

```kotlin
else -> {
    val showDirectOnly by viewModel.showDirectConnectedOnly.collectAsStateWithLifecycle()
    PresenceGraphView(
        peersUiState = peersUiState,
        showDirectConnectedOnly = showDirectOnly,
        onToggleDirectConnectedOnly = { viewModel.toggleDirectConnectedOnly() },
        modifier = Modifier.fillMaxSize(),
    )
}
```

No other changes to `PresenceSection.kt`. The Settings gear and `TransportConfigSheet` remain untouched.

---

## Test Strategy

### Unit tests (`app/src/test/`, JVM, no Android)

| File | Test | Assertion |
|------|------|-----------|
| `PresenceGraphLayoutTest.kt` | `singlePeer_localAtCenter` | 1 position; local peer at `Offset.Zero` (±1f) |
| | `fivePeers_allOnRing1` | All 5 direct peers have `distance == baseRadius` (±1f) and unique angles |
| | `twentyOnePeers_twoRings` | Ring 0 = local; ring 1 ≤ 10 peers; ring 2 holds remainder |
| | `multihopPeer_placedBehindParent` | A peer reachable only via peer P shares P's angle (±30°) |
| | `cloudPeer_atTopCenter` | When `isCloudConnected = true`, cloud node sits at `Offset(0, -1.5f * baseRadius)` |
| | `disconnectedPeer_outermostRing` | Peer with no edges to local goes to the outermost ring |
| | `seenPairTypes_dedupes` | `(A, B, bluetooth)` + `(B, A, bluetooth)` produces exactly 1 edge |
| | `directConnectedOnly_dropsRemoteToRemote` | Edge `P1↔P2` (no local endpoint) is dropped when filter on, kept when off |
| `PresenceGraphStateTest.kt` | `toGraphModel_emptyRemotePeers_onlyLocal` | `nodes.size == 1`, `edges.isEmpty()` |
| | `toGraphModel_cloudFlag_synthesizesCloudNode` | Cloud node + 1 cloud edge added when flag true; removed when flag false |
| `ConnectionStylesTest.kt` | `dashPatternsMatchIOS` | Each `ConnectionType`'s dash array matches the iOS `[3,2] / [16,3] / [6,3] / [10,3,2,3] / [8,4]` table |

**Removed vs. the prior draft:** `ParticleKinematicsTest`, `FrameTimeProbeTest` (subjects deleted).

### Instrumented tests (`app/src/androidTest/`, **Pixel 10a only** — `ANDROID_SERIAL=58300DLCR0000L`)

`PresenceGraphViewTest.kt`:

| Test | Assertion |
|------|-----------|
| `fivePeers_rendersFiveSemanticsNodes` | `onAllNodesWithRole(Button).filter(hasContentDescriptionContaining("Device")).assertCountEquals(5)` |
| `tapNode_highlightsConnectedEdges` | Tap on `"Device 1"`, then `onNode(...isHighlighted...).assertExists()` (custom semantics property `IsHighlighted`) |
| `dragNode_movesPeerPosition` | After `performTouchInput { down(); moveBy(100, 100); up() }`, `onNode(...).fetchSemanticsNode().positionInRoot` changed by ~(100, 100) |
| `directConnectedToggle_hidesPeerToPeerEdges` | Toggle off → semantic edge count includes remote-remote; toggle on → drops |
| `emptyState_showsOnlyMe` | Local peer pill visible, no other nodes |
| `cloudConnection_showsCloudNode` | `onNodeWithContentDescription("Ditto Cloud").assertIsDisplayed()` |
| `pinchZoom_changesTransformScale` | Two-finger pinch by 1.5× → semantic `Scale` increases |

### Visual / perf verification (Samsung Tab + Pixel Tablet, **not** wipe-safe — visual only)

- Run app on Samsung tablet `R5GL15XPVGA` (primary). Visually confirm 60 fps with a 20-peer mesh during drag.
- Pixel Tablet (benchmark rig): enable GPU profiling overlay; verify 95th-percentile frame ≤ 16 ms with 25 peers + 50 edges during a topology-change tween (the highest-load steady state).
- Pixel 10a (`58300DLCR0000L`): run `connectedAndroidTest`. This is the wipe-safe test device.
- **Manual minSdk 28 check:** install on an emulator running API 28 (Android 9 Pie). Verify drag and pinch remain smooth and animations complete without missed frames.

### Tooling

- `./gradlew check` — passes unit tests + lint (`forbidNonAdaptiveSizeApis` task does not affect this code).
- `ANDROID_SERIAL=58300DLCR0000L ./gradlew connectedAndroidTest` — passes instrumented tests.

---

## Verification (manual smoke after implementation)

1. Connect Samsung tablet to one Pixel 10a; open Edge Studio on both; ensure both connect to the same Ditto database with peer-to-peer enabled.
2. On the Samsung tablet, switch to the **Presence Viewer** tab.
3. **Expected:** the Pixel 10a peer appears with a fade-in + scale-up animation, placed on ring 1. A dashed edge (color matches the active transport: blue for Bluetooth, green for LAN) connects the local "Me" pill to it. Background is a solid `surface` color — no decorative motion.
4. Drag the remote peer pill. The edge follows in real time. Layout deferral leaves the rearranged position stable until you release.
5. Toggle off Bluetooth on the tablet — within ~1 s, the Bluetooth edge fades out and only the LAN edge remains.
6. Pinch-zoom in to 200%. All elements scale; text remains crisp; no jank.
7. Disable internet on the tablet — cloud edge (purple, dashed with decorative circles) disappears.
8. Disconnect the Pixel from the database — its pill animates to the center and fades out.
9. Toggle "Direct Connected Only" off → remote-to-remote edges appear (when ≥ 2 remote peers exist that talk to each other). Toggle on → they disappear.
10. Idle the screen with the viewer open — confirm GPU usage (via Android Studio Profiler) drops to ~0% when no peer is moving, no animation is active, and no peer is selected.

---

## Out of Scope (explicit)

- **Animated background particles** — explicitly dropped in this revision. The iOS `FloatingSquaresLayer` does not have an Android equivalent.
- Multihop graph beyond what the SDK exposes — same as iOS. The "Direct Connected Only" toggle only suppresses **remote-to-remote** edges; full mesh discovery (peers not reachable through the local device) requires SDK changes not in scope.
- Network editor / disconnect / kick peer — debug viewer only.
- RSSI heatmap / signal-strength coloring — data not in `SyncStatusInfo`. Available on the local interface only via `NetworkInterfaceInfo`, but not per-peer.
- Per-peer detail sheet on tap — user confirmed iOS-parity (highlight only, no sheet).
- Web/WASM rendering or shared rendering with iOS — Compose for Web / Skiko is not used by this project.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Excess recomposition during animations causing jank | `Animatable.value` is read **only** inside `drawBehind` lambdas (not in child composable params). Verified by inspecting Composition Counts (Android Studio's Layout Inspector) — `PresenceGraphView` itself shows ≤ 1 composition per state-change event, not per animation frame. |
| `Path` / `Paint` allocations in the hot path | All long-lived objects in `remember { … }`. Optional: a `BenchmarkRule` test in `app/src/androidTest/` measures allocations per frame and fails CI if > 0 in steady state. |
| Drag-while-sync-update fights the user | Layout-deferral logic (matches iOS `isUserInteracting` flag). Updates accumulated during drag are applied with a single tween once `up` fires. |
| New SDK field (`isConnectedToDittoCloud`) not bound in mocks | Add `isCloudConnected = false` default to all `LocalPeerInfo` fakes in `ConnectedPeersScreenTest.kt` and `MainStudioViewModelTest.kt`. Grep ensures coverage. |
| `rememberInfiniteTransition` continuing to recompose forever | The infinite transition is hosted in a child composable that's only added to composition while at least one peer is selected. When selection clears, the composable leaves composition and the transition is cancelled. |

---

## File-by-File Implementation Order (single PR, recommended commit sequence)

1. `domain/model/LocalPeerInfo.kt` — add `isCloudConnected` (default `false`).
2. `data/repository/SystemRepositoryImpl.kt` — populate the new field.
3. `viewmodel/MainStudioViewModel.kt` — add `showDirectConnectedOnly` flow + toggle.
4. `ui/mainstudio/presence/PresenceGraphState.kt` — pure data classes + `toGraphModel()`.
5. `ui/mainstudio/presence/ConnectionStyles.kt` — theme tokens + dash patterns.
6. `ui/mainstudio/presence/PresenceGraphLayout.kt` — BFS ring algorithm.
7. `ui/mainstudio/presence/PresenceGraphRenderer.kt` — pure DrawScope drawing.
8. `ui/mainstudio/presence/PresenceGraphView.kt` — top-level composable, gestures, animations.
9. `ui/mainstudio/PresenceSection.kt` — replace placeholder.
10. `app/src/test/.../presence/*` — unit tests (in lockstep with steps 4–6).
11. `app/src/androidTest/.../presence/PresenceGraphViewTest.kt` — instrumented tests.
12. `plans/android/presence-graph.md` — delete.
13. `plans/android/presence-viewer.md` — add (this plan, post-approval).

---

## References

- **iOS source of truth:**
  - `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceNetworkScene.swift` — 739 lines, the SKScene
  - `SwiftUI/EdgeStudio/Components/PresenceViewer/PeerNode.swift` — pill rendering
  - `SwiftUI/EdgeStudio/Components/PresenceViewer/NetworkLayoutEngine.swift` — BFS ring algorithm
  - `SwiftUI/EdgeStudio/Components/PresenceViewer/ConnectionLine.swift` — Bézier edges + dash patterns
  - `SwiftUI/EdgeStudio/Models/SyncStatus.swift:69-87, 257-260` — color palette
  - `SwiftUI/EdgeStudio/Views/StudioView/Details/PresenceViewerSK.swift` — host view + zoom controls + legend
  - (Not ported: `SwiftUI/EdgeStudio/Components/PresenceViewer/FloatingSquaresLayer.swift`)
- **Android current state:**
  - `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/PresenceSection.kt:138–149` — placeholder
  - `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/SystemRepositoryImpl.kt:88–157` — direct-peer filter (preserved)
  - `android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioSession.kt:133–138` — `peersUiState` flow
  - `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/RemotePeerCard.kt:285–301` — current per-transport color hardcodes (to be replaced by `ConnectionStyles.kt`)
- **Project rules:**
  - `CLAUDE.md` — "Presence Graph Pitfall" (already mitigated at repository layer)
  - `android/CLAUDE.md` — device targeting (`ANDROID_SERIAL=58300DLCR0000L` for `connectedAndroidTest`)
  - `docs/PRESENCE_GRAPH.md` — domain detail
- **Plan being superseded:** `plans/android/presence-graph.md` (delete on merge).
