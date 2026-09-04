package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CenterFocusStrong
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.util.Log
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private const val TAG = "PresenceGraphView"

/**
 * Per-peer animation state. Position, scale, and alpha each have their own [Animatable];
 * the renderer reads `.value` inside `drawBehind`, which invalidates the draw layer only
 * — composition is not retriggered per animation frame.
 *
 * The three `*Job` fields hold the outer coroutines driving each Animatable. They are
 * cancelled before launching a replacement so back-to-back `applyLayoutDiff` invocations
 * (e.g. presence update arriving immediately after drag-release) can't race each other
 * on the same Animatable with stale targets.
 */
internal class PeerAnimState(
    val position: Animatable<Offset, *>,
    val scale: Animatable<Float, *>,
    val alpha: Animatable<Float, *>,
    var target: Offset,
    var exiting: Boolean = false,
    var positionJob: Job? = null,
    var scaleJob: Job? = null,
    var alphaJob: Job? = null,
)

private const val ENTER_ANIM_MS = 400
private const val EXIT_ANIM_MS = 300
private const val LAYOUT_ANIM_MS = 500
private const val HIGHLIGHT_ANIM_MS = 150

private val RemoteGreenLight = Color(0xFF0D8540)
private val RemoteGreenDark = Color(0xFF1FA858)

/**
 * Android port of iOS `PresenceViewerSK`. Renders a BFS-ring presence graph with
 * dashed Bézier edges per transport, a synthetic cloud node when the local peer is
 * cloud-connected, and pan/zoom/drag gestures. The animated background particles
 * present on iOS are intentionally dropped (plan decision).
 */
