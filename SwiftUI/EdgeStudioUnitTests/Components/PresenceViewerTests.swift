import SpriteKit
import Testing

import DittoSwift

@testable import Ditto_Edge_Studio

// MARK: - PresenceEdgeAggregator Tests
//
// `PresenceEdgeAggregator` is the single source the presence scene's
// change-detection pass and draw pass both build from. These tests pin the two
// behaviors that were historically buggy when the two passes each had their own
// collection loop:
//
//   1. The local peer's own connection list is aggregated too. Ditto usually
//      reports an undirected edge from both endpoints, but the local peer is the
//      authoritative source for edges attached to this process — a transport
//      (notably multicast) vanished from the graph when only the local side
//      advertised it. (Same fix as the VS Code extension's
//      `buildPresenceGraphView`.)
//   2. Edges are deduplicated by (sorted pair, type) while parallel transports
//      between the same pair survive, and the direct-only filter matches
//      docs/PRESENCE_GRAPH.md.

@Suite("PresenceEdgeAggregator Tests")
struct PresenceEdgeAggregatorTests {
    private func makeLocal(connections: [MockConnection] = []) -> MockPeer {
        MockPeer(peerKey: "local", deviceName: "Local", connections: connections)
    }

    private func makeRemote(_ key: String, connections: [MockConnection] = []) -> MockPeer {
        MockPeer(peerKey: key, deviceName: key, connections: connections)
    }

