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

/**
 * Projection of a peer in the raw mesh.
 *
 * Everything here comes from `DittoPeer` and is therefore available for **indirect**
 * peers too — peers the local device has no connection to. The sync fields
 * (`synced_up_to_local_commit_id`, `last_update_received_time`) deliberately do NOT
 * live here: they come from `system:data_sync_info`, a local table computed from where
 * this device actually receives data, so it has no rows for indirect peers at all. The
 * presence viewer joins those in separately for the peers that have them.
 *
 * [os], [dittoSdkVersion] and [isCompatible] are nullable because the SDK learns them
 * gradually — a peer can appear in the graph before they are known.
 */
data class MeshPeer(
    val peerKey: String,
    val deviceName: String?,
    val os: PeerOS = PeerOS.Unknown,
    val dittoSdkVersion: String? = null,
    /** Whether THIS peer has a Ditto Cloud link — true even for peers we can't reach. */
    val isConnectedToDittoServer: Boolean = false,
    val isCompatible: Boolean? = null,
    /** Raw peer metadata JSON, or null when empty. Capped at 4 KB by the SDK. */
    val peerMetadata: String? = null,
    /** Top-level key count of [peerMetadata] — the card shows a badge, not the blob. */
    val peerMetadataKeyCount: Int = 0,
    /** Raw identity-service metadata JSON (set by the auth webhook), or null when empty. */
    val identityServiceMetadata: String? = null,
    val identityServiceMetadataKeyCount: Int = 0,
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