@Composable
fun PresenceGraphView(
    peersUiState: PeersUiState,
    showDirectConnectedOnly: Boolean,
    onToggleDirectConnectedOnly: () -> Unit,
    // Focus-mode peer id, hoisted to MainStudioViewModel so it survives the
    // Peers ↔ Viewer tab switch (the tab `when` disposes this subtree, which
    // would otherwise kill an active focus session on every hop).
    focusedPeerId: String?,
    onFocusedPeerChange: (String?) -> Unit,
    modifier: Modifier = Modifier,
    controlsVisible: Boolean = true,
    onToggleControlsVisible: () -> Unit = {},
) {
    val density = LocalDensity.current
    val viewConfig = LocalViewConfiguration.current
    val scope = rememberCoroutineScope()

    val graphModel by remember(peersUiState, showDirectConnectedOnly) {
        derivedStateOf {
            when (peersUiState) {
                is PeersUiState.Active -> peersUiState.toGraphModel(showDirectConnectedOnly)
                is PeersUiState.Initializing -> PresenceGraphModel(emptyList(), emptyList(), null)
            }
        }
    }

    val peerStates: SnapshotStateMap<String, PeerAnimState> = remember { mutableStateMapOf() }
    val transform = remember { mutableStateOf(Transform.Identity) }
    val selectedPeerId = remember { mutableStateOf<String?>(null) }
    // Focus mode (Expanded/full-mesh only) — VS Code extension parity: tapping a
    // remote peer with Direct OFF re-lays-out that peer at the centre with its
    // direct neighbours on one orbit; the rest of the mesh stays as dimmed context.
    // The focused id itself is the hoisted parameter; preFocusTransform stays
    // view-local and is re-saved on re-entry (a stale pre-focus camera restored
    // across a tab switch would be worse than snapping back to Identity).
    val preFocusTransform = remember { mutableStateOf<Transform?>(null) }
    val draggingPeerId = remember { mutableStateOf<String?>(null) }
    val deferredLayout = remember { mutableStateOf<LayoutResult?>(null) }
    val sceneSizePx = remember { mutableStateOf(IntOffset.Zero) }
    // Entering Direct mode fits the (smaller) compact layout to the viewport on the
    // next applied layout — zoom-out only, never past the user's chosen zoom-in.
    // (VS Code extension `fitZoomToLayout` parity; not fired on initial composition.)
    val fitDirectLayout = remember { mutableStateOf(false) }
    // The mode that produced the last APPLIED layout. Owned by the layout-apply
    // effect below — a flip means "discard focus + selection, and fit-zoom when
    // entering Direct", honouring the extension's one-layout-per-toggle invariant.
    val appliedDirectMode = remember { mutableStateOf(showDirectConnectedOnly) }

    // ── Label measurement (cached per label string) ─────────────────────────
    val measurer = rememberTextMeasurer()
    val labelStyle = remember {
        TextStyle(
            color = Color.White,
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.Bold,
            fontSize = 9.sp,
            textAlign = TextAlign.Center,
        )
    }
    val pillHeightPx = with(density) { 22.5.dp.toPx() }
    val pillHorizPaddingPx = with(density) { 22.5.dp.toPx() }
    // Pill-width cache keyed by label (the VS Code extension's pill width cache):
    // text measurement is expensive, labels are stable per peer, and renames are
    // rare — so a topology change re-measures nothing.
    val pillMeasureCache = remember { mutableMapOf<String, PillMeasurement>() }
    val pillMeasurements: Map<String, PillMeasurement> = remember(graphModel.nodes) {
        graphModel.nodes.associate { node ->
            node.peerId to pillMeasureCache.getOrPut(node.displayName) {
                measurePeerPill(
                    measurer = measurer,
                    label = node.displayName,
                    style = labelStyle,
                    horizontalPaddingPx = pillHorizPaddingPx,
                    fixedHeightPx = pillHeightPx,
                )
            }
        }
    }

    // Key on the @Immutable graphModel directly. Its data-class equality is cached
    // and stable across recompositions for unchanged states, so we avoid allocating
    // a temporary List<String> per recompose for the remember key. Layout runs AFTER
    // pill measurement: measured label widths (converted to the engine's dp space)
    // feed expanded-mode ring packing so long pills aren't packed too tightly.
    val layoutResult = remember(graphModel, pillMeasurements) {
        val localId = graphModel.localPeerId
            ?: return@remember LayoutResult(emptyMap(), emptyMap(), emptyMap())
        calculateRadialLayout(
            localPeerId = localId,
            peerIds = graphModel.nodes.map { it.peerId },
            edges = graphModel.edges.map { LayoutEdgeInput(it.fromPeerId, it.toPeerId) },
            // Full-mesh (Direct OFF) mode spreads rings wider and packs crowded BFS
            // layers into multiple visual rings (VS Code extension parity). Keyed on
            // the projection actually built, not the toggle: when the mesh hasn't
            // been published yet the model falls back to the direct star, and that
            // fallback must render at the compact 1× scale.
            radiusScale = if (graphModel.isExpandedProjection) EXPANDED_RADIUS_SCALE else 1f,
            peerFootprints = pillMeasurements.mapValues { it.value.width / density.density },
        )
    }

    // Pulse on incident edges when a peer is selected. Hosted via a conditional
    // composable helper: while inactive it's a stable State<Float>=1f, while active
    // it's an InfiniteTransition-driven State. Either way the parent never reads
    // `.value` during composition (only inside drawBehind), so the parent never
    // recomposes per animation frame.
    val pulseAlphaState: State<Float> = rememberPulseAlphaState(
        active = selectedPeerId.value != null,
    )

    // Belt-and-suspenders: if the composable leaves composition mid-drag (tab
    // switch, navigation), clear draggingPeerId so the next visit doesn't start
    // with the LaunchedEffect deferring forever because the flag was never reset.
    DisposableEffect(Unit) {
        onDispose {
            draggingPeerId.value = null
            peerStates.clear()
            deferredLayout.value = null
        }
    }

    val sceneCenterPx by remember(sceneSizePx.value) {
        derivedStateOf { Offset(sceneSizePx.value.x * 0.5f, sceneSizePx.value.y * 0.5f) }
    }

    val pxPerDp = density.density

    // Gesture/click callbacks outlive one composition (pointerInput(Unit) captures
    // the FIRST composition's instances and never restarts), so anything they —
    // or the drag-end layout apply — read must come through these refs. A plain
    // read of a `remember(keys) { derivedStateOf {} }` delegate (e.g. graphModel)
    // would be stuck at the first unequal emission's instance: remember re-creates
    // the delegate when its keys change while the captured lambda keeps the old one.
    val currentLayout by rememberUpdatedState(layoutResult)
    val currentPills by rememberUpdatedState(pillMeasurements)
    val currentPxPerDp by rememberUpdatedState(pxPerDp)
    val currentGraphModel by rememberUpdatedState(graphModel)
    val currentShowDirectOnly by rememberUpdatedState(showDirectConnectedOnly)
    val currentFocusedPeerId by rememberUpdatedState(focusedPeerId)

    // The focused peer plus its direct neighbours — the full-alpha set during
    // focus. Declared before the focus functions + layout-apply effect that use it.
    val focusNeighbourhood: Set<String> by remember(graphModel.edges, focusedPeerId) {
        derivedStateOf {
            val focused = focusedPeerId ?: return@derivedStateOf emptySet()
            PresenceFocusPlanner.neighbourKeys(focused, graphModel.edges).toSet() + focused
        }
    }
    val currentFocusNeighbourhood by rememberUpdatedState(focusNeighbourhood)

    // ── Focus mode (Expanded/full-mesh only) ────────────────────────────────
    // VS Code extension parity: tapping a remote peer with Direct OFF re-lays-out
    // that peer at the centre with its direct neighbours on one orbit; the rest of
    // the mesh stays in place as dimmed context. Exit via the banner ✕, re-tapping
    // the focused peer, or tapping empty canvas. A mode toggle always discards it.
    fun enterFocusMode(peerId: String) {
        if (currentShowDirectOnly) return
        if (peerId == currentGraphModel.localPeerId) return // the local peer is never focusable
        if (peerStates[peerId] == null) return
        selectedPeerId.value = null // focus replaces selection
        // Save the pre-focus camera on entry — also on RE-entry after a tab
        // switch, where the hoisted id is already non-null but the view-local
        // preFocusTransform was disposed with the previous subtree.
        if (currentFocusedPeerId == null || preFocusTransform.value == null) {
            preFocusTransform.value = transform.value
        }
        onFocusedPeerChange(peerId)

        val layout = currentLayout
        val pills = currentPills
        val neighbours = PresenceFocusPlanner.neighbourKeys(peerId, currentGraphModel.edges)
        val focusLayout = calculateRadialLayout(
            localPeerId = peerId,
            peerIds = listOf(peerId) + neighbours,
            edges = currentGraphModel.edges
                .filter { it.fromPeerId == peerId || it.toPeerId == peerId }
                .map { LayoutEdgeInput(it.fromPeerId, it.toPeerId) },
            radiusScale = 1f,
            // The engine's crowding floor + measured footprints make the orbit
            // label-aware (supersedes the extension's expandFocusedRingForLabels).
            peerFootprints = pills.mapValues { it.value.width / currentPxPerDp },
        )

        // Animate the neighbourhood onto the focus orbit; context stays in place.
        for ((id, point) in focusLayout.positions) {
            val state = peerStates[id] ?: continue
            val target = Offset(point.x * currentPxPerDp, point.y * currentPxPerDp)
            state.target = target
            state.positionJob?.cancel()
            state.positionJob = scope.launch {
                state.position.animateTo(target, tween(LAYOUT_ANIM_MS, easing = FastOutSlowInEasing))
            }
        }

        // Focus camera: magnify to at least 1.25×, never past the fit for the
        // complete neighbourhood. The focused peer sits at the layout origin, so
        // centre the viewport on the mesh centre.
        val maxRadiusDp = focusLayout.ringRadii.values.maxOrNull() ?: 0f
        val maxPillPx = pills.values.maxOfOrNull { it.width } ?: 0f
        val sizePx = sceneSizePx.value
        val contentW = (maxRadiusDp * 2f * currentPxPerDp) + maxPillPx + (128f * currentPxPerDp)
        val contentH = (maxRadiusDp * 2f * currentPxPerDp) + maxPillPx + (176f * currentPxPerDp)
        val fit = PresenceFocusPlanner.fitZoom(contentW, contentH, sizePx.x.toFloat(), sizePx.y.toFloat())
        val targetScale = PresenceFocusPlanner.focusScale(fitZoom = fit, currentZoom = transform.value.scale)
        transform.value = Transform(offset = Offset.Zero, scale = targetScale)
    }

    fun exitFocusMode(restorePositions: Boolean = true) {
        if (currentFocusedPeerId == null) return
        onFocusedPeerChange(null)
        // Restore the pre-focus camera; the mesh positions come back through the
        // layout diff. Callers that know a layout pass is running right now (mode
        // toggle, topology change) skip the redundant restore.
        preFocusTransform.value?.let { transform.value = it }
        preFocusTransform.value = null
        if (restorePositions) {
            applyLayoutDiff(scope, peerStates, currentGraphModel, currentLayout, currentPxPerDp)
        }
    }

    // One layout pass = the position diff PLUS the mode/focus bookkeeping that
    // must travel with it (extension invariant: a mode toggle discards focus +
    // selection and arms the Direct fit-zoom). Shared by the layout-apply effect
    // below AND the gesture handler's drag-end path, so a layout deferred by an
    // in-progress peer drag lands with identical invariants when applied at drag
    // end. Reads go through the rememberUpdatedState refs because the drag-end
    // call site is captured once by pointerInput(Unit).
    fun applyLayoutWithBookkeeping(layout: LayoutResult) {
        // A mode toggle always discards focus + selection (extension invariant), so
        // the mesh pass below restores every position (nothing skipped). While
        // focused (no mode change), the neighbourhood keeps its focus orbit — the
        // pass only moves the (dimmed) context nodes, then the orbit refreshes.
        val modeChanged = appliedDirectMode.value != currentShowDirectOnly
        appliedDirectMode.value = currentShowDirectOnly
        val model = currentGraphModel
        val focused = currentFocusedPeerId
        val focusAlive = !modeChanged && focused != null && model.nodes.any { it.peerId == focused }
        val skip = if (focusAlive) currentFocusNeighbourhood else emptySet()

        applyLayoutDiff(scope, peerStates, model, layout, currentPxPerDp, skipRepositioning = skip)
        deferredLayout.value = null

        when {
            modeChanged -> {
                selectedPeerId.value = null
                if (currentShowDirectOnly) fitDirectLayout.value = true
                if (focused != null) exitFocusMode(restorePositions = false)
            }
            focused != null && !focusAlive -> exitFocusMode(restorePositions = false)
            // Refresh the orbit. Skip while the viewport is unmeasured (first
            // composition of a tab-switch re-entry): the focus camera would be
            // computed against a zero size and the re-entry effect below re-fires
            // once onSizeChanged reports the real viewport.
            focused != null && sceneSizePx.value != IntOffset.Zero -> enterFocusMode(focused)
            else -> Unit
        }

        if (fitDirectLayout.value) {
            fitDirectLayout.value = false
            // Zoom OUT (smaller scale shows more content) until the compact layout
            // fits the viewport — never zoom in past the user's chosen level.
            val maxRadiusDp = layout.ringRadii.values.maxOrNull() ?: 0f
            val sizePx = sceneSizePx.value
            if (maxRadiusDp > 0f && sizePx != IntOffset.Zero) {
                val maxPillPx = currentPills.values.maxOfOrNull { it.width } ?: 0f
                val layoutDiameterPx = (maxRadiusDp * 2f * currentPxPerDp) + maxPillPx + (40f * currentPxPerDp)
                if (layoutDiameterPx > 0f) {
                    val fitScale = minOf(
                        sizePx.x.toFloat() / layoutDiameterPx,
                        sizePx.y.toFloat() / layoutDiameterPx,
                    )
                    val current = transform.value.scale
                    val target = fitScale.coerceIn(Transform.MIN_SCALE, Transform.MAX_SCALE)
                    if (target < current) {
                        transform.value = transform.value.copy(scale = target)
                    }
                }
            }
        }
    }

    // showDirectConnectedOnly is a key even though the body reads it through a
    // ref: when both projections are structurally equal (all-direct mesh with
    // matching order), graphModel/layoutResult don't change on a toggle — without
    // this key the effect wouldn't fire and the mode-toggle bookkeeping inside
    // applyLayoutWithBookkeeping (discard selection/focus, arm fitDirectLayout)
    // would never run.
    LaunchedEffect(graphModel.nodes, layoutResult.positions, pxPerDp, showDirectConnectedOnly) {
        if (draggingPeerId.value != null) {
            if (BuildConfig.DEBUG) {
                Log.d(
                    TAG,
                    "Layout update deferred (peer drag in progress); nodes=${graphModel.nodes.size} " +
                        "edges=${graphModel.edges.size}",
                )
            }
            deferredLayout.value = layoutResult
            return@LaunchedEffect
        }
        if (BuildConfig.DEBUG) {
            Log.d(
                TAG,
                "Applying layout: nodes=${graphModel.nodes.size} edges=${graphModel.edges.size}",
            )
        }
        applyLayoutWithBookkeeping(layoutResult)
    }

    // Focus re-entry after a Peers ↔ Viewer tab switch: the hoisted id survives
    // the dispose of this subtree; the in-view orbit + pre-focus camera do not.
    // Re-enter once the viewport is measured and the first layout pass has
    // placed the peer. If the peer left the mesh meanwhile (or the mode is
    // Direct, where focus doesn't exist), clear the hoisted id instead.
    LaunchedEffect(focusedPeerId, showDirectConnectedOnly, sceneSizePx.value) {
        val focused = focusedPeerId ?: return@LaunchedEffect
        if (showDirectConnectedOnly || graphModel.nodes.none { it.peerId == focused }) {
            onFocusedPeerChange(null)
            // Mirror exitFocusMode's camera restore. The layout-apply path skips
            // exitFocusMode once the hoisted id is cleared (e.g. a Direct toggle
            // mid-drag, where the layout lands only at drag end) — without this the
            // camera stays stuck at the focus zoom/centre.
            preFocusTransform.value?.let { transform.value = it }
            preFocusTransform.value = null
            return@LaunchedEffect
        }
        if (preFocusTransform.value != null) return@LaunchedEffect // already entered here
        if (sceneSizePx.value == IntOffset.Zero) return@LaunchedEffect // wait for the viewport
        if (peerStates[focused] == null) return@LaunchedEffect // layout hasn't placed it yet
        enterFocusMode(focused)
    }

    val pathPool = remember { mutableMapOf<String, Path>() }
    // Reused PathMeasure for cloud-edge decorative circles. PathMeasure is mutable
    // (setPath() rebinds), so a single instance is safe — only one cloud edge
    // measures at a time inside drawBehind's sequential loop.
    val cloudPathMeasure = remember { androidx.compose.ui.graphics.PathMeasure() }
    val dashEffects = rememberDashEffects()
    val cloudCircleSpacingPx = with(density) { 40.dp.toPx() }
    val baseStrokePx = with(density) { 2.dp.toPx() }
    val highlightStrokePx = with(density) { 3.dp.toPx() }
    val parallelBaseOffsetPx = with(density) { 10.dp.toPx() }

    // Parallel-edge offsets: when N edges connect the same pair (e.g. Pixel 6 over BT +
    // P2P WiFi), distribute them along the perpendicular so the lines don't overlap.
    // Port of iOS PresenceNetworkScene.updateConnections offset computation.
    // Selection-driven sets: which edges are incident to the selected peer, and which
    // peer nodes are at either endpoint of those edges. Used in drawBehind to dim
    // everything that isn't part of the selected peer's neighbourhood — gives the user
    // a clear "show me how X is connected" answer when they tap, especially in OFF
    // mode where the full mesh is on screen.
    val incidentEdgeIds: Set<String> by remember(graphModel.edges, selectedPeerId.value) {
        derivedStateOf {
            val sel = selectedPeerId.value ?: return@derivedStateOf emptySet()
            graphModel.edges.asSequence()
                .filter { it.fromPeerId == sel || it.toPeerId == sel }
                .map { it.edgeId }
                .toSet()
        }
    }
    val highlightedPeerIds: Set<String> by remember(graphModel.edges, selectedPeerId.value) {
        derivedStateOf {
            val sel = selectedPeerId.value ?: return@derivedStateOf emptySet()
            graphModel.edges.asSequence()
                .filter { it.fromPeerId == sel || it.toPeerId == sel }
                .flatMap { sequenceOf(it.fromPeerId, it.toPeerId) }
                .toSet() + sel
        }
    }



    val parallelOffsetByEdgeId: Map<String, Float> = remember(graphModel.edges, parallelBaseOffsetPx) {
        buildMap {
            graphModel.edges
                .groupBy { it.pairKey }
                .forEach { (_, edges) ->
                    val sorted = edges.sortedBy { it.edgeId }
                    val count = sorted.size
                    sorted.forEachIndexed { index, edge ->
                        val offset = when {
                            count <= 1 -> 0f
                            count == 2 -> if (index == 0) parallelBaseOffsetPx else -parallelBaseOffsetPx
                            else -> parallelBaseOffsetPx -
                                (parallelBaseOffsetPx * 2f / (count - 1) * index)
                        }
                        put(edge.edgeId, offset)
                    }
                }
        }
    }

    val isDarkScheme = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val remoteGreen = if (isDarkScheme) RemoteGreenDark else RemoteGreenLight
    val primaryColor = MaterialTheme.colorScheme.primary
    val onPrimaryColor = MaterialTheme.colorScheme.onPrimary

    // Wrap the three per-node/edge color tables in `remember` so they aren't rebuilt
    // (allocating a fresh LinkedHashMap each time) on every recomposition. Keys
    // include the inputs that can change the mapping: edges/nodes from the model,
    // dark-mode toggle, and the primary theme colors. `resolveColor` is the
    // non-Composable underlying function from ConnectionStyles — safe to call
    // inside `remember { ... }`.
    val cloudColor = remember(isDarkScheme) {
        resolveColor(ConnectionType.WebSocket, isCloud = true, dark = isDarkScheme)
    }
    val edgeColorByEdgeId: Map<String, Color> = remember(graphModel.edges, isDarkScheme) {
        graphModel.edges.associate { edge ->
            edge.edgeId to resolveColor(edge.type, edge.isCloud, isDarkScheme)
        }
    }
    val nodeFillByPeerId: Map<String, Color> = remember(graphModel.nodes, primaryColor, remoteGreen, cloudColor) {
        graphModel.nodes.associate { node ->
            node.peerId to when {
                node.isCloud -> cloudColor
                node.isLocal -> primaryColor
                else -> remoteGreen
            }
        }
    }
    // Local pill sits on `primary` (yellow in this theme) — onPrimary is the readable
    // text color the theme provides. Remote (green) and cloud (purple) are dark fills,
    // so white text stays readable on both.
    val nodeTextColorByPeerId: Map<String, Color> = remember(graphModel.nodes, onPrimaryColor) {
        graphModel.nodes.associate { node ->
            node.peerId to if (node.isLocal) onPrimaryColor else Color.White
        }
    }
    // Use the same background tone every other screen inherits from the parent
    // Material 3 Scaffold (colorScheme.background — PapyrusWhite light / JetBlack
    // dark). `surface` would render TrafficWhite/TrafficBlack, which visually
    // matches the top toolbar instead of the page body and broke parity with the
    // Peers tab.
    val surfaceColor = MaterialTheme.colorScheme.background

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(surfaceColor)
            // Clip drawn edges/pills (and the semantics-layer pill overlays) to this
            // Box's bounds. Without this the user can drag the camera and have peer
            // pills bleed up into the tab toolbar above this view.
            .clipToBounds()
            .onSizeChanged { size -> sceneSizePx.value = IntOffset(size.width, size.height) }
            // Key on Unit so mesh churn (peers joining/leaving while the user is
            // mid-gesture) does NOT cancel the gesture coroutine. The trade-off:
            // this lambda keeps the FIRST composition's captured instances, so
            // everything it reads must come through the rememberUpdatedState refs
            // (currentGraphModel, currentPills, currentPxPerDp, ...) — a plain
            // delegate read would go stale on the first unequal emission (peers
            // joining after first composition couldn't even be hit-tested).
            .pointerInput(Unit) {
                awaitEachGesture {
                    val firstDown = awaitFirstDown(requireUnconsumed = false)
                    val downPosition = firstDown.position
                    val hitPeerId = hitTestPeer(
                        point = downPosition,
                        nodes = currentGraphModel.nodes,
                        peerStates = peerStates,
                        pillMeasurements = currentPills,
                        transform = transform.value,
                        sceneCenterPx = sceneCenterPx,
                    )

                    var dragStarted = false
                    var isPeerDrag = false
                    var isPanning = false
                    // Tracks the prior frame's active-pointer count. When it
                    // transitions 2→1 (a pinch becomes a single touch) the remaining
                    // pointer's `previousPosition` is stale (it was moving during the
                    // pinch), so we skip that frame's delta to avoid an unwanted
                    // single-frame jump in pan or peer-drag.
                    var lastPressedCount = 0

                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Main)
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.isEmpty()) {
                            // Tap on EMPTY canvas → clear selection. Tap on a peer is
                            // handled exclusively by the semantics-overlay clickable
                            // below; if we also acted here on hitPeerId != null we'd
                            // race that handler (child sets P, parent immediately
                            // toggles it back off because selectedPeerId == hitPeerId).
                            //
                            // Defensive: also skip the clear when any descendant has
                            // consumed the tap. The child clickable consumes on tap
                            // recognition, so seeing a consumed event here means the
                            // child just toggled selection — never overwrite that.
                            val anyConsumed = event.changes.any { it.isConsumed }
                            if (!dragStarted && hitPeerId == null && !anyConsumed) {
                                selectedPeerId.value = null
                                // Empty-canvas tap also exits focus mode (extension parity).
                                exitFocusMode()
                            }
                            if (isPeerDrag) {
                                if (BuildConfig.DEBUG) Log.d(TAG, "Drag end peer=${draggingPeerId.value}")
                                draggingPeerId.value = null
                                val deferred = deferredLayout.value
                                if (deferred != null) {
                                    // A layout that landed mid-drag is applied here
                                    // with the SAME mode/focus bookkeeping as the
                                    // layout-apply effect — including discarding a
                                    // focus session a mode toggle already killed.
                                    applyLayoutWithBookkeeping(deferred)
                                }
                            }
                            lastPressedCount = 0
                            break
                        }
                        if (pressed.size >= 2) {
                            val zoom = event.calculateZoom()
                            if (zoom != 1f) {
                                transform.value = transform.value.copy(
                                    scale = (transform.value.scale * zoom)
                                        .coerceIn(Transform.MIN_SCALE, Transform.MAX_SCALE),
                                )
                                event.changes.forEach { it.consume() }
                            }
                            lastPressedCount = pressed.size
                            continue
                        }
                        // Single-pointer drag or pending tap
                        val justTransitionedFromPinch = lastPressedCount >= 2
                        lastPressedCount = pressed.size
                        if (justTransitionedFromPinch) {
                            // Discard this frame's stale delta — the next frame will
                            // produce a clean previousPosition.
                            continue
                        }
                        val change = pressed[0]
                        val delta = change.position - change.previousPosition
                        if (!dragStarted) {
                            val totalDelta = change.position - downPosition
                            if (totalDelta.getDistance() > viewConfig.touchSlop) {
                                dragStarted = true
                                if (hitPeerId != null) {
                                    isPeerDrag = true
                                    draggingPeerId.value = hitPeerId
                                    if (BuildConfig.DEBUG) Log.d(TAG, "Drag start peer=$hitPeerId")
                                } else {
                                    isPanning = true
                                }
                            }
                        }
                        if (dragStarted) {
                            change.consume()
                            if (isPeerDrag) {
                                val id = draggingPeerId.value
                                val state = if (id != null) peerStates[id] else null
                                if (state != null) {
                                    val scaled = Offset(
                                        delta.x / transform.value.scale,
                                        delta.y / transform.value.scale,
                                    )
                                    // Drag is in canvas y-down; math coords are y-up — flip.
                                    val mathDelta = Offset(scaled.x, -scaled.y)
                                    scope.launch {
                                        state.position.snapTo(state.position.value + mathDelta)
                                    }
                                }
                            } else if (isPanning) {
                                transform.value = transform.value.copy(
                                    offset = transform.value.offset + delta,
                                )
                            }
                        }
                    }
                }
            }
            .drawBehind {
                // Skip the entire draw pass before onSizeChanged has reported a real
                // viewport — otherwise the first frame draws every pill at canvas
                // origin (0,0), producing a brief visible flash before re-layout.
                if (sceneSizePx.value.x == 0 || sceneSizePx.value.y == 0) return@drawBehind

                for (edge in graphModel.edges) {
                    val fromState = peerStates[edge.fromPeerId] ?: continue
                    val toState = peerStates[edge.toPeerId] ?: continue
                    val fromCanvas = mathToCanvas(
                        pos = fromState.position.value,
                        sceneCenter = sceneCenterPx,
                        transform = transform.value,
                    )
                    val toCanvas = mathToCanvas(
                        pos = toState.position.value,
                        sceneCenter = sceneCenterPx,
                        transform = transform.value,
                    )
                    val selected = selectedPeerId.value
                    val focused = focusedPeerId
                    val isIncident = selected != null && edge.edgeId in incidentEdgeIds
                    val color = edgeColorByEdgeId[edge.edgeId] ?: Color.Gray
                    val dashKey = DashKey(edge.type, edge.isCloud)
                    val dashEffect = dashEffects[dashKey] ?: continue
                    val strokePx = if (isIncident) highlightStrokePx else baseStrokePx
                    // States per edge (focus wins over selection):
                    //   focused + touches focus → full alpha (the orbit's spokes)
                    //   focused + other        → context backdrop (0.04)
                    //   selected + incident    → pulse (0.8..1.0) — reads State<Float>
                    //                            inside drawBehind so only the draw
                    //                            layer invalidates, never composition
                    //   selected + non-incident → dim to 0.2
                    //   otherwise              → full alpha
                    val edgeAlpha = when {
                        focused != null ->
                            if (edge.fromPeerId == focused || edge.toPeerId == focused) {
                                1f
                            } else {
                                PresenceFocusPlanner.CONTEXT_LINE_ALPHA
                            }
                        selected == null -> 1f
                        isIncident -> pulseAlphaState.value
                        else -> 0.2f
                    }
                    val path = pathPool.getOrPut(edge.edgeId) { Path() }
                    drawPresenceEdge(
                        fromPos = fromCanvas,
                        toPos = toCanvas,
                        sceneCenter = sceneCenterPx,
                        color = color,
                        dashEffect = dashEffect,
                        strokeWidthPx = strokePx,
                        alpha = (fromState.alpha.value * toState.alpha.value) * edgeAlpha,
                        isCloud = edge.isCloud,
                        arcOutward = edge.arcOutward,
                        parallelOffsetPx = parallelOffsetByEdgeId[edge.edgeId] ?: 0f,
                        cloudCircleSpacingPx = cloudCircleSpacingPx,
                        path = path,
                        pathMeasure = cloudPathMeasure,
                    )
                }
                // Evict pooled Path objects for edges that are no longer in the model.
                // Without this, a long-running session with churning peers would grow
                // the pool unbounded (one Path per ever-seen edgeId).
                if (pathPool.size > graphModel.edges.size) {
                    val activeEdgeIds = graphModel.edges.mapTo(HashSet(graphModel.edges.size)) { it.edgeId }
                    pathPool.keys.retainAll(activeEdgeIds)
                }
                for (node in graphModel.nodes) {
                    val state = peerStates[node.peerId] ?: continue
                    val measurement = pillMeasurements[node.peerId] ?: continue
                    val canvasPos = mathToCanvas(
                        pos = state.position.value,
                        sceneCenter = sceneCenterPx,
                        transform = transform.value,
                    )
                    val fill = nodeFillByPeerId[node.peerId] ?: Color.Gray
                    val textColor = nodeTextColorByPeerId[node.peerId] ?: Color.White
                    val selected = selectedPeerId.value
                    val focused = focusedPeerId
                    val isSelectedPeer = focused == null && selected != null && node.peerId == selected
                    // Neighbourhood membership: focus mode uses the focus orbit;
                    // selection mode uses the selected peer's incident edges.
                    val isInNeighbourhood = when {
                        focused != null -> node.peerId in focusNeighbourhood
                        selected == null -> true
                        else -> node.peerId in highlightedPeerIds
                    }
                    // Selection visual: selected peer scales to 1.1×, peers in its
                    // neighbourhood stay full alpha, everyone else dims (0.35
                    // selection / 0.08 focus context) so the structure pops.
                    val dimAlpha = if (focused != null) PresenceFocusPlanner.CONTEXT_PEER_ALPHA else 0.35f
                    val pillScale = state.scale.value * if (isSelectedPeer) 1.1f else 1f
                    val pillAlpha = state.alpha.value * if (isInNeighbourhood) 1f else dimAlpha
                    drawPresencePeerPill(
                        center = canvasPos,
                        widthPx = measurement.width * transform.value.scale,
                        heightPx = measurement.height * transform.value.scale,
                        fillColor = fill,
                        strokeColor = fill,
                        textColor = textColor,
                        textLayout = measurement.text,
                        scale = pillScale,
                        alpha = pillAlpha,
                    )
                }
            },
    ) {
        // Parallel semantics layer (a11y + keyboard). Tap routing mirrors the
        // extension's nodeAt/selectPeer pair:
        //  - Direct mode: a tap toggles selection (dim/highlight) for any peer,
        //    including local "Me" — a documented intentional deviation from the
        //    extension, which rejects the local key everywhere.
        //  - Expanded, unfocused: tapping a remote peer enters focus on it;
        //    tapping Me is an invalid selection (no-op — Me is never focusable).
        //  - Expanded, focused: re-tapping the focused peer exits focus; tapping
        //    an ORBIT peer refocuses on it; tapping a dimmed CONTEXT peer (or Me
        //    while he's off the orbit) is a canvas click — the extension's
        //    nodeAt skips non-orbit nodes, so the tap exits focus; Me ON the
        //    orbit is an invalid selection (no-op, focus stays).
        //
        // Me is intentionally excluded from `hitTestPeer` in the parent gesture
        // handler instead: that keeps drag-from-Me out of the peer-drag path
        // (which would otherwise shift the BFS layout anchor away from origin) and
        // routes it to camera-pan, while taps still flow through the child
        // clickable here unimpeded.
        for (node in graphModel.nodes) {
            val state = peerStates[node.peerId] ?: continue
            val measurement = pillMeasurements[node.peerId] ?: continue
            val widthDp = with(density) { (measurement.width * transform.value.scale).toDp() }
            val heightDp = with(density) { (measurement.height * transform.value.scale).toDp() }
            Box(
                modifier = Modifier
                    .offset {
                        val canvas = mathToCanvas(
                            pos = state.position.value,
                            sceneCenter = sceneCenterPx,
                            transform = transform.value,
                        )
                        IntOffset(
                            (canvas.x - measurement.width * transform.value.scale * 0.5f).roundToInt(),
                            (canvas.y - measurement.height * transform.value.scale * 0.5f).roundToInt(),
                        )
                    }
                    .size(widthDp, heightDp)
                    .semantics(mergeDescendants = true) {
                        contentDescription = node.displayName
                        role = Role.Button
                    }
                    .clickable {
                        val focused = focusedPeerId
                        when {
                            // Direct mode: tap only dims (selection) — extension parity,
                            // except that local "Me" stays selectable here
                            // (documented intentional deviation).
                            showDirectConnectedOnly -> {
                                val newValue = if (selectedPeerId.value == node.peerId) null else node.peerId
                                if (BuildConfig.DEBUG) {
                                    Log.d(TAG, "Selection ${selectedPeerId.value} → $newValue (tap on ${node.peerId})")
                                }
                                selectedPeerId.value = newValue
                            }
                            focused != null -> when {
                                // Re-tapping the focused peer exits focus.
                                node.peerId == focused -> exitFocusMode()
                                // Me ON the orbit: invalid selection (the
                                // extension's selectPeer rejects the local key)
                                // — no-op, focus stays.
                                node.peerId == graphModel.localPeerId &&
                                    node.peerId in focusNeighbourhood -> Unit
                                // Orbit peer → refocus on it.
                                node.peerId in focusNeighbourhood -> enterFocusMode(node.peerId)
                                // Dimmed CONTEXT peer (and Me off the orbit): the
                                // extension's nodeAt skips non-orbit nodes, so the
                                // tap lands as a canvas click — exit focus.
                                else -> exitFocusMode()
                            }
                            // Expanded, unfocused: Me is never focusable (invalid
                            // selection → no-op); any other tap enters focus.
                            node.peerId == graphModel.localPeerId -> Unit
                            else -> enterFocusMode(node.peerId)
                        }
                    },
            )
        }

        // Focus banner (top-center) — mirrors the VS Code extension's
        // "Focused on <label>" pill with an exit button.
        focusedPeerId?.let { focusedId ->
            val focusedName = graphModel.nodes.firstOrNull { it.peerId == focusedId }?.displayName ?: focusedId
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = RoundedCornerShape(percent = 50),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 12.dp)
                    .semantics { contentDescription = "Focused on $focusedName" },
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(start = 14.dp, end = 4.dp, top = 2.dp, bottom = 2.dp),
                ) {
                    Text(
                        text = "Focused on ",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = focusedName,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    IconButton(
                        onClick = { exitFocusMode() },
                        modifier = Modifier
                            .size(28.dp)
                            .semantics { contentDescription = "Exit focus" },
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Close,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Connection legend (bottom-left) — port of iOS PresenceViewerSK.connectionLegend.
        // Hidden by the controls-visibility (eye) toggle.
        if (controlsVisible) {
            ConnectionLegendCard(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(12.dp),
            )
        }

        // Bottom-right control stack: reset / Direct toggle / zoom controls.
        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(12.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Reset view — restores 100% zoom, recenters the camera, and animates any
            // dragged peers back to their layout-assigned positions. Without this, a
            // user who pans far off-canvas has no way to find their graph again.
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
                shape = RoundedCornerShape(12.dp),
            ) {
                FilledIconButton(
                    onClick = {
                        transform.value = Transform.Identity
                        selectedPeerId.value = null
                        for ((_, state) in peerStates) {
                            scope.launch {
                                state.position.animateTo(
                                    state.target,
                                    tween(LAYOUT_ANIM_MS, easing = FastOutSlowInEasing),
                                )
                            }
                            if (state.scale.value != 1f) {
                                scope.launch {
                                    state.scale.animateTo(
                                        1f,
                                        tween(HIGHLIGHT_ANIM_MS, easing = FastOutSlowInEasing),
                                    )
                                }
                            }
                        }
                    },
                    modifier = Modifier
                        .padding(horizontal = 4.dp, vertical = 4.dp)
                        .semantics { contentDescription = "Reset view" },
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.CenterFocusStrong,
                        contentDescription = null,
                    )
                }
            }
            // Direct toggle — hidden by the controls-visibility (eye) toggle.
            if (controlsVisible) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "Direct",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Switch(
                            checked = showDirectConnectedOnly,
                            onCheckedChange = { onToggleDirectConnectedOnly() },
                            modifier = Modifier
                                .padding(start = 8.dp)
                                .semantics { contentDescription = "Direct Connected Only" },
                        )
                    }
                }
            }
            // Zoom cluster — hidden by the controls-visibility (eye) toggle.
            if (controlsVisible) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                    FilledIconButton(
                        onClick = {
                            transform.value = transform.value.copy(
                                scale = (transform.value.scale - 0.1f)
                                    .coerceAtLeast(Transform.MIN_SCALE),
                            )
                        },
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    ) {
                        Text("−", style = MaterialTheme.typography.titleMedium)
                    }
                    Text(
                        text = "${(transform.value.scale * 100).roundToInt()}%",
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.semantics { contentDescription = "Zoom level" },
                    )
                    FilledIconButton(
                        onClick = {
                            transform.value = transform.value.copy(
                                scale = (transform.value.scale + 0.1f)
                                    .coerceAtMost(Transform.MAX_SCALE),
                            )
                        },
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    ) {
                        Text("+", style = MaterialTheme.typography.titleMedium)
                    }
                    }
                }
            }
            // Controls-visibility (eye) toggle — always visible (extension parity):
            // hides/shows the legend + Direct toggle + zoom cluster.
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
                shape = RoundedCornerShape(12.dp),
            ) {
                FilledIconButton(
                    onClick = { onToggleControlsVisible() },
                    modifier = Modifier
                        .padding(horizontal = 4.dp, vertical = 4.dp)
                        .semantics { contentDescription = "Toggle controls visibility" },
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                ) {
                    Icon(
                        imageVector = if (controlsVisible) Icons.Outlined.Visibility else Icons.Outlined.VisibilityOff,
                        contentDescription = null,
                    )
                }
            }
        }

        // Pulse is sourced from rememberPulseAlphaState (declared above) — its
        // State<Float> is read only inside drawBehind, so the parent never
        // recomposes per frame.
    }
}

