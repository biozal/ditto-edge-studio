import CoreGraphics
import Foundation

/// Advanced layout engine using BFS ring assignment for network topology visualization
/// Assigns peers to rings based on their connection distance from the local peer
class NetworkLayoutEngine {
    // MARK: - Types

    /// Result of layout calculation
    struct LayoutResult {
        let positions: [String: CGPoint]
        let ringAssignments: [Int: [String]]
        let ringRadii: [Int: CGFloat]
    }

    /// Ring information
    private struct Ring {
        let ringNumber: Int
        let radius: CGFloat
        var peerKeys: [String]
    }

    // MARK: - Constants

    private let baseRadius: CGFloat = 123.75 // Ring 1 radius (220 * 0.75 * 0.75)
    private let radiusIncrement: CGFloat = 101.25 // Additional radius per ring (180 * 0.75 * 0.75)
    private let minAngularSeparation: CGFloat = 15.0 * .pi / 180.0 // 15° in radians

    // MARK: - Public Methods

    /// Calculate layout positions for all peers using BFS ring assignment
    /// - Parameters:
    ///   - localPeerKey: The local peer's key (center of diagram)
    ///   - allPeers: Dictionary of all peer nodes
    ///   - connections: Array of connection lines
    /// - Returns: Layout result with positions and ring assignments
    func calculateLayout(
        localPeerKey: String,
        allPeers: [String: Any], // Can't use PeerNode here due to import issues
        connections: [ConnectionInfo]
    ) -> LayoutResult {
        // Build adjacency graph from connections
        let adjacencyGraph = buildAdjacencyGraph(connections: connections, localPeer: localPeerKey)

        // Perform BFS to assign rings and record parent relationships
        let (ringAssignments, parentMap) = performBFS(
            localPeer: localPeerKey,
            adjacencyGraph: adjacencyGraph,
            allPeers: Array(allPeers.keys)
        )

        // Calculate ring radii (may expand if too many peers)
        let ringRadii = calculateRingRadii(ringAssignments: ringAssignments)

        // Calculate positions: ring-1 peers spread evenly in connection-aware order,
        // ring-2+ peers placed behind their parent to avoid crossing unrelated nodes
        let positions = calculatePositions(
            ringAssignments: ringAssignments,
            ringRadii: ringRadii,
            localPeer: localPeerKey,
            parentMap: parentMap,
            adjacencyGraph: adjacencyGraph
        )

        return LayoutResult(
            positions: positions,
            ringAssignments: ringAssignments,
            ringRadii: ringRadii
        )
    }

    // MARK: - Private Methods - Graph Building

    /// Build adjacency graph from connections
    private func buildAdjacencyGraph(connections: [ConnectionInfo], localPeer: String) -> [String: Set<String>] {
        var graph: [String: Set<String>] = [:]

        for connection in connections {
            let peer1 = connection.fromPeer
            let peer2 = connection.toPeer

            // Add bidirectional edges
            graph[peer1, default: []].insert(peer2)
            graph[peer2, default: []].insert(peer1)
        }

        return graph
    }

    // MARK: - Private Methods - BFS Ring Assignment

    /// Perform breadth-first search to assign peers to rings.
    /// Also returns a parentMap (child → parent) so ring-2+ peers can be positioned
    /// behind their parent rather than at an arbitrary angle.
    private func performBFS(
        localPeer: String,
        adjacencyGraph: [String: Set<String>],
        allPeers: [String]
    ) -> (ringAssignments: [Int: [String]], parentMap: [String: String]) {
        var ringAssignments: [Int: [String]] = [:]
        var parentMap: [String: String] = [:]
        var visited: Set<String> = []
        var queue: [(peer: String, ring: Int)] = []

        // Ring 0: Local peer
        ringAssignments[0] = [localPeer]
        visited.insert(localPeer)

        // Start BFS from local peer
        queue.append((localPeer, 0))

        while !queue.isEmpty {
            let (currentPeer, currentRing) = queue.removeFirst()

            // Get neighbors
            guard let neighbors = adjacencyGraph[currentPeer] else { continue }

            for neighbor in neighbors where !visited.contains(neighbor) {
                visited.insert(neighbor)
                let nextRing = currentRing + 1

                parentMap[neighbor] = currentPeer // record which peer discovered this one
                ringAssignments[nextRing, default: []].append(neighbor)
                queue.append((neighbor, nextRing))
            }
        }

        // Handle disconnected peers (assign to outermost ring)
        let disconnectedPeers = Set(allPeers).subtracting(visited)

        if !disconnectedPeers.isEmpty {
            let maxRing = ringAssignments.keys.max() ?? 0
            ringAssignments[maxRing + 1] = Array(disconnectedPeers)
        }

        return (ringAssignments, parentMap)
    }

    // MARK: - Private Methods - Ring Radii

