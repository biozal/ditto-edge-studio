package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo

/**
 * Synthetic peer key for the Ditto Cloud node. Mirrors the iOS scene's
 * `PresenceNetworkScene.cloudNodeKey`. Never collides with a real SDK-issued peer key
 * (peer keys are base64 strings far longer than this constant).
 */
const val CLOUD_NODE_KEY: String = "ditto-cloud-node"

/** Display name for the synthetic cloud node. Matches iOS `PeerNode` label "Ditto Cloud". */
const val CLOUD_NODE_DISPLAY_NAME: String = "Ditto Cloud"

/** Heuristic classification of a peer from its device name — drives the pill color. */
enum class PeerDeviceKind { Phone, Laptop, Cloud, Server }

/**
 * One node in the presence graph. Pure data; ephemeral animation state (scale, alpha,
 * position) lives in `PresenceGraphView` via `Animatable` lookup by [peerId].
 */
@Immutable
data class PeerNode(
    val peerId: String,
    val displayName: String,
    val deviceKind: PeerDeviceKind,
    val isLocal: Boolean,
    val isCloud: Boolean,
)

/**
 * One edge in the presence graph. The [edgeId] is the stable identity used for
 * Animatable lookups and for change-detection between successive projections.
 * [pairKey] groups parallel edges between the same two peers so the renderer can
 * apply offsets for visual separation.
 */
@Immutable
data class PeerEdge(
    val edgeId: String,
    val pairKey: String,
    val fromPeerId: String,
    val toPeerId: String,
    val type: ConnectionType,
    val isCloud: Boolean,
    /**
     * When true the renderer pushes the Bézier control point radially outward from the
     * scene origin (the local peer at center). Used for remote↔remote edges so the arc
     * bends around the outside of the peer cluster instead of cutting through it.
     */
    val arcOutward: Boolean,
)

/**
 * Camera transform for pan/zoom. Pure data; updated inside `remember { mutableStateOf(...) }`
 * by gesture handlers. Reads happen inside `drawBehind` only — updates therefore invalidate
 * the draw layer without recomposing children.
 */
@Stable
data class Transform(val offset: Offset, val scale: Float) {
    companion object {
        val Identity: Transform = Transform(Offset.Zero, 1f)

        /**
         * Minimum zoom. The VS Code extension uses 0.25, but it renders into a
         * desktop panel roughly 1500 dp wide. A 120-node full mesh spans ~2590 dp
         * including pills, which needs 0.13 to frame on a 344 dp phone screen and
         * 0.27 on an unfolded Fold — so 0.25 clamps the auto-fit and clips the
         * outer ring on exactly the large meshes that most need an overview.
         */
        const val MIN_SCALE: Float = 0.1f

        /** 2.0 = the VS Code extension's maximum zoom (plan open question #6:
         *  align, resolved in review). */
        const val MAX_SCALE: Float = 2.0f
    }
}

/**
 * Pure focus-mode decisions for [PresenceGraphView] — the VS Code extension's
 * `scene.ts` focus view (`neighboursOf`,
 * `clampZoom(min(max(zoom, FOCUS_ZOOM), fitZoom))`), extracted for JVM unit tests.
 *
 * Note the Compose [Transform.scale] IS the magnification (higher = zoomed in),
 * so the extension's zoom formula applies directly — no camera-scale inversion
 * like on SpriteKit.
 */
internal object PresenceFocusPlanner {
    /** Default focus magnification (extension `FOCUS_ZOOM`). */
    const val FOCUS_ZOOM: Float = 1.25f

    /** Focus-view context dimming — the rest of the mesh stays as backdrop. */
    const val CONTEXT_PEER_ALPHA: Float = 0.08f
    const val CONTEXT_LINE_ALPHA: Float = 0.04f

    /** Keys directly connected to [key] among [edges] — sorted, no self. */
    fun neighbourKeys(key: String, edges: List<PeerEdge>): List<String> {
        val neighbours = sortedSetOf<String>()
        for (edge in edges) {
            if (edge.fromPeerId == key && edge.toPeerId != key) neighbours += edge.toPeerId
            if (edge.toPeerId == key && edge.fromPeerId != key) neighbours += edge.fromPeerId
        }
        return neighbours.toList()
    }