/**
 * Returns a stable `State<Float>` consumed inside `drawBehind` only. When [active]
 * is true an `InfiniteTransition` ticks the value between 0.8 and 1.0 at ~3 Hz;
 * when false the value is a constant `1f`.
 *
 * Why this shape: previously a child composable hosted the transition and wrote
 * back into a parent `mutableFloatStateOf` via `LaunchedEffect(v)`. Reading the
 * animated value with property-delegation (`val v by ...`) inside that child
 * caused it to recompose every animation frame (~60 Hz) and restart the
 * LaunchedEffect with a fresh key each tick — defeating the plan's "no
 * recomposition during animations" perf budget. This helper exposes a `State<Float>`
 * the parent reads from `drawBehind` only; composition is never re-entered.
 */
@Composable
private fun rememberPulseAlphaState(active: Boolean): State<Float> {
    return if (active) {
        val transition = rememberInfiniteTransition(label = "edgePulse")
        transition.animateFloat(
            initialValue = 0.8f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 333, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "edgePulseValue",
        )
    } else {
        // When deselected, the parent reads a constant 1f — no animation runs,
        // no per-frame invalidation. `remember` keeps the State identity stable
        // across re-toggles so drawBehind isn't churning closure captures.
        remember { mutableFloatStateOf(1f) }
    }
}