    /// Calculate ring radii, expanding if too many peers
    private func calculateRingRadii(ringAssignments: [Int: [String]]) -> [Int: CGFloat] {
        var ringRadii: [Int: CGFloat] = [:]

        // Ring 0 (local peer) is at center
        ringRadii[0] = 0.0

        for ring in ringAssignments.keys.sorted() where ring > 0 {
            let peerCount = ringAssignments[ring]?.count ?? 0
            let baseRadiusForRing = baseRadius + CGFloat(ring - 1) * radiusIncrement

            // Calculate minimum radius needed to avoid overlaps
            // Assuming peer node size is ~60pt diameter
            let peerDiameter: CGFloat = 60.0
            let minimumCircumference = CGFloat(peerCount) * (peerDiameter + 20.0) // 20pt spacing
            let minimumRadius = minimumCircumference / (2.0 * .pi)

            // Use the larger of base radius or minimum required radius
            ringRadii[ring] = max(baseRadiusForRing, minimumRadius)
        }

        return ringRadii
    }

    // MARK: - Private Methods - Position Calculation

    /// Calculate final positions.
    ///
    /// Ring 1 (directly connected) peers are distributed evenly around the local peer.
    /// Ring 2+ (multihop) peers are placed radially behind their parent — at the same
    /// angle as the parent but at the larger ring radius — so their connecting edge is
    /// a short outward segment rather than a diagonal that crosses unrelated nodes.
    /// Multiple siblings (children of the same parent) are spread symmetrically around
    /// the parent's angle.
    private func calculatePositions(
        ringAssignments: [Int: [String]],
        ringRadii: [Int: CGFloat],
        localPeer: String,
        parentMap: [String: String],
        adjacencyGraph: [String: Set<String>]
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]

        // Local peer at center
        positions[localPeer] = .zero

        for ring in ringAssignments.keys.sorted() where ring > 0 {
            guard let peers = ringAssignments[ring],
                  let radius = ringRadii[ring],
                  !peers.isEmpty else
            {
                continue
            }

            if ring == 1 {
                // Ring 1: sort peers so directly-connected pairs land adjacent on the circle,
                // then distribute evenly. This prevents connection chords from cutting through
                // unrelated nodes that sit between the two endpoints.
                let orderedPeers = sortRing1Peers(peers, adjacencyGraph: adjacencyGraph)
                let angles = calculateOptimalAngles(peerCount: orderedPeers.count)
                for (index, peerKey) in orderedPeers.enumerated() {
                    let angle = angles[index]
                    positions[peerKey] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                }
            } else {
                // Ring 2+: group children by parent and place each group behind its parent.
                // This keeps the connecting edge radial (short, outward) and avoids it
                // cutting through other peer nodes near the center.
                var peersByParent: [String: [String]] = [:]
                for peerKey in peers {
                    let parent = parentMap[peerKey] ?? localPeer
                    peersByParent[parent, default: []].append(peerKey)
                }

                // Build a sorted list of parent angles so each parent's available arc can
                // be computed as the gap to its nearest neighbour. This prevents siblings
                // from spilling into an adjacent parent's angular territory when ring-1 is
                // dense or a single parent has many children.
                let parentAngles: [(key: String, angle: CGFloat)] = peersByParent.keys
                    .compactMap { key -> (String, CGFloat)? in
                        guard let pos = positions[key] else { return nil }
                        return (key, atan2(pos.y, pos.x))
                    }
                    .sorted { $0.1 < $1.1 }

                for (parentKey, children) in peersByParent {
                    let parentPos = positions[parentKey] ?? .zero
                    let parentAngle = atan2(parentPos.y, parentPos.x)

                    // Half-gap to nearest neighbours, capped at 60° so a lone parent
                    // doesn't spread its children across the entire circle.
                    let halfGap: CGFloat
                    if parentAngles.count <= 1 {
                        halfGap = .pi / 3.0
                    } else {
                        let sorted = parentAngles.map(\.angle)
                        let idx = sorted.firstIndex(of: parentAngle) ?? 0
                        let prev = sorted[(idx + sorted.count - 1) % sorted.count]
                        let next = sorted[(idx + 1) % sorted.count]
                        var gapLeft = parentAngle - prev
                        var gapRight = next - parentAngle
                        if gapLeft < 0 { gapLeft += 2 * .pi }
                        if gapRight < 0 { gapRight += 2 * .pi }
                        halfGap = min(min(gapLeft, gapRight) * 0.8, .pi / 3.0)
                    }

                    // Divide the available arc evenly among siblings. Enforce a 15° minimum
                    // per child so two siblings are always visually distinct.
                    let childCount = children.count
                    let siblingSpread: CGFloat = childCount > 1
                        ? max(halfGap * 2.0 / CGFloat(childCount - 1), .pi / 12.0)
                        : 0.0

                    let totalSpan = siblingSpread * CGFloat(childCount - 1)
                    let startAngle = parentAngle - totalSpan / 2.0

                    for (i, child) in children.enumerated() {
                        let angle = startAngle + siblingSpread * CGFloat(i)
                        positions[child] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                    }
                }
            }
        }