    /** Max magnification that fits the content in the viewport (1f when degenerate). */
    fun fitZoom(
        contentWidthPx: Float,
        contentHeightPx: Float,
        viewWidthPx: Float,
        viewHeightPx: Float,
    ): Float {
        if (contentWidthPx <= 0f || contentHeightPx <= 0f || viewWidthPx <= 0f || viewHeightPx <= 0f) {
            return 1f
        }
        return minOf(viewWidthPx / contentWidthPx, viewHeightPx / contentHeightPx)
    }

    /**
     * Zoom at which a whole mesh layout — the outermost ring PLUS the widest peer
     * pill and a margin — fits inside the viewport.
     *
     * Peer names are drawn inside their pill, so fitting the *pill* footprint (not
     * just the ring radius) is what guarantees every device name stays fully on
     * screen. That matters most on narrow displays: a folded Galaxy Z Fold cover
     * screen is 344 dp wide, while one expanded ring already spans ~433 dp plus a
     * pill, so the default 100% camera clips the left/right pills against the
     * view's `clipToBounds()`.
     *
     * The margin is treated as if it scaled with the content, which errs slightly
     * conservative (a marginally wider fit than strictly required) — matching the
     * Direct-mode fit this generalises.
     *
     * @param maxRingRadiusDp outermost ring radius in the layout engine's dp space.
     * @param maxPillWidthPx  widest measured pill at 1x zoom.
     * @param marginPx        breathing room around the content at 1x zoom.
     */
    @Suppress("LongParameterList")
    fun meshFitZoom(
        maxRingRadiusDp: Float,
        maxPillWidthPx: Float,
        pxPerDp: Float,
        viewWidthPx: Float,
        viewHeightPx: Float,
        marginPx: Float,
    ): Float {
        if (maxRingRadiusDp <= 0f || pxPerDp <= 0f) return 1f
        val contentPx = (maxRingRadiusDp * 2f * pxPerDp) + maxPillWidthPx + marginPx
        if (contentPx <= 0f) return 1f
        return fitZoom(contentPx, contentPx, viewWidthPx, viewHeightPx)
            .coerceIn(Transform.MIN_SCALE, Transform.MAX_SCALE)
    }

    /**
     * Focus zoom target: magnify to at least [FOCUS_ZOOM], never exceed the fit for
     * the complete neighbourhood, clamped to the view's scale range. The extension's
     * `clampZoom(min(max(zoom, FOCUS_ZOOM), fitZoom))` verbatim.
     */
    fun focusScale(fitZoom: Float, currentZoom: Float): Float =
        minOf(maxOf(currentZoom, FOCUS_ZOOM), fitZoom)
            .coerceIn(Transform.MIN_SCALE, Transform.MAX_SCALE)
}

/**
 * Projected graph model: nodes + edges + the local peer's id (or null if unavailable).
 * Produced by [toGraphModel]; consumed by the layout engine and the renderer.
 *
 * [isExpandedProjection] reports which projection was ACTUALLY built — not which
 * mode the toggle is in. The full-mesh builder falls back to the direct-only star
 * when no mesh topology has been published yet, and that fallback must lay out at
 * the compact (1×) scale, not the expanded one.
 */
@Immutable
data class PresenceGraphModel(
    val nodes: List<PeerNode>,
    val edges: List<PeerEdge>,
    val localPeerId: String?,
    val isExpandedProjection: Boolean = false,
)

/**
 * Classify a peer's device kind from its device name. Mirrors the iOS
 * `PeerNode.DeviceType.detect(from:)` heuristic so the same name produces the same icon
 * color on both platforms.
 */