/** Convert a y-up math-coord position to canvas pixels (post transform, post y-flip). */
private fun mathToCanvas(pos: Offset, sceneCenter: Offset, transform: Transform): Offset {
    val scaled = Offset(pos.x * transform.scale, -pos.y * transform.scale)
    return Offset(
        sceneCenter.x + scaled.x + transform.offset.x,
        sceneCenter.y + scaled.y + transform.offset.y,
    )
}

private fun hitTestPeer(
    point: Offset,
    nodes: List<PeerNode>,
    peerStates: Map<String, PeerAnimState>,
    pillMeasurements: Map<String, PillMeasurement>,
    transform: Transform,
    sceneCenterPx: Offset,
): String? {
    for (node in nodes.asReversed()) {
        // Local is excluded from PARENT-gesture hit-testing only — taps on Me
        // still reach the semantics-overlay clickable, whose Expanded/Direct
        // routing decides what a Me tap means (Direct: selection toggle;
        // Expanded: invalid selection — no-op, or canvas-click focus exit while
        // focused and off the orbit). Excluding here means a drag starting on Me
        // falls through to the panning branch (camera pan) instead of
        // `isPeerDrag = true`, which would otherwise yank Me away from the scene
        // origin and visually break the BFS layout anchor.
        if (node.isLocal) continue
        val state = peerStates[node.peerId] ?: continue
        val measurement = pillMeasurements[node.peerId] ?: continue
        val canvas = mathToCanvas(
            pos = state.position.value,
            sceneCenter = sceneCenterPx,
            transform = transform,
        )
        // IMPORTANT: do NOT multiply by `state.scale.value` — the semantics-overlay
        // Box uses `.size(widthDp, heightDp)` computed without the animation scale,
        // so the overlay's clickable bounds are full-size during the enter
        // animation. If we hit-tested with a smaller box here, a tap on the
        // already-animating-in peer would: (a) miss the parent hit-test, leaving
        // `hitPeerId = null`, then (b) get caught by the child's clickable (sets
        // selection), then (c) the parent's tap-up handler would clear the
        // selection because hitPeerId was null — the symptom users reported as
        // "tap doesn't highlight on first launch but works after a tab switch".
        val halfW = measurement.width * transform.scale * 0.5f
        val halfH = measurement.height * transform.scale * 0.5f
        if (
            point.x in (canvas.x - halfW)..(canvas.x + halfW) &&
            point.y in (canvas.y - halfH)..(canvas.y + halfH)
        ) {
            return node.peerId
        }
    }
    return null
}

