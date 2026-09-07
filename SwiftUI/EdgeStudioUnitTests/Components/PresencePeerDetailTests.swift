import Foundation
import Testing

@testable import Ditto_Edge_Studio

/// Unit tests for `PresencePeerDetail` — the payload behind the presence viewer's
/// focus-mode detail card.
///
/// The property that matters is the three-way sync split. `system:data_sync_info` is a
/// local table computed from where this device actually receives data, so it has rows
/// only for peers we hold a session with — never for an indirect peer, and never for
/// ourselves. The card has to tell those apart rather than rendering a blank, and these
/// pin that down.
@Suite("PresencePeerDetail")
struct PresencePeerDetailTests {
    private func mockPeer(
        key: String = "p1",
        name: String = "Pixel 10a",
        cloud: Bool = false
    ) -> MockPeer {
        MockPeer(peerKey: key, deviceName: name, connections: [], isConnectedToDittoCloud: cloud)
    }

    private func syncStatus(commit: Int?, lastUpdate: TimeInterval?) -> SyncStatusInfo {
        var documents: [String: Any] = [:]
        if let commit { documents["synced_up_to_local_commit_id"] = commit }
        if let lastUpdate { documents["last_update_received_time"] = lastUpdate }
        return SyncStatusInfo(from: ["_id": "p1", "documents": documents])
    }

    // MARK: Sync three-way split

    @Test("A directly connected peer carries its commit id and last update", .tags(.fast))
    func directPeerCarriesSyncProgress() {
        let detail = PresencePeerDetail(
            peer: mockPeer(),
            isLocal: false,
            isDirectlyConnected: true,
            syncStatus: syncStatus(commit: 42, lastUpdate: 1_700_000_000_000)
        )

        #expect(detail.isDirectlyConnected)
        #expect(detail.syncedUpToLocalCommitId == 42)
        #expect(detail.lastUpdateReceivedTime == 1_700_000_000_000)
    }

    @Test("An indirect peer reports no sync session at all", .tags(.fast))
    func indirectPeerHasNoSyncSession() {
        // No row exists for it, so the card must say "no sync session" rather than
        // rendering an empty commit id that reads as a bug.
        let detail = PresencePeerDetail(
            peer: mockPeer(),
            isLocal: false,
            isDirectlyConnected: false,
            syncStatus: nil
        )

        #expect(!detail.isDirectlyConnected)
        #expect(detail.syncedUpToLocalCommitId == nil)
        #expect(detail.lastUpdateReceivedTime == nil)
    }

    @Test("The local peer is never 'directly connected' and never has sync rows", .tags(.fast))
    func localPeerIsItsOwnCase() {
        // data_sync_info records what REMOTE peers confirmed of OUR commits, so there is
        // no row for ourselves. Even handed one, the local card must not claim progress.
        let detail = PresencePeerDetail(
            peer: mockPeer(key: "local", name: "This Mac"),
            isLocal: true,
            isDirectlyConnected: true,
            syncStatus: syncStatus(commit: 99, lastUpdate: 1_700_000_000_000)
        )

        #expect(detail.isLocal)
        #expect(!detail.isDirectlyConnected, "a session with oneself does not exist")
        #expect(detail.syncedUpToLocalCommitId == nil)
        #expect(detail.lastUpdateReceivedTime == nil)
        #expect(detail.displayName == "Me")
    }

    // MARK: Presence-graph facts survive for indirect peers

    @Test("Presence-graph facts are populated regardless of reachability", .tags(.fast))
    func presenceFactsPopulatedForIndirectPeers() {
        // The whole reason the card is worth opening on a peer we cannot reach.
        let detail = PresencePeerDetail(
            peer: mockPeer(cloud: true),
            isLocal: false,
            isDirectlyConnected: false,
            syncStatus: nil
        )

        #expect(detail.peerKey == "p1")
        #expect(detail.displayName == "Pixel 10a")
        #expect(detail.isConnectedToDittoCloud, "a peer we can't reach may still have a cloud link")
    }

    @Test("A blank device name falls back to a truncated peer key", .tags(.fast))
    func blankDeviceNameFallsBack() {
        let detail = PresencePeerDetail(
            peer: mockPeer(key: "abcdefghijklmnop", name: ""),
            isLocal: false,
            isDirectlyConnected: false,
            syncStatus: nil
        )

        #expect(detail.displayName == "abcdefgh")
    }

    @Test("Sync-row enrichment fills gaps the presence graph has not learned yet", .tags(.fast))
    func syncEnrichmentFillsUnknownFields() {
        // MockPeer returns nil for the detail fields (protocol defaults), standing in for
        // a peer whose OS and SDK version the SDK has not reported yet.
        var documents: [String: Any] = [:]
        documents["synced_up_to_local_commit_id"] = 7
        let enriched = SyncStatusInfo(
            from: ["_id": "p1", "documents": documents],
            peerEnrichment: PeerEnrichmentData(
                deviceName: "Pixel 10a",
                osInfo: .android(version: nil),
                dittoSDKVersion: "5.1.0",
                addressInfo: nil,
                identityMetadata: nil,
                peerMetadata: nil,
                connections: nil
            )
        )

        let detail = PresencePeerDetail(
            peer: mockPeer(),
            isLocal: false,
            isDirectlyConnected: true,
            syncStatus: enriched
        )

        #expect(detail.os == .android(version: nil))
        #expect(detail.sdkVersion == "5.1.0")
    }

    @Test("Metadata key counts default to zero when the peer reports none", .tags(.fast))
    func metadataDefaultsToNone() {
        let detail = PresencePeerDetail(
            peer: mockPeer(),
            isLocal: false,
            isDirectlyConnected: true,
            syncStatus: nil
        )

        #expect(detail.peerMetadataKeyCount == 0)
        #expect(detail.peerMetadataJSON == nil)
        #expect(detail.identityMetadataKeyCount == 0)
    }

    // MARK: PeerOS bridge (shared with SystemRepository)

    @Test("PeerOS(dittoPeerOS:) is nil for an unknown peer OS", .tags(.fast))
    func peerOSBridgeHandlesNil() {
        #expect(PeerOS(dittoPeerOS: nil) == nil)
    }
}
