import CoreGraphics
import Foundation
import Testing
@testable import Ditto_Edge_Studio

// MARK: - NetworkLayoutEngine Tests
//
// Port of the VS Code extension's `src/test/NetworkLayoutEngine.test.ts` — the
// two engines are kept in lockstep (the TS one is a port of this one), so these
// scenarios are the shared behavioral contract. The expanded-mode cases cover
// the large-mesh packing ported back from the extension (EXPANDED_RADIUS_SCALE,
// packBfsRings, measured pill footprints).

@Suite("NetworkLayoutEngine")
struct NetworkLayoutEngineTests {
    private typealias Conn = NetworkLayoutEngine.ConnectionInfo

    private func edge(_ from: String, _ to: String) -> Conn {
        Conn(fromPeer: from, toPeer: to)
    }

    private func angle(of point: CGPoint) -> CGFloat {
        var a = atan2(point.y, point.x)
        if a < 0 { a += 2 * .pi }
        return a
    }

    private func radius(of point: CGPoint) -> CGFloat {
        (point.x * point.x + point.y * point.y).squareRoot()
    }

    // MARK: BFS ring assignment (compact mode)

    @Test("lone local peer → only ring 0", .tags(.fast))
    func loneLocalPeer() {
        // ARRANGE + ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: ["local"], connections: []
        )