/**
 * Diff the desired model+layout against the per-peer animation map: add new peers with
 * an enter animation, animate existing peers to their new layout positions, and start
 * exit animations for peers no longer in the model. Exit-complete peers are removed.
 *
 * [skipRepositioning]: peers whose positions belong to the focus orbit (focus mode)
 * — the mesh pass leaves them in place while a focus refresh re-animates them.
 */
private fun applyLayoutDiff(
    scope: CoroutineScope,
    peerStates: SnapshotStateMap<String, PeerAnimState>,
    model: PresenceGraphModel,
    layout: LayoutResult,
    pxPerDp: Float,
    skipRepositioning: Set<String> = emptySet(),
) {
    val desiredIds = model.nodes.map { it.peerId }.toSet()

    for (node in model.nodes) {
        // Layout positions are in dp (matches iOS NetworkLayoutEngine constants).
        // Canvas draws in pixels, so convert once here at the boundary.
        val target = layout.positions[node.peerId]
            ?.let { Offset(it.x * pxPerDp, it.y * pxPerDp) } ?: Offset.Zero
        val existing = peerStates[node.peerId]
        if (existing == null) {
            val state = PeerAnimState(
                position = Animatable(Offset.Zero, Offset.VectorConverter),
                scale = Animatable(0.5f),
                alpha = Animatable(0f),
                target = target,
            )
            peerStates[node.peerId] = state
            state.positionJob = scope.launch {
                state.position.animateTo(target, tween(LAYOUT_ANIM_MS, easing = FastOutSlowInEasing))
            }
            state.scaleJob = scope.launch {
                state.scale.animateTo(1f, tween(ENTER_ANIM_MS, easing = FastOutSlowInEasing))
            }
            state.alphaJob = scope.launch {
                state.alpha.animateTo(1f, tween(ENTER_ANIM_MS, easing = FastOutSlowInEasing))
            }
        } else {
            existing.exiting = false
            if (node.peerId !in skipRepositioning) {
                existing.target = target
                // Cancel any in-flight animation coroutines on each Animatable before
                // launching a replacement. Animatable.animateTo internally cancels its
                // own current animation, but the outer coroutine's onComplete callbacks
                // (e.g. peerStates.remove in the exit branch below) would otherwise run
                // to completion against stale state when the user races a presence
                // update against a drag-release.
                existing.positionJob?.cancel()
                existing.positionJob = scope.launch {
                    existing.position.animateTo(target, tween(LAYOUT_ANIM_MS, easing = FastOutSlowInEasing))
                }
            }
            if (existing.scale.value != 1f) {
                existing.scaleJob?.cancel()
                existing.scaleJob = scope.launch {
                    existing.scale.animateTo(1f, tween(HIGHLIGHT_ANIM_MS, easing = FastOutSlowInEasing))
                }
            }
            if (existing.alpha.value != 1f) {
                existing.alphaJob?.cancel()
                existing.alphaJob = scope.launch {
                    existing.alpha.animateTo(1f, tween(ENTER_ANIM_MS, easing = FastOutSlowInEasing))
                }
            }
        }
    }

    val toRemove = peerStates.keys.filter { it !in desiredIds }
    for (id in toRemove) {
        val state = peerStates[id] ?: continue
        if (state.exiting) continue
        state.exiting = true
        state.scaleJob?.cancel()
        state.scaleJob = scope.launch {
            state.scale.animateTo(0.5f, tween(EXIT_ANIM_MS, easing = FastOutSlowInEasing))
        }
        state.alphaJob?.cancel()
        state.alphaJob = scope.launch {
            state.alpha.animateTo(0f, tween(EXIT_ANIM_MS, easing = FastOutSlowInEasing))
        }
        state.positionJob?.cancel()
        state.positionJob = scope.launch {
            state.position.animateTo(Offset.Zero, tween(EXIT_ANIM_MS, easing = FastOutSlowInEasing))
            // Only remove if our coroutine ran to completion. If a fresh
            // applyLayoutDiff readded the peer mid-exit, this Job was cancelled
            // before this line and `state.exiting` was already reset back to false.
            if (peerStates[id]?.exiting == true) {
                peerStates.remove(id)
            }
        }
    }
}

