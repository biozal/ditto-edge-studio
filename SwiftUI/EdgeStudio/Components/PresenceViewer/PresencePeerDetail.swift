import Foundation

/// Everything the presence viewer's detail card shows about one peer.
///
/// Every field except the last three comes from the presence graph, which reports the
/// same shape whether or not the local device can reach the peer — so this is populated
/// for **indirect** peers too. That matters: a focus orbit is the *focused* peer's
/// neighbourhood, not ours, so most of it is usually unreachable from here.
///
/// [syncedUpToLocalCommitId] and [lastUpdateReceivedTime] come from
/// `system:data_sync_info`, a local table computed from where this device actually
/// receives data. It has rows only for peers we hold a sync session with — never for
/// indirect peers, and never for ourselves. [isDirectlyConnected] and [isLocal] let the
/// card distinguish "a session exists and nothing has synced yet" from "there is no
/// session to report on", which is the difference worth showing.
struct PresencePeerDetail: Equatable, Identifiable {
    var id: String {
        peerKey
    }

    let peerKey: String
    let displayName: String
    let isLocal: Bool

    // Presence-graph facts — available for indirect peers as well.
    let os: PeerOS?
    let sdkVersion: String?
    let isConnectedToDittoCloud: Bool
    let isCompatible: Bool?

    /// Raw metadata JSON and its top-level key count. The card shows the count; the JSON
    /// is kept for a detail sheet. Nil when the peer has set none.
    let peerMetadataJSON: String?
    let peerMetadataKeyCount: Int
    let identityMetadataJSON: String?
    let identityMetadataKeyCount: Int

    // Sync session — direct peers only, see the type doc.
    let isDirectlyConnected: Bool
    let syncedUpToLocalCommitId: Int?
    let lastUpdateReceivedTime: TimeInterval?

    /// Build a detail record from a presence-graph peer.
    ///
    /// - Parameters:
    ///   - peer: the peer as reported by the presence graph, direct or not.
    ///   - isLocal: whether this is the local device. The local peer has no
    ///     `system:data_sync_info` row — that table records what *remote* peers have
    ///     confirmed of our commits — so its sync fields are always nil and the card
    ///     says "This device" rather than implying a missing connection.
    ///   - isDirectlyConnected: derived from the aggregated presence edges, i.e. from
    ///     `PresenceEdgeAggregator.directVisiblePeerKeys`, which is the same test that
    ///     decides which peers `system:data_sync_info` has rows for.
    ///   - syncStatus: the peer's sync row, when one exists.
    init(
        peer: any PeerProtocol,
        isLocal: Bool,
        isDirectlyConnected: Bool,
        syncStatus: SyncStatusInfo?
    ) {
        peerKey = peer.peerKeyString
        displayName = isLocal
            ? "Me"
            : (peer.deviceName.isEmpty ? String(peer.peerKeyString.prefix(8)) : peer.deviceName)
        self.isLocal = isLocal

        // Prefer the presence graph, which covers indirect peers, and fall back to the
        // enrichment on the sync row for anything it has not learned yet.
        os = peer.peerOS ?? syncStatus?.osInfo
        sdkVersion = peer.sdkVersionString ?? syncStatus?.dittoSDKVersion
        isConnectedToDittoCloud = peer.isConnectedToDittoCloud
        isCompatible = peer.isCompatiblePeer

        let peerMeta = peer.peerMetadataJSON
        peerMetadataJSON = peerMeta?.json ?? syncStatus?.peerMetadata
        peerMetadataKeyCount = peerMeta?.keyCount ?? 0
        let identityMeta = peer.identityMetadataJSON
        identityMetadataJSON = identityMeta?.json ?? syncStatus?.identityMetadata
        identityMetadataKeyCount = identityMeta?.keyCount ?? 0

        // The local device never has a sync row, so it is never "directly connected" in
        // the sense this flag means — a session with oneself does not exist.
        self.isDirectlyConnected = isLocal ? false : isDirectlyConnected
        syncedUpToLocalCommitId = isLocal ? nil : syncStatus?.syncedUpToLocalCommitId
        lastUpdateReceivedTime = isLocal ? nil : syncStatus?.lastUpdateReceivedTime
    }
}
