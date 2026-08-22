import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Additional `SyncStatusViewModel` coverage beyond `SyncStatusViewModelTests`,
/// plus model coverage for `ConnectionsByTransport` (the transport-count value
/// type the VM publishes to the connection status bar).
///
/// Not covered here (and why): `mergeStatusItems` is `private` and only reachable
/// via the `SystemRepository` sync-status callback wired in `installCallbacks`;
/// driving it deterministically needs a fake repository that invokes the stored
/// closure, which the current `MockSystemRepository` does not. `loadLocalPeerInfo`
/// needs a live `Ditto` (`dittoSelectedApp` is `nil` in the mock, so it logs and
/// returns without mutating state). Both belong to integration tests.
@Suite("SyncStatusViewModel — transport state & reset", .serialized)
struct SyncStatusViewModelMoreTests {
    @Test(.tags(.fast))
    @MainActor
    func `connectionsByTransport defaults to empty`() {
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )

        #expect(viewModel.connectionsByTransport == .empty)
        #expect(viewModel.connectionsByTransport.totalConnections == 0)
    }

    @Test(.tags(.fast))
    @MainActor
    func `toggleSync off clears transport connection counts`() async throws {
        // ARRANGE — seed a non-empty transport snapshot. Sync now starts STOPPED, so the
        // test must start it before it can meaningfully toggle it off.
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )
        try await viewModel.toggleSync() // start
        #expect(viewModel.isSyncEnabled, "precondition: sync must be running to toggle off")
        viewModel.connectionsByTransport = ConnectionsByTransport(webSocket: 3)
        #expect(viewModel.connectionsByTransport.totalConnections == 3)

        // ACT — toggling sync off should wipe the live caches.
        try await viewModel.toggleSync()

        // ASSERT
        #expect(viewModel.isSyncEnabled == false)
        #expect(viewModel.connectionsByTransport == .empty)
    }

    @Test(.tags(.fast))
    @MainActor
    func `reset clears connectionsByTransport along with the rest`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )
        viewModel.connectionsByTransport = ConnectionsByTransport(bluetooth: 2)
        viewModel.localPeerSDKVersion = "5.0.0"

        // ACT
        viewModel.reset()

        // ASSERT — `reset()` clears the caches; it no longer writes sync state.
        #expect(viewModel.connectionsByTransport == .empty)
        #expect(viewModel.localPeerSDKVersion == nil)
    }
}

// MARK: - ConnectionsByTransport model coverage

/// Pure-model tests for `ConnectionsByTransport` aggregation and dictionary
/// parsing — the value the sync VM publishes for the connection status bar.
@Suite("ConnectionsByTransport — aggregation & parsing", .serialized)
struct ConnectionsByTransportModelTests {
    @Test(.tags(.model, .fast))
    func `totalConnections sums every transport`() {
        let transports = ConnectionsByTransport(
            accessPoint: 1,
            bluetooth: 2,
            dittoServer: 3,
            p2pWiFi: 4,
            webSocket: 5
        )

        #expect(transports.totalConnections == 15)
        #expect(transports.hasActiveConnections == true)
    }

    @Test(.tags(.model, .fast))
    func `empty has no active connections`() {
        #expect(ConnectionsByTransport.empty.totalConnections == 0)
        #expect(ConnectionsByTransport.empty.hasActiveConnections == false)
    }

    @Test(.tags(.model, .fast))
    func `init from dictionary parses the connections_by_transport map`() {
        // ARRANGE
        let dict: [String: Any] = [
            "connections_by_transport": [
                "WebSocket": 2,
                "Bluetooth": 1,
                "AccessPoint": 0,
                "P2PWiFi": 0,
                "DittoServer": 3
            ]
        ]

        // ACT
        let transports = ConnectionsByTransport(from: dict)

        // ASSERT
        #expect(transports.webSocket == 2)
        #expect(transports.bluetooth == 1)
        #expect(transports.dittoServer == 3)
        #expect(transports.totalConnections == 6)
    }