internal fun detectDeviceKind(deviceName: String?): PeerDeviceKind {
    val name = deviceName?.lowercase().orEmpty()
    return when {
        name.contains("iphone") || name.contains("ipad") ||
            name.contains("pixel") || name.contains("galaxy") ||
            name.contains("mobile") || name.contains("android") -> PeerDeviceKind.Phone

        name.contains("macbook") || name.contains("imac") ||
            name.contains("mac mini") || name.contains("mac studio") ||
            name.contains("windows") || name.contains("surface") ||
            name.contains("laptop") -> PeerDeviceKind.Laptop

        // Tightened from `contains("ditto")` — "Ditto Server" (an on-prem product)
        // would otherwise collide with the synthetic Big-Peer "Ditto Cloud" node and
        // be drawn as a cloud pill instead of a server.
        name.contains("ditto cloud") || name == "cloud" -> PeerDeviceKind.Cloud

        else -> PeerDeviceKind.Server
    }
}

/**
 * Build a graph model from the current peers state.
 *
 * Two modes, matching iOS `PresenceViewerSK.updateSceneWithCurrentFilter`:
 *
 * **showDirectConnectedOnly = true** — uses the pre-filtered [remotePeers] list (only
 * peers directly connected to local) and derives edges from each peer's `connections`
 * field (already filtered to local ↔ peer + deduped by type at the repository layer).
 * Emits exactly one edge per (local, peer, transport-type) tuple. Result: a tight star
 * graph centered on "Me".
 *
 * **showDirectConnectedOnly = false** — switches to [meshTopology], the unfiltered
 * presence-graph snapshot. Surfaces every peer the SDK knows about plus every
 * connection between them — including remote↔remote edges that aren't anchored at the
 * local device. Result: the full mesh, matching iOS's off-mode rendering.
 *
 * Always: filter out Ditto Server peers (synthesized from sync metrics, not part of
 * the presence graph), and append a synthetic "Ditto Cloud" node + edge when
 * `localPeer.isCloudConnected` is true. iOS does the same.
 */
fun PeersUiState.Active.toGraphModel(
    showDirectConnectedOnly: Boolean,
): PresenceGraphModel {
    val local = localPeer ?: return PresenceGraphModel(emptyList(), emptyList(), null)
    val localId = local.peerId

    return if (showDirectConnectedOnly) {
        buildDirectOnlyModel(local, localId)
    } else {
        buildFullMeshModel(local, localId)
    }
}

private fun PeersUiState.Active.buildDirectOnlyModel(
    local: LocalPeerInfo,
    localId: String,
): PresenceGraphModel {
    val nodes = mutableListOf<PeerNode>()
    nodes.add(
        PeerNode(
            peerId = localId,
            displayName = "Me",
            deviceKind = detectDeviceKind(local.deviceName),
            isLocal = true,
            isCloud = false,
        ),
    )

    val realRemotePeers = remotePeers.filterNot { it.isDittoServer }

    // Edges first: the Direct node set derives from the surviving edges'
    // endpoints (extension parity). A peer whose connections were all stripped
    // by the repository's enabled-transport filter must NOT render as an
    // edgeless floating node.
    val edges = mutableListOf<PeerEdge>()
    val seenPairTypes = mutableSetOf<String>()
    val connectedPeerIds = mutableSetOf<String>()
    for (peer in realRemotePeers) {
        for (conn in peer.connections) {
            val pairKey = listOf(localId, peer.peerId).sorted().joinToString(separator = "_")
            val edgeId = "${pairKey}_${conn.type}"
            if (!seenPairTypes.add(edgeId)) continue
            connectedPeerIds += peer.peerId
            edges.add(
                PeerEdge(
                    edgeId = edgeId,
                    pairKey = pairKey,
                    fromPeerId = localId,
                    toPeerId = peer.peerId,
                    type = conn.type,
                    isCloud = false,
                    arcOutward = false,
                ),
            )
        }
    }

    for (peer in realRemotePeers) {
        if (peer.peerId !in connectedPeerIds) continue
        nodes.add(
            PeerNode(
                peerId = peer.peerId,
                displayName = peer.deviceName?.takeIf { it.isNotBlank() } ?: peer.peerId.take(8),
                deviceKind = detectDeviceKind(peer.deviceName),
                isLocal = false,
                isCloud = false,
            ),
        )
    }

    appendCloudNodeAndEdge(local, localId, nodes, edges)
    return PresenceGraphModel(
        nodes = nodes,
        edges = edges,
        localPeerId = localId,
        isExpandedProjection = false,
    )
}