    @Test("Edge advertised only by the local peer (multicast) is included", .tags(.fast))
    func localOnlyEdgeIsIncluded() {
        // ARRANGE: local reports a multicast edge to B; B reports nothing
        let local = makeLocal(connections: [
            MockConnection(type: .multicast, id: "1<->2:Multicast", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")

        // ACT
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: local,
            remotePeers: [remoteB],
            showDirectConnectedOnly: false
        )

        // ASSERT
        #expect(edges.count == 1)
        #expect(edges.first?.type == .multicast)
        #expect(edges.first?.pairKey == "B_local")
    }

    @Test("A→B and B→A reports from both endpoints dedupe to one edge", .tags(.fast))
    func bidirectionalReportsDedupe() {
        // ARRANGE: both sides report the same bluetooth edge
        let local = makeLocal(connections: [
            MockConnection(type: .bluetooth, id: "1<->2:Bluetooth", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B", connections: [
            MockConnection(type: .bluetooth, id: "2<->1:Bluetooth", peerKeyString1: "B", peerKeyString2: "local")
        ])

        // ACT
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: local,
            remotePeers: [remoteB],
            showDirectConnectedOnly: false
        )

        // ASSERT
        #expect(edges.count == 1)
        #expect(edges.first?.type == .bluetooth)
    }

    @Test("Parallel transports between the same pair are kept", .tags(.fast))
    func parallelTransportsSurvive() {
        // ARRANGE: local↔B over both bluetooth and p2pWiFi
        let local = makeLocal(connections: [
            MockConnection(type: .bluetooth, id: "1<->2:Bluetooth", peerKeyString1: "local", peerKeyString2: "B"),
            MockConnection(type: .p2pWiFi, id: "1<->2:P2PWiFi", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")

        // ACT
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: local,
            remotePeers: [remoteB],
            showDirectConnectedOnly: false
        )

        // ASSERT
        #expect(edges.count == 2)
        #expect(Set(edges.map(\.type)) == [.bluetooth, .p2pWiFi])
        #expect(Set(edges.map(\.pairKey)).count == 1)
    }

    @Test("Direct-only filter drops chords between remote peers", .tags(.fast))
    func directOnlyDropsChords() {
        // ARRANGE: A↔B chord that does not involve local
        let remoteA = makeRemote("A", connections: [
            MockConnection(type: .p2pWiFi, id: "2<->3:P2PWiFi", peerKeyString1: "A", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")

        // ACT
        let directEdges = PresenceEdgeAggregator.aggregate(
            localPeer: makeLocal(),
            remotePeers: [remoteA, remoteB],
            showDirectConnectedOnly: true
        )
        let meshEdges = PresenceEdgeAggregator.aggregate(
            localPeer: makeLocal(),
            remotePeers: [remoteA, remoteB],
            showDirectConnectedOnly: false
        )

        // ASSERT
        #expect(directEdges.isEmpty)
        #expect(meshEdges.count == 1)
    }

    @Test("Connections with an empty endpoint key are dropped", .tags(.fast))
    func emptyEndpointsDropped() {
        // ARRANGE
        let local = makeLocal(connections: [
            MockConnection(type: .bluetooth, id: "bad", peerKeyString1: "local", peerKeyString2: "")
        ])

        // ACT
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: local,
            remotePeers: [],
            showDirectConnectedOnly: false
        )

        // ASSERT
        #expect(edges.isEmpty)
    }

    // MARK: Visible-set derivation (Direct + Expanded mode filtering)
    //
    // The viewer derives each mode's visible peers from the aggregated edges,
    // never from each remote peer's own connection list — otherwise a peer
    // whose edge only the local side advertises (multicast) is hidden in
    // Direct mode, and orphan peers render as floating pills in Expanded mode
    // (extension `buildGraphInput` / `buildPresenceGraphView` pass 2 parity).

    @Test("Direct visible set includes a peer whose edge only the local side advertises", .tags(.fast))
    func directVisibleSetIncludesLocalOnlyEdgePeer() {
        // ARRANGE: local reports a multicast edge to B; B reports nothing (the
        // multicast asymmetry). C participates in no edge at all.
        let local = makeLocal(connections: [
            MockConnection(type: .multicast, id: "1<->2:Multicast", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")
        let remoteC = makeRemote("C")

        // ACT
        let visible = PresenceEdgeAggregator.directVisiblePeerKeys(
            localPeer: local,
            remotePeers: [remoteB, remoteC]
        )

        // ASSERT — B is visible via the local-advertised edge; C is not
        #expect(visible == ["B"])
    }

    @Test("Direct mode: every aggregated edge endpoint is in the visible set", .tags(.fast))
    func directEdgesDrawableFromVisibleSet() {
        // ARRANGE: local→B multicast advertised only by local; an A↔B chord
        // advertised by A (dropped in Direct mode).
        let local = makeLocal(connections: [
            MockConnection(type: .multicast, id: "1<->2:Multicast", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteA = makeRemote("A", connections: [
            MockConnection(type: .p2pWiFi, id: "2<->3:P2PWiFi", peerKeyString1: "A", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")

        // ACT — mirror the view-model → scene pipeline: filter the remotes by
        // the visible set, then aggregate the edges the scene would expect.
        let all = [remoteA, remoteB]
        let visible = PresenceEdgeAggregator.directVisiblePeerKeys(localPeer: local, remotePeers: all)
        let visiblePeers = all.filter { visible.contains($0.peerKeyString) }
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: local,
            remotePeers: visiblePeers,
            showDirectConnectedOnly: true
        )
        let nodeKeys = Set(visiblePeers.map(\.peerKeyString)).union(["local"])

        // ASSERT — expected == drawable: every expected edge has both endpoints
        // in the node set, so the scene's change detection settles (a mismatch
        // rebuilds the lines on every push and flickers the fade-in).
        #expect(visible == ["B"])
        #expect(edges.count == 1)
        for edge in edges {
            #expect(nodeKeys.contains(edge.from))
            #expect(nodeKeys.contains(edge.to))
        }
    }

    @Test("Mesh visible set drops orphan peers but keeps edge-only endpoints", .tags(.fast))
    func meshVisibleSetDropsOrphans() {
        // ARRANGE: X appears only as peer2 of Y's advertised edge (kept — a
        // peer reachable only via another's connection list still draws);
        // Z participates in no edge (dropped — the sync stop→start orphan).
        let local = makeLocal(connections: [
            MockConnection(type: .bluetooth, id: "1<->2:Bluetooth", peerKeyString1: "local", peerKeyString2: "B")
        ])
        let remoteB = makeRemote("B")
        let remoteY = makeRemote("Y", connections: [
            MockConnection(type: .p2pWiFi, id: "3<->4:P2PWiFi", peerKeyString1: "Y", peerKeyString2: "X")
        ])
        let remoteX = makeRemote("X")
        let remoteZ = makeRemote("Z")

        // ACT
        let visible = PresenceEdgeAggregator.meshVisiblePeerKeys(
            localPeer: local,
            remotePeers: [remoteB, remoteY, remoteX, remoteZ]
        )

        // ASSERT — the local peer and every edge participant are visible; the
        // orphan is not.
        #expect(visible.contains("local"))
        #expect(visible.contains("B"))
        #expect(visible.contains("X"))
        #expect(visible.contains("Y"))
        #expect(!visible.contains("Z"))
    }
}

// MARK: - ConnectionLine Multicast Style Tests
//
// Multicast renders as a bright golden-yellow dotted line (#FFD60A, dash [2,3])
// so it stands apart from the red P2P WiFi, blue Bluetooth, green LAN, and
// orange WebSocket lines — matching the VS Code extension's legend.

@Suite("ConnectionLine Multicast Style Tests")
struct ConnectionLineMulticastStyleTests {
    @Test("Multicast line uses the golden-yellow transport color", .tags(.fast))
    func multicastLineColor() {
        // ARRANGE + ACT
        let line = ConnectionLine(
            from: "local",
            to: "peerB",
            type: .multicast,
            fromPos: .zero,
            toPos: CGPoint(x: 100, y: 0)
        )

        // ASSERT
        #expect(line.getConnectionType() == .multicast)
        let color = line.getColor()
        #expect(abs(color.redComponent - 1.0) < 0.01)
        #expect(abs(color.greenComponent - 0.84) < 0.01)
        #expect(abs(color.blueComponent - 0.04) < 0.01)
    }

    @Test("Multicast color is distinct from the other transport colors", .tags(.fast))
    func multicastColorDistinctness() {
        // ARRANGE + ACT
        let multicast = ConnectionLine(from: "a", to: "b", type: .multicast, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))
        let bluetooth = ConnectionLine(from: "a", to: "b", type: .bluetooth, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))
        let lan = ConnectionLine(from: "a", to: "b", type: .accessPoint, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))
        let p2p = ConnectionLine(from: "a", to: "b", type: .p2pWiFi, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))
        let webSocket = ConnectionLine(from: "a", to: "b", type: .webSocket, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))

        // ASSERT
        let others = [bluetooth, lan, p2p, webSocket].map { $0.getColor() }
        for other in others {
            #expect(multicast.getColor() != other)
        }
    }
}
