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
        const val MIN_SCALE: Float = 0.5f
        const val MAX_SCALE: Float = 2.5f
    }
}

/**
 * Projected graph model: nodes + edges + the local peer's id (or null if unavailable).
 * Produced by [toGraphModel]; consumed by the layout engine and the renderer.
 */
@Immutable
data class PresenceGraphModel(
    val nodes: List<PeerNode>,
    val edges: List<PeerEdge>,
    val localPeerId: String?,
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

        name.contains("cloud") || name.contains("ditto") -> PeerDeviceKind.Cloud

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
    for (peer in realRemotePeers) {
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

    val edges = mutableListOf<PeerEdge>()
    val seenPairTypes = mutableSetOf<String>()
    for (peer in realRemotePeers) {
        for (conn in peer.connections) {
            val pairKey = listOf(localId, peer.peerId).sorted().joinToString(separator = "_")
            val edgeId = "${pairKey}_${conn.type}"
            if (!seenPairTypes.add(edgeId)) continue
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

    appendCloudNodeAndEdge(local, localId, nodes, edges)
    return PresenceGraphModel(nodes = nodes, edges = edges, localPeerId = localId)
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
    return PresenceGraphModel(nodes = nodes, edges = edges, localPeerId = localId)
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