    @Test(.tags(.model, .fast))
    func `init from dictionary without the key yields all zeros`() {
        let transports = ConnectionsByTransport(from: ["unrelated": 1])
        #expect(transports == .empty)
    }

    @Test(.tags(.model, .fast))
    func `activeTransports lists only the non-zero transports`() {
        // ARRANGE — only WebSocket and Bluetooth are active.
        let transports = ConnectionsByTransport(bluetooth: 1, webSocket: 2)

        // ACT
        let active = transports.activeTransports

        // ASSERT — exactly two entries, with the expected names/counts.
        #expect(active.count == 2)
        #expect(active.contains { $0.name == "WebSocket" && $0.count == 2 })
        #expect(active.contains { $0.name == "Bluetooth" && $0.count == 1 })
    }

    // MARK: - Multicast (beta transport added in Ditto SDK 5.1.0)

    @Test(.tags(.model, .fast))
    func `totalConnections includes multicast`() {
        let transports = ConnectionsByTransport(
            accessPoint: 1,
            bluetooth: 2,
            dittoServer: 3,
            p2pWiFi: 4,
            webSocket: 5,
            multicast: 6
        )

        #expect(transports.multicast == 6)
        #expect(transports.totalConnections == 21)
    }

    @Test(.tags(.model, .fast))
    func `init from dictionary parses the Multicast key`() {
        // ARRANGE
        let dict: [String: Any] = [
            "connections_by_transport": [
                "Multicast": 2,
                "Bluetooth": 1
            ]
        ]

        // ACT
        let transports = ConnectionsByTransport(from: dict)

        // ASSERT
        #expect(transports.multicast == 2)
        #expect(transports.bluetooth == 1)
        #expect(transports.totalConnections == 3)
    }

    @Test(.tags(.model, .fast))
    func `activeTransports includes multicast when non-zero`() {
        // ARRANGE
        let transports = ConnectionsByTransport(multicast: 3)

        // ACT
        let active = transports.activeTransports

        // ASSERT
        #expect(active.count == 1)
        #expect(active.contains { $0.name == "Multicast" && $0.count == 3 })
    }

    @Test(.tags(.model, .fast))
    func `dominantConnectionType reports multicast and ranks it below p2p`() {
        // ARRANGE — a peer connected over multicast only, and one over both p2p and multicast.
        let multicastOnly = SyncStatusInfo(
            from: [:],
            peerEnrichment: makeEnrichment(types: [.multicast])
        )
        let p2pAndMulticast = SyncStatusInfo(
            from: [:],
            peerEnrichment: makeEnrichment(types: [.multicast, .p2pWiFi])
        )

        // ASSERT — multicast surfaces on its own, but p2p still wins when both are present.
        #expect(multicastOnly.dominantConnectionType == "multicast")
        #expect(p2pAndMulticast.dominantConnectionType == "p2p")
    }

    /// Builds enrichment data carrying one connection per requested transport type.
    private func makeEnrichment(types: [ConnectionType]) -> PeerEnrichmentData {
        PeerEnrichmentData(
            deviceName: nil,
            osInfo: nil,
            dittoSDKVersion: nil,
            addressInfo: nil,
            identityMetadata: nil,
            peerMetadata: nil,
            connections: types.enumerated().map { index, type in
                ConnectionInfo(
                    id: "conn-\(index)",
                    type: type,
                    peerKeyString1: "local",
                    peerKeyString2: "remote",
                    approximateDistanceInMeters: nil
                )
            }
        )
    }

    @Test(.tags(.model, .fast))
    func `multicast connection type has its own display metadata`() {
        // ASSERT — multicast is a first-class type, not folded into `.unknown`.
        #expect(ConnectionType.multicast.displayName == "Multicast")
        #expect(ConnectionType.multicast.cardColor != ConnectionType.unknown("").cardColor)
        #expect(ConnectionType.multicast.cardDarkColor != ConnectionType.unknown("").cardDarkColor)
    }
}
