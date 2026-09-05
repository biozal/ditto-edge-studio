import CoreGraphics
import Foundation
import Testing

@testable import Ditto_Edge_Studio

/// Unit tests for `NetworkLayoutEngine` — the BFS ring layout behind the presence
/// viewer.
///
/// Focus is on expanded (full-mesh) mode, which is new here: before it existed, every
/// peer landed on a single ring whose crowding floor inflated the radius without bound,
/// so a large mesh was one enormous unreadable circle. The Android port found two
/// further defects in the shared algorithm that these tests pin down: a BFS layer used
/// to claim a fresh visual ring even when it held one peer, stranding it hundreds of
/// points out on a spoke; and every ring started at exactly 90°, drawing a seam of
/// stacked nodes straight up.
@Suite("NetworkLayoutEngine")
struct NetworkLayoutEngineTests {
    private let expandedScale = NetworkLayoutEngine.expandedRadiusScale

    // MARK: - Helpers

    /// Layout a mesh where every peer is connected to every other peer.
    private func fullMesh(_ peerCount: Int, radiusScale: CGFloat) -> NetworkLayoutEngine.LayoutResult {
        let peers = ["local"] + (0 ..< peerCount).map { String(format: "P%03d", $0) }
        var connections: [NetworkLayoutEngine.ConnectionInfo] = []
        for i in 0 ..< peers.count {
            for j in (i + 1) ..< peers.count {
                connections.append(.init(fromPeer: peers[i], toPeer: peers[j]))
            }
        }
        return NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) }),
            connections: connections,
            radiusScale: radiusScale
        )
    }

    /// Peer counts per ring, innermost first (ring 0 excluded).
    private func ringSizes(_ result: NetworkLayoutEngine.LayoutResult) -> [Int] {
        result.ringAssignments.keys.sorted().filter { $0 > 0 }
            .map { result.ringAssignments[$0]?.count ?? 0 }
    }

    private func angle(of peer: String, in result: NetworkLayoutEngine.LayoutResult) -> CGFloat {
        guard let point = result.positions[peer] else { return 0 }
        var a = atan2(point.y, point.x)
        if a < 0 { a += 2 * .pi }
        return a
    }

    // MARK: - Expanded mode exists at all

    @Test("Expanded mode spreads a large mesh across several concentric rings")
    func expandedModePacksMultipleRings() {
        let result = fullMesh(60, radiusScale: expandedScale)
        let sizes = ringSizes(result)

        #expect(sizes.count >= 4, "60 peers should occupy several orbits, got \(sizes)")
        #expect(sizes.reduce(0, +) == 60)
        #expect(result.positions.count == 61)
    }

    @Test("Compact mode still puts every direct peer on ring 1")
    func compactModeUnchanged() {
        let result = fullMesh(12, radiusScale: 1.0)
        #expect(ringSizes(result) == [12], "compact mode must keep its single-orbit behaviour")
    }

    // MARK: - Balanced rings

    @Test("No ring is left holding a single stranded peer")
    func noStrandedRings() {
        // The on-device symptom: multi-hop stragglers each took a whole ring to
        // themselves, hundreds of points out, on a spoke pointing straight up.
        let core = (0 ..< 14).map { String(format: "core%02d", $0) }
        let peers = ["local"] + core + ["hop2", "hop3"]
        var connections: [NetworkLayoutEngine.ConnectionInfo] = []
        let meshed = ["local"] + core
        for i in 0 ..< meshed.count {
            for j in (i + 1) ..< meshed.count {
                connections.append(.init(fromPeer: meshed[i], toPeer: meshed[j]))
            }
        }
        connections.append(.init(fromPeer: core[0], toPeer: "hop2"))
        connections.append(.init(fromPeer: "hop2", toPeer: "hop3"))

        let result = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) }),
            connections: connections,
            radiusScale: expandedScale
        )

        let sizes = ringSizes(result)
        #expect(sizes.allSatisfy { $0 > 1 }, "every ring must carry more than one peer, got \(sizes)")
        #expect(result.positions.count == peers.count)
    }

    @Test("Ring populations grow outward and never trail off into a remainder")
    func ringsGrowOutward() {
        // 60 peers used to pack as 6/12/17/23/2 — two nodes stranded on the outermost
        // orbit.
        for peerCount in [12, 25, 40, 60, 90, 120] {
            let sizes = ringSizes(fullMesh(peerCount, radiusScale: expandedScale))
            #expect(sizes.reduce(0, +) == peerCount, "all \(peerCount) peers must be placed")
            for index in 1 ..< sizes.count {
                #expect(
                    sizes[index] >= sizes[index - 1],
                    "orbits must not shrink outward at n=\(peerCount), got \(sizes)"
                )
            }
        }
    }

    @Test("Neighbour spacing stays comparable across orbits")
    func spacingIsBalancedAcrossRings() {
        // Capacity-proportional sharing is what makes the rings read as balanced: the
        // chord between neighbours should be roughly the same on every orbit.
        let result = fullMesh(60, radiusScale: expandedScale)
        let gaps = result.ringAssignments.keys.sorted().filter { $0 > 0 }.map { ring -> CGFloat in
            let count = CGFloat(result.ringAssignments[ring]?.count ?? 1)
            let radius = result.ringRadii[ring] ?? 0
            return 2 * radius * sin(.pi / count)
        }
        let smallest = gaps.min() ?? 0
        let largest = gaps.max() ?? 0
        #expect(largest <= smallest * 2, "spacing should stay within 2x across rings, got \(gaps)")
    }

    @Test("A three-hop chain collapses onto one orbit instead of one ring per hop")
    func shortChainUsesOneOrbit() {
        let peers = ["local", "a", "b", "c"]
        let connections: [NetworkLayoutEngine.ConnectionInfo] = [
            .init(fromPeer: "local", toPeer: "a"),
            .init(fromPeer: "a", toPeer: "b"),
            .init(fromPeer: "b", toPeer: "c")
        ]

        let result = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) }),
            connections: connections,
            radiusScale: expandedScale
        )

        #expect(ringSizes(result) == [3], "three peers fit a single orbit")
    }

    // MARK: - Ring angle stagger

    @Test("Consecutive rings do not stack their first peer on the same spoke")
    func ringsAreStaggered() {
        let result = fullMesh(120, radiusScale: expandedScale)
        let startAngles = result.ringAssignments.keys.sorted().filter { $0 > 0 }
            .compactMap { ring -> CGFloat? in
                guard let first = result.ringAssignments[ring]?.first else { return nil }
                return angle(of: first, in: result)
            }
        let distinct = Set(startAngles.map { Int(($0 * 1000).rounded()) })
        #expect(
            distinct.count == startAngles.count,
            "every ring started at 90 degrees, drawing a seam straight up"
        )
    }

    // MARK: - Footprints

    @Test("Measured pill widths reduce how many peers share an orbit")
    func widePillsReduceRingCapacity() {
        let peers = ["local"] + (0 ..< 12).map { "P\($0)" }
        let connections = peers.dropFirst().map {
            NetworkLayoutEngine.ConnectionInfo(fromPeer: "local", toPeer: $0)
        }
        let allPeers = Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) })
        let wide = Dictionary(uniqueKeysWithValues: peers.dropFirst().map { ($0, CGFloat(340)) })

        let engine = NetworkLayoutEngine()
        let narrowResult = engine.calculateLayout(
            localPeerKey: "local", allPeers: allPeers, connections: Array(connections),
            radiusScale: expandedScale
        )
        let wideResult = engine.calculateLayout(
            localPeerKey: "local", allPeers: allPeers, connections: Array(connections),
            radiusScale: expandedScale, peerFootprints: wide
        )

        let innermostNarrow = narrowResult.ringAssignments[1]?.count ?? 0
        let innermostWide = wideResult.ringAssignments[1]?.count ?? 0
        #expect(innermostWide <= innermostNarrow, "wide pills must not pack tighter than narrow ones")
        #expect(wideResult.positions.count == peers.count)
    }

    @Test("Neighbours on a ring are never closer than the widest pill")
    func chordAlwaysFitsTheWidestPill() {
        let peers = ["local"] + (0 ..< 12).map { "P\($0)" }
        let connections = peers.dropFirst().map {
            NetworkLayoutEngine.ConnectionInfo(fromPeer: "local", toPeer: $0)
        }
        let footprints = Dictionary(uniqueKeysWithValues: peers.dropFirst().map { ($0, CGFloat(340)) })

        let result = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) }),
            connections: Array(connections),
            radiusScale: expandedScale,
            peerFootprints: footprints
        )

        for (ring, ringPeers) in result.ringAssignments where ring > 0 && ringPeers.count > 1 {
            let points = ringPeers.compactMap { result.positions[$0] }
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                let distance = hypot(points[index].x - next.x, points[index].y - next.y)
                #expect(distance >= 340 - 0.5, "ring \(ring) chord too short: \(distance)")
            }
        }
    }

    // MARK: - Regressions preserved from the original engine

    @Test("Every peer gets a unique position in a large mesh")
    func noOverlappingPositions() {
        let result = fullMesh(120, radiusScale: expandedScale)
        let unique = Set(result.positions.values.map { "\($0.x),\($0.y)" })
        #expect(unique.count == result.positions.count, "large meshes must not reuse a position")
    }

    @Test("The local peer stays at the origin")
    func localPeerAtOrigin() {
        let result = fullMesh(30, radiusScale: expandedScale)
        #expect(result.positions["local"] == .zero)
        #expect(result.ringRadii[0] == 0)
    }

    @Test("A disconnected peer is still placed rather than dropped")
    func disconnectedPeerIsPlaced() {
        let peers = ["local", "a", "b", "orphan"]
        let connections: [NetworkLayoutEngine.ConnectionInfo] = [
            .init(fromPeer: "local", toPeer: "a"),
            .init(fromPeer: "local", toPeer: "b")
        ]

        let result = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: Dictionary(uniqueKeysWithValues: peers.map { ($0, 0) }),
            connections: connections,
            radiusScale: expandedScale
        )

        #expect(result.positions["orphan"] != nil, "a disconnected peer must still be laid out")
        #expect(result.positions.count == peers.count)
    }
}