        return positions
    }

    /// Reorder ring-1 peers using a greedy double-ended path algorithm so that peers with
    /// direct connections between them end up adjacent on the circle.
    ///
    /// The algorithm:
    /// 1. Build a sub-graph of ring-1 → ring-1 edges only (ignoring the centre node).
    /// 2. Start a path from the highest-degree node in that sub-graph.
    /// 3. Greedily extend the path at the *tail*, then the *head*, prioritising
    ///    neighbours with more ring-1 connections (to keep clusters together).
    /// 4. When no connected neighbour remains at either end, append the next
    ///    highest-degree unvisited peer and continue — this handles disconnected
    ///    sub-graphs (e.g. a peer with no ring-1 peer connections at all).
    ///
    /// The resulting linear order is mapped onto the circle by `calculateOptimalAngles`,
    /// so connected pairs are placed at adjacent angular positions, keeping their
    /// chord short and away from unrelated nodes.
    private func sortRing1Peers(_ peers: [String], adjacencyGraph: [String: Set<String>]) -> [String] {
        guard peers.count > 2 else { return peers }

        let peerSet = Set(peers)

        // Count ring-1 connections (peer-to-peer edges, not spokes to centre)
        var ring1Degree: [String: Int] = [:]
        for peer in peers {
            ring1Degree[peer] = (adjacencyGraph[peer] ?? []).count(where: { peerSet.contains($0) })
        }

        // No inter-peer connections — even distribution is already optimal
        if ring1Degree.values.allSatisfy({ $0 == 0 }) { return peers }

        var remaining = Set(peers)
        var path: [String] = []

        // Start from the peer with the most ring-1 connections (best anchor for clustering)
        let start = peers
            .sorted { $0 < $1 } // secondary sort for determinism
            .max(by: { (ring1Degree[$0] ?? 0) < (ring1Degree[$1] ?? 0) }) ?? peers[0]
        path.append(start)
        remaining.remove(start)

        while !remaining.isEmpty {
            // Try to extend the path at the tail
            let tail = path.last!
            let tailNeighbour = (adjacencyGraph[tail] ?? [])
                .filter { remaining.contains($0) }
                .sorted { // deterministic: degree desc, then key asc
                    let d0 = ring1Degree[$0] ?? 0
                    let d1 = ring1Degree[$1] ?? 0
                    return d0 != d1 ? d0 > d1 : $0 < $1
                }
                .first

            if let next = tailNeighbour {
                path.append(next)
                remaining.remove(next)
                continue
            }

            // Tail is stuck — try to extend at the head instead
            let head = path.first!
            let headNeighbour = (adjacencyGraph[head] ?? [])
                .filter { remaining.contains($0) }
                .sorted {
                    let d0 = ring1Degree[$0] ?? 0
                    let d1 = ring1Degree[$1] ?? 0
                    return d0 != d1 ? d0 > d1 : $0 < $1
                }
                .first

            if let prev = headNeighbour {
                path.insert(prev, at: 0)
                remaining.remove(prev)
                continue
            }

            // Both ends stuck (disconnected sub-graph) — append the highest-degree remainder
            let fallback = remaining
                .sorted { $0 < $1 }
                .max(by: { (ring1Degree[$0] ?? 0) < (ring1Degree[$1] ?? 0) }) ?? remaining.first!
            path.append(fallback)
            remaining.remove(fallback)
        }

        return path
    }

    /// Distribute `peerCount` peers evenly around a full circle, starting at the top (90°).
    private func calculateOptimalAngles(peerCount: Int) -> [CGFloat] {
        guard peerCount > 0 else { return [] }
        let startAngle: CGFloat = .pi / 2.0
        let step: CGFloat = (2.0 * .pi) / CGFloat(peerCount)
        return (0 ..< peerCount).map { startAngle + step * CGFloat($0) }
    }

    // MARK: - Helper Types

    /// Connection information for building the graph
    struct ConnectionInfo {
        let fromPeer: String
        let toPeer: String
    }
}

// MARK: - Extensions

extension NetworkLayoutEngine {
    /// Calculate control point for Bézier curve between two points
    /// Used for cross-ring connections
    static func calculateBezierControlPoint(from: CGPoint, to: CGPoint) -> CGPoint {
        // Calculate midpoint
        let midX = (from.x + to.x) / 2.0
        let midY = (from.y + to.y) / 2.0

        // Calculate perpendicular offset
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        // Curve amount based on distance (more curve for longer lines)
        let curveAmount = min(distance * 0.15, 60.0)

        // Perpendicular direction
        let perpX = -dy / distance * curveAmount
        let perpY = dx / distance * curveAmount

        return CGPoint(x: midX + perpX, y: midY + perpY)
    }

    /// Determine if two peers are in the same ring
    static func areInSameRing(peer1: String, peer2: String, ringAssignments: [Int: [String]]) -> Bool {
        for (_, peers) in ringAssignments {
            if peers.contains(peer1) && peers.contains(peer2) {
                return true
            }
        }
        return false
    }

    /// Get ring number for a peer
    static func getRingNumber(for peerKey: String, ringAssignments: [Int: [String]]) -> Int? {
        for (ring, peers) in ringAssignments where peers.contains(peerKey) {
            return ring
        }
        return nil
    }
}