/**
 * Build the full-mesh graph from [meshTopology]. Includes peers not directly
 * connected to local, and edges between remote peers (peer A ↔ peer B where neither
 * endpoint is local) — those edges arc outward so they route around the central
 * cluster instead of cutting across it.
 */
private fun PeersUiState.Active.buildFullMeshModel(
    local: LocalPeerInfo,
    localId: String,
): PresenceGraphModel {
    val mesh = meshTopology
    // If the repository hasn't published a meshTopology yet (e.g. first observe
    // emission still in flight), fall back to the direct-only projection rather
    // than rendering a one-node "Me" graph from MeshTopology.Empty.
    if (mesh.localPeerKey.isBlank()) {
        return buildDirectOnlyModel(local, localId)
    }
    val nodes = mutableListOf<PeerNode>()
    nodes.add(
        PeerNode(
            peerId = localId,
            displayName = "Me",
            deviceKind = detectDeviceKind(local.deviceName),
            isLocal = true,
            isCloud = false,
        ),
    )

    // Carry direct-peer device-name overrides forward so a peer that's both in
    // SyncStatusInfo and the raw graph keeps the same label.
    val directNameById = remotePeers.associate { it.peerId to it.deviceName }
    for (peer in mesh.peers) {
        if (peer.peerKey == localId) continue
        val name = directNameById[peer.peerKey]?.takeIf { !it.isNullOrBlank() }
            ?: peer.deviceName?.takeIf { it.isNotBlank() }
            ?: peer.peerKey.take(8)
        nodes.add(
            PeerNode(
                peerId = peer.peerKey,
                displayName = name,
                deviceKind = detectDeviceKind(name),
                isLocal = false,
                isCloud = false,
            ),
        )
    }

    val edges = mutableListOf<PeerEdge>()
    val seenPairTypes = mutableSetOf<String>()
    for (edge in mesh.edges) {
        val sortedPair = listOf(edge.peer1, edge.peer2).sorted()
        val pairKey = sortedPair.joinToString(separator = "_")
        val edgeId = "${pairKey}_${edge.type}"
        if (!seenPairTypes.add(edgeId)) continue
        val isRemoteToRemote = edge.peer1 != localId && edge.peer2 != localId
        edges.add(
            PeerEdge(
                edgeId = edgeId,
                pairKey = pairKey,
                fromPeerId = edge.peer1,
                toPeerId = edge.peer2,
                type = edge.type,
                isCloud = false,
                // Remote↔remote edges arc outward so they bend around the cluster
                // rather than passing through unrelated nodes near the center.
                arcOutward = isRemoteToRemote,
            ),
        )
    }

    appendCloudNodeAndEdge(local, localId, nodes, edges)
    return PresenceGraphModel(
        nodes = nodes,
        edges = edges,
        localPeerId = localId,
        isExpandedProjection = true,
    )
}

private fun appendCloudNodeAndEdge(
    local: LocalPeerInfo,
    localId: String,
    nodes: MutableList<PeerNode>,
    edges: MutableList<PeerEdge>,
) {
    if (!local.isCloudConnected) return
    nodes.add(
        PeerNode(
            peerId = CLOUD_NODE_KEY,
            displayName = CLOUD_NODE_DISPLAY_NAME,
            deviceKind = PeerDeviceKind.Cloud,
            isLocal = false,
            isCloud = true,
        ),
    )
    val pairKey = listOf(localId, CLOUD_NODE_KEY).sorted().joinToString(separator = "_")
    edges.add(
        PeerEdge(
            edgeId = "cloud_$localId",
            pairKey = pairKey,
            fromPeerId = localId,
            toPeerId = CLOUD_NODE_KEY,
            type = ConnectionType.WebSocket,
            isCloud = true,
            arcOutward = false,
        ),
    )
}
