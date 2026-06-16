package com.costoda.dittoedgestudio.domain.model

/**
 * Snapshot of the full presence-graph mesh, captured directly from the SDK with NO
 * direct-connection filtering. Used by the Presence Viewer when "Direct Connected
 * Only" is toggled off — that mode reveals every peer Ditto knows about plus every
 * connection between them, matching the iOS PresenceViewerSK off-mode behavior.
 *
 * The default UI paths (peer cards, transport counts) keep using the filtered
 * `SyncStatusInfo` collection from `SystemRepository.peers` — those views must
 * remain direct-only per the project-wide presence-graph pitfall rule.
 */
data class MeshTopology(
    val localPeerKey: String,
    val peers: List<MeshPeer>,
    val edges: List<MeshEdge>,
) {
    companion object {
        val Empty: MeshTopology = MeshTopology(
            localPeerKey = "",
            peers = emptyList(),
            edges = emptyList(),
        )
    }
}

/** Minimal projection of a peer in the raw mesh — only what the graph view needs. */
data class MeshPeer(
    val peerKey: String,
    val deviceName: String?,
)

/**
 * One mesh edge with full endpoint identities. Deduplicated by sorted (peer1, peer2, type)
 * — the SDK returns A→B and B→A as separate `DittoConnection` instances with the same
 * type, which the repository collapses before exposing.
 */
data class MeshEdge(
    val peer1: String,
    val peer2: String,
    val type: ConnectionType,
)