/** Perceived luminance proxy — used to pick light/dark variants of non-Material colors. */
private fun Color.luminance(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue

/**
 * Bottom-left legend card matching iOS `PresenceViewerSK.connectionLegend`. One row per
 * transport: a small color/dash swatch then the transport name. Without this users
 * can't tell what the dash patterns and colors mean.
 */
@Composable
private fun ConnectionLegendCard(modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(
                text = "Connection Types",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            LegendRow(type = ConnectionType.Bluetooth, isCloud = false, label = "Bluetooth")
            LegendRow(type = ConnectionType.LAN, isCloud = false, label = "LAN")
            LegendRow(type = ConnectionType.P2PWiFi, isCloud = false, label = "P2P WiFi")
            LegendRow(type = ConnectionType.WebSocket, isCloud = false, label = "WebSocket")
            LegendRow(type = ConnectionType.Multicast, isCloud = false, label = "Multicast")
            LegendRow(type = ConnectionType.WebSocket, isCloud = true, label = "Cloud")
        }
    }
}

@Composable
private fun LegendRow(
    type: ConnectionType,
    isCloud: Boolean,
    label: String,
) {
    val color = connectionColor(type, isCloud)
    val intervals = dashIntervalsDp(type, isCloud)
    val density = LocalDensity.current
    val pxIntervals = remember(density, type, isCloud) {
        FloatArray(intervals.size) { i -> with(density) { intervals[i].dp.toPx() } }
    }
    val dash = remember(pxIntervals) { PathEffect.dashPathEffect(pxIntervals, 0f) }
    Row(
        modifier = Modifier.padding(top = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        androidx.compose.foundation.Canvas(
            modifier = Modifier.size(width = 36.dp, height = 10.dp),
        ) {
            val y = size.height / 2f
            drawLine(
                color = color,
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = 2.dp.toPx(),
                cap = StrokeCap.Round,
                pathEffect = dash,
            )
            if (isCloud) {
                // Sample cloud's decorative circle on the swatch so users learn the
                // "dash + circles" pattern from the legend.
                drawCircle(color = color, radius = 2.dp.toPx(), center = Offset(size.width * 0.5f, y))
            }
        }
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