        // ASSERT
        #expect(r.ringAssignments.count == 1)
        #expect(r.ringAssignments[0] == ["local"])
        #expect(r.positions["local"] == .zero)
    }

    @Test("two-peer chain — one ring-1 peer at the top", .tags(.fast))
    func twoPeerChain() {
        // ARRANGE + ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: ["local", "A"], connections: [edge("local", "A")]
        )

        // ASSERT — first ring-1 peer sits at 90° → x≈0, y≈radius
        #expect(r.ringAssignments[1] == ["A"])
        let a = try? #require(r.positions["A"])
        #expect(abs(a?.x ?? 1) < 1e-6)
        #expect((a?.y ?? 0) > 100)
    }

    @Test("chain of 3 — ring-2 peer sits on its parent's radial, further out", .tags(.fast))
    func chainOfThree() {
        // ARRANGE + ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: ["local", "A", "B"],
            connections: [edge("local", "A"), edge("A", "B")]
        )

        // ASSERT
        #expect(r.ringAssignments[1] == ["A"])
        #expect(r.ringAssignments[2] == ["B"])
        let a = r.positions["A"]!
        let b = r.positions["B"]!
        #expect(abs(angle(of: a) - angle(of: b)) < 1e-6)
        #expect(radius(of: b) > radius(of: a))
    }

    @Test("star with 4 ring-1 peers and no inter-peer edges → evenly spaced", .tags(.fast))
    func starEvenSpacing() {
        // ARRANGE + ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: ["local", "A", "B", "C", "D"],
            connections: [edge("local", "A"), edge("local", "B"), edge("local", "C"), edge("local", "D")]
        )

        // ASSERT — adjacent angle gaps are all π/2
        #expect(r.ringAssignments[1]?.count == 4)
        let angles = ["A", "B", "C", "D"].map { angle(of: r.positions[$0]!) }.sorted()
        for i in 1 ..< angles.count {
            #expect(abs((angles[i] - angles[i - 1]) - .pi / 2) < 1e-6)
        }
    }

    @Test("disconnected peer parked in the outermost ring", .tags(.fast))
    func disconnectedPeerParked() {
        // ARRANGE + ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: ["local", "A", "orphan"],
            connections: [edge("local", "A")]
        )

        // ASSERT
        #expect(r.ringAssignments[1] == ["A"])
        #expect(r.ringAssignments[2] == ["orphan"])
    }

    @Test("ring with many peers expands radius beyond base", .tags(.fast))
    func crowdedRingExpands() {
        // ARRANGE — 20 ring-1 peers × 80pt circumference needs > base radius
        let peers = ["local"] + (0 ..< 20).map { "P\($0)" }
        let connections = peers.dropFirst().map { edge("local", $0) }

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections
        )

        // ASSERT — base ring 1 is 123.75; crowding must expand it past 200
        #expect((r.ringRadii[1] ?? 0) > 200)
    }

    @Test("small ring with wide pills expands to the chord floor, not just the arc floor", .tags(.fast))
    func chordAwareRingExpansion() {
        // ARRANGE — 4 direct peers × 340pt pills. The arc floor is
        // 4×(340+20)/2π ≈ 229, but equal-angle peers are separated by the CHORD
        // 2R·sin(π/4) ≈ 1.41R — 324pt at the arc floor, short of the 360pt
        // footprint. The chord floor requires R ≥ 360/(2·sin(π/4)) ≈ 254.6.
        let direct = (0 ..< 4).map { "P\($0)" }
        let peers = ["local"] + direct
        let connections = direct.map { edge("local", $0) }
        let footprints = Dictionary(uniqueKeysWithValues: direct.map { ($0, CGFloat(340)) })

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: peers,
            connections: connections,
            peerFootprints: footprints
        )

        // ASSERT — the radius meets the chord floor…
        let chordFloor = 360 / (2 * sin(CGFloat.pi / 4))
        #expect((r.ringRadii[1] ?? 0) >= chordFloor - 0.5, "ring radius is below the chord floor")

        // …and adjacent centres never come closer than a pill width (no overlap).
        let positions = direct.map { r.positions[$0]! }
        for i in positions.indices {
            let next = positions[(i + 1) % positions.count]
            let distance = hypot(positions[i].x - next.x, positions[i].y - next.y)
            #expect(distance >= 340, "adjacent pills overlap: centre distance \(distance) < 340")
        }
    }

    @Test("mixed scenario (3 direct + 2 multihop + 1 orphan) is consistent", .tags(.fast))
    func mixedScenario() {
        // ARRANGE
        let peers = ["local", "A", "B", "C", "X", "Y", "Z"]
        let connections = [
            edge("local", "A"), edge("local", "B"), edge("local", "C"),
            edge("A", "X"), edge("B", "Y"),
        ]

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections
        )

        // ASSERT
        #expect(r.ringAssignments[0] == ["local"])
        #expect(r.ringAssignments[1]?.count == 3)
        #expect(r.ringAssignments[2]?.count == 2)
        #expect(r.ringAssignments[3] == ["Z"])
        for peer in peers {
            #expect(r.positions[peer] != nil, "missing position for \(peer)")
        }
    }

    // MARK: Expanded mode (radiusScale > 1)

    @Test("radiusScale spreads rings outward proportionally", .tags(.fast))
    func radiusScaleSpreadsRings() {
        // ARRANGE — 4-peer star; the crowding floor doesn't kick in, so the
        // scale is the only factor.
        let peers = ["local", "A", "B", "C", "D"]
        let connections = [edge("local", "A"), edge("local", "B"), edge("local", "C"), edge("local", "D")]

        // ACT
        let engine = NetworkLayoutEngine()
        let r1 = engine.calculateLayout(localPeerKey: "local", allPeers: peers, connections: connections)
        let r2 = engine.calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        // ASSERT — ring 1 radius scales exactly 1.75×; same angles, bigger radius
        let radius1 = r1.ringRadii[1] ?? 0
        let radius2 = r2.ringRadii[1] ?? 0
        #expect(abs(radius2 - radius1 * 1.75) < 1e-6)
        for key in ["A", "B", "C", "D"] {
            let p1 = r1.positions[key]!
            let p2 = r2.positions[key]!
            #expect(abs(p2.x - p1.x * 1.75) < 1e-6, "\(key).x should scale 1.75×")
            #expect(abs(p2.y - p1.y * 1.75) < 1e-6, "\(key).y should scale 1.75×")
        }
    }

    @Test("expanded mode packs a crowded BFS layer into concentric rings", .tags(.fast))
    func expandedPacking() {
        // ARRANGE — 12 direct peers + 1 multi-hop peer off direct-0
        let direct = (0 ..< 12).map { "direct-\($0)" }
        let peers = ["local"] + direct + ["indirect"]
        var connections = direct.map { edge("local", $0) }
        connections.append(edge("direct-0", "indirect"))

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        // ASSERT — hop order still decides who sits innermost: ring 1 is all direct
        // peers and the multi-hop peer lands on the outermost ring. What it must NOT
        // do is claim a ring of its own — before the balanced packer, "indirect" was
        // alone on ring 3 at a radius half again as large as ring 2, dangling on a
        // long spoke.
        let ring1 = r.ringAssignments[1] ?? []
        let ring2 = r.ringAssignments[2] ?? []
        #expect(!ring1.isEmpty && ring1.allSatisfy { direct.contains($0) })
        #expect(ring2.count > 1, "the multi-hop peer must share a ring, not get its own")
        #expect(ring2.contains("indirect"), "the multi-hop peer belongs on the outermost ring")
        #expect(r.ringAssignments[3] == nil)

        // Visual rings must expand outward.
        let radii = r.ringRadii.filter { $0.key > 0 }.sorted { $0.key < $1.key }.map(\.value)
        for i in 1 ..< radii.count {
            #expect(radii[i] > radii[i - 1], "visual rings must expand outward")
        }

        #expect(r.positions.count == peers.count)
    }

    @Test("expanded mode evenly spaces peers within every visual ring", .tags(.fast))
    func expandedEvenSpacing() {
        // ARRANGE — 30 direct peers overflow ring 1 into several visual rings
        let peers = ["local"] + (0 ..< 30).map { "P\($0)" }
        let connections = peers.dropFirst().map { edge("local", $0) }

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        // ASSERT — each populated visual ring is evenly spaced
        for (ring, ringPeers) in r.ringAssignments where ring > 0 && ringPeers.count > 1 {
            let angles = ringPeers.map { angle(of: r.positions[$0]!) }.sorted()
            let expectedGap = 2 * CGFloat.pi / CGFloat(ringPeers.count)
            for i in 1 ..< angles.count {
                #expect(
                    abs((angles[i] - angles[i - 1]) - expectedGap) < 1e-6,
                    "ring \(ring) is not evenly spaced"
                )
            }
        }
    }

    @Test("expanded mode uses supplied pill footprints when packing rings", .tags(.fast))
    func expandedUsesFootprints() {
        // ARRANGE — 12 direct peers with very wide (340pt) pills
        let direct = (0 ..< 12).map { "P\($0)" }
        let peers = ["local"] + direct
        let connections = direct.map { edge("local", $0) }
        let footprints = Dictionary(uniqueKeysWithValues: direct.map { ($0, CGFloat(340)) })

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local",
            allPeers: peers,
            connections: connections,
            radiusScale: 1.75,
            peerFootprints: footprints
        )

        // ASSERT — wide pills reduce visual-ring capacity…
        let ring1 = r.ringAssignments[1] ?? []
        #expect(ring1.count < direct.count)

        // …and the chord between neighbors is never shorter than the pill width.
        for (ring, ringPeers) in r.ringAssignments where ring > 0 && ringPeers.count > 1 {
            let positions = ringPeers.map { r.positions[$0]! }
            for i in positions.indices {
                let next = positions[(i + 1) % positions.count]
                let distance = hypot(positions[i].x - next.x, positions[i].y - next.y)
                #expect(distance >= 340, "ring \(ring) chord is too short: \(distance)")
            }
        }
    }

    @Test("expanded mode continues outward beyond 100 peers", .tags(.fast))
    func expandedBeyondHundredPeers() {
        // ARRANGE
        let peers = ["local"] + (0 ..< 101).map { "P\($0)" }
        let connections = peers.dropFirst().map { edge("local", $0) }

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        // ASSERT
        let visualRings = r.ringAssignments.keys.filter { $0 > 0 }
        #expect(visualRings.count >= 5, "expected at least 5 visual rings, got \(visualRings.count)")
        #expect(r.positions.count == peers.count)
        let uniquePositions = Set(r.positions.values.map { "\($0.x),\($0.y)" })
        #expect(uniquePositions.count == peers.count, "large meshes must not reuse a position")
    }

    @Test("radiusScale does not shrink rings below the crowding floor", .tags(.fast))
    func crowdingFloorNotScaled() {
        // ARRANGE — 20 ring-1 peers; scaling DOWN must not overlap pills
        let peers = ["local"] + (0 ..< 20).map { "P\($0)" }
        let connections = peers.dropFirst().map { edge("local", $0) }

        // ACT — 0.1 is below 1, so this is compact mode with a tiny scale
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 0.1
        )

        // ASSERT — floor is ~254 (20 × 80pt / 2π); the tiny scale must not shrink it
        #expect((r.ringRadii[1] ?? 0) > 200)
    }

    @Test("rerunning the same input produces the same output (determinism)", .tags(.fast))
    func determinism() {
        // ARRANGE
        let peers = ["local", "A", "B", "C", "D"]
        let connections = [
            edge("local", "A"), edge("local", "B"), edge("local", "C"), edge("local", "D"),
            edge("A", "B"), edge("C", "D"),
        ]
        let engine = NetworkLayoutEngine()

        // ACT
        let a = engine.calculateLayout(localPeerKey: "local", allPeers: peers, connections: connections)
        let b = engine.calculateLayout(localPeerKey: "local", allPeers: peers, connections: connections)

        // ASSERT
        for key in peers {
            #expect(a.positions[key] == b.positions[key], "position for \(key) differs across runs")
        }
    }

    // MARK: Balanced rings (expanded mode)

    /// Peer counts per ring, innermost first (ring 0 excluded).
    private func ringSizes(_ r: NetworkLayoutEngine.LayoutResult) -> [Int] {
        r.ringAssignments.keys.sorted().filter { $0 > 0 }
            .map { r.ringAssignments[$0]?.count ?? 0 }
    }

    private func fullMesh(_ peerCount: Int) -> NetworkLayoutEngine.LayoutResult {
        let peers = ["local"] + (0 ..< peerCount).map { String(format: "P%03d", $0) }
        var connections: [Conn] = []
        for i in 0 ..< peers.count {
            for j in (i + 1) ..< peers.count {
                connections.append(edge(peers[i], peers[j]))
            }
        }
        return NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )
    }

    @Test("no ring is left stranded with a lone peer", .tags(.fast))
    func noStrandedRings() {
        // ARRANGE — 14 fully-meshed peers plus a 2-hop and a 3-hop straggler. This is
        // the on-device shape: the stragglers each used to take a whole ring to
        // themselves, hundreds of points out, on a spoke pointing straight up.
        let core = (0 ..< 14).map { String(format: "core%02d", $0) }
        let peers = ["local"] + core + ["hop2", "hop3"]
        let meshed = ["local"] + core
        var connections: [Conn] = []
        for i in 0 ..< meshed.count {
            for j in (i + 1) ..< meshed.count {
                connections.append(edge(meshed[i], meshed[j]))
            }
        }
        connections.append(edge(core[0], "hop2"))
        connections.append(edge("hop2", "hop3"))

        // ACT
        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        // ASSERT
        let sizes = ringSizes(r)
        #expect(sizes.allSatisfy { $0 > 1 }, "every ring must carry more than one peer, got \(sizes)")
        #expect(r.positions.count == peers.count)
    }

    @Test("ring populations grow outward, never trailing off into a remainder", .tags(.fast))
    func ringsGrowOutward() {
        // 60 peers used to pack as 6/12/17/23/2 — two nodes stranded on the outermost
        // orbit at the largest radius in the scene.
        for peerCount in [12, 25, 40, 60, 90, 120] {
            let sizes = ringSizes(fullMesh(peerCount))
            #expect(sizes.reduce(0, +) == peerCount, "all \(peerCount) peers must be placed")
            for i in 1 ..< sizes.count {
                #expect(
                    sizes[i] >= sizes[i - 1],
                    "orbits must not shrink outward at n=\(peerCount), got \(sizes)"
                )
            }
        }
    }

    @Test("neighbour spacing stays comparable across orbits", .tags(.fast))
    func spacingBalancedAcrossRings() {
        // Capacity-proportional sharing is what makes the rings read as balanced: the
        // chord between neighbours should be roughly equal on every orbit.
        let r = fullMesh(60)
        let gaps = r.ringAssignments.keys.sorted().filter { $0 > 0 }.map { ring -> CGFloat in
            let count = CGFloat(r.ringAssignments[ring]?.count ?? 1)
            return 2 * (r.ringRadii[ring] ?? 0) * sin(.pi / count)
        }
        let smallest = gaps.min() ?? 0
        let largest = gaps.max() ?? 0
        #expect(largest <= smallest * 2, "spacing should stay within 2x across rings, got \(gaps)")
    }

    @Test("a three-hop chain collapses onto one orbit instead of one ring per hop", .tags(.fast))
    func shortChainUsesOneOrbit() {
        let peers = ["local", "a", "b", "c"]
        let connections = [edge("local", "a"), edge("a", "b"), edge("b", "c")]

        let r = NetworkLayoutEngine().calculateLayout(
            localPeerKey: "local", allPeers: peers, connections: connections, radiusScale: 1.75
        )

        #expect(ringSizes(r) == [3], "three peers fit a single orbit")
    }

    @Test("consecutive rings do not stack their first peer on the same spoke", .tags(.fast))
    func ringsAreStaggered() {
        let r = fullMesh(120)
        let startAngles = r.ringAssignments.keys.sorted().filter { $0 > 0 }
            .compactMap { ring -> CGFloat? in
                guard let first = r.ringAssignments[ring]?.first,
                      let point = r.positions[first] else { return nil }
                return angle(of: point)
            }
        let distinct = Set(startAngles.map { Int(($0 * 1000).rounded()) })
        #expect(
            distinct.count == startAngles.count,
            "every ring started at 90 degrees, drawing a seam straight up"
        )
    }
}
