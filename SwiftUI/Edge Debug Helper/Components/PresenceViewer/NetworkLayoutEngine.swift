//
//  NetworkLayoutEngine.swift
//  Edge Debug Helper
//
//  Created by Claude on 2026-02-10.
//  Phase 3: Layout Algorithm - BFS Ring Assignment
//

import Foundation
import CoreGraphics

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

    private let baseRadius: CGFloat = 123.75  // Ring 1 radius (220 * 0.75 * 0.75)
    private let radiusIncrement: CGFloat = 101.25  // Additional radius per ring (180 * 0.75 * 0.75)
    private let minAngularSeparation: CGFloat = 15.0 * .pi / 180.0  // 15° in radians
    
    // MARK: - Public Methods
    
    /// Calculate layout positions for all peers using BFS ring assignment
    /// - Parameters:
    ///   - localPeerKey: The local peer's key (center of diagram)
    ///   - allPeers: Dictionary of all peer nodes
    ///   - connections: Array of connection lines
    /// - Returns: Layout result with positions and ring assignments
    func calculateLayout(
        localPeerKey: String,
        allPeers: [String: Any],  // Can't use PeerNode here due to import issues
        connections: [ConnectionInfo]
    ) -> LayoutResult {
        
        // Build adjacency graph from connections
        let adjacencyGraph = buildAdjacencyGraph(connections: connections, localPeer: localPeerKey)
        
        // Perform BFS to assign rings
        let ringAssignments = performBFS(
            localPeer: localPeerKey,
            adjacencyGraph: adjacencyGraph,
            allPeers: Array(allPeers.keys)
        )
        
        // Calculate ring radii (may expand if too many peers)
        let ringRadii = calculateRingRadii(ringAssignments: ringAssignments)
        
        // Calculate positions with angle optimization
        let positions = calculatePositions(
            ringAssignments: ringAssignments,
            ringRadii: ringRadii,
            localPeer: localPeerKey
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
    
    /// Perform breadth-first search to assign peers to rings
    private func performBFS(
        localPeer: String,
        adjacencyGraph: [String: Set<String>],
        allPeers: [String]
    ) -> [Int: [String]] {
        
        var ringAssignments: [Int: [String]] = [:]
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
            
            for neighbor in neighbors {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    let nextRing = currentRing + 1
                    
                    ringAssignments[nextRing, default: []].append(neighbor)
                    queue.append((neighbor, nextRing))
                }
            }
        }
        
        // Handle disconnected peers (assign to outermost ring)
        let connectedPeers = visited
        let disconnectedPeers = Set(allPeers).subtracting(connectedPeers)
        
        if !disconnectedPeers.isEmpty {
            let maxRing = ringAssignments.keys.max() ?? 0
            let disconnectedRing = maxRing + 1
            ringAssignments[disconnectedRing] = Array(disconnectedPeers)
        }
        
        return ringAssignments
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
            let minimumCircumference = CGFloat(peerCount) * (peerDiameter + 20.0)  // 20pt spacing
            let minimumRadius = minimumCircumference / (2.0 * .pi)
            
            // Use the larger of base radius or minimum required radius
            ringRadii[ring] = max(baseRadiusForRing, minimumRadius)
        }
        
        return ringRadii
    }
    
    // MARK: - Private Methods - Position Calculation
    
    /// Calculate final positions with angle optimization
    private func calculatePositions(
        ringAssignments: [Int: [String]],
        ringRadii: [Int: CGFloat],
        localPeer: String
    ) -> [String: CGPoint] {
        
        var positions: [String: CGPoint] = [:]
        
        // Local peer at center
        positions[localPeer] = .zero
        
        // Position peers in each ring
        for ring in ringAssignments.keys.sorted() where ring > 0 {
            guard let peers = ringAssignments[ring],
                  let radius = ringRadii[ring],
                  !peers.isEmpty else {
                continue
            }
            
            // Calculate angles for even distribution
            let angles = calculateOptimalAngles(
                peerCount: peers.count,
                radius: radius
            )
            
            // Assign positions
            for (index, peerKey) in peers.enumerated() {
                let angle = angles[index]
                let x = radius * cos(angle)
                let y = radius * sin(angle)
                positions[peerKey] = CGPoint(x: x, y: y)
            }
        }
        
        return positions
    }
    
    /// Calculate optimal angles for peer distribution
    private func calculateOptimalAngles(peerCount: Int, radius: CGFloat) -> [CGFloat] {
        guard peerCount > 0 else { return [] }
        
        var angles: [CGFloat] = []
        
        // Start at top (90°) for aesthetic appeal
        let startAngle: CGFloat = .pi / 2.0
        let angleStep: CGFloat = (2.0 * .pi) / CGFloat(peerCount)
        
        for i in 0..<peerCount {
            let angle = startAngle + CGFloat(i) * angleStep
            angles.append(angle)
        }
        
        return angles
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
        for (ring, peers) in ringAssignments {
            if peers.contains(peerKey) {
                return ring
            }
        }
        return nil
    }
}
