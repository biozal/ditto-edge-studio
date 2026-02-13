//
//  MockPresenceDataGenerator.swift
//  Edge Debug Helper
//
//  Created by Claude on 2026-02-10.
//  Phase 8: Test Mode - Mock Data Generator for Testing
//

import Foundation
import DittoSwift

/// Generates mock presence data for testing with 30 peers and varied connection types
class MockPresenceDataGenerator {
    
    // MARK: - Properties
    
    private var mockPeers: [MockPeer] = []
    private let localPeerKey = "local-test-peer"
    private var peerCounter = 0
    
    // Realistic device names for variety
    private let deviceNames: [String] = [
        "iPhone 17 Pro Max",
        "iPhone 17 Pro",
        "iPhone 16 Pro Max",
        "iPhone 16",
        "iPad Pro 12.9\"",
        "iPad mini (A17 Pro)",
        "iPad Air",
        "MacBook Pro 16\" M3 Max",
        "MacBook Air M2",
        "iMac 24\" M3",
        "Mac Studio M2 Ultra",
        "Mac mini M3",
        "Windows Desktop",
        "Surface Pro 9",
        "Galaxy S24 Ultra",
        "Pixel 8 Pro",
        "OnePlus 12",
        "Linux Server",
        "Raspberry Pi 5",
        "Android Tablet"
    ]
    
    // MARK: - Initialization
    
    init() {
        // Generate initial 30 peers
        mockPeers = generateInitialPeers(count: 30)
    }
    
    // MARK: - Public API
    
    /// Generate a presence graph update with local peer and remote peers
    func generateUpdate() -> (localPeer: PeerProtocol, remotePeers: [PeerProtocol]) {
        // Simulate occasional peer changes (10% chance)
        if Double.random(in: 0...1) < 0.1 {
            simulateChange()
        }
        
        // Create local peer
        let localPeer = createLocalPeer()
        
        // Return mock peers as remote peers
        return (localPeer: localPeer, remotePeers: mockPeers)
    }
    
    // MARK: - Private Methods
    
    /// Generate initial set of mock peers
    private func generateInitialPeers(count: Int) -> [MockPeer] {
        var peers: [MockPeer] = []
        
        for i in 0..<count {
            let deviceName = deviceNames[i % deviceNames.count]
            let suffix = i / deviceNames.count > 0 ? " (\(i / deviceNames.count + 1))" : ""
            let fullDeviceName = deviceName + suffix
            
            // Distribution:
            // - 50% single connection
            // - 50% dual connection
            // Note: Only local peer connects to cloud (more realistic)
            let random = Double.random(in: 0...1)
            let connectionCount: Int
            
            if random < 0.5 {
                // Single connection
                connectionCount = 1
            } else {
                // Dual connection
                connectionCount = 2
            }
            
            // Generate connections
            var connections: [MockConnection] = []
            let connectionTypes: [DittoConnectionType] = [.bluetooth, .accessPoint, .p2pWiFi, .webSocket]
            
            for j in 0..<connectionCount {
                let randomType = connectionTypes[Int.random(in: 0..<connectionTypes.count)]
                connections.append(MockConnection(
                    type: randomType,
                    id: "conn-\(peerCounter)-\(j)"
                ))
            }
            
            peers.append(MockPeer(
                peerKey: "mock-peer-\(peerCounter)",
                deviceName: fullDeviceName,
                connections: connections,
                isConnectedToDittoCloud: false  // Only local peer connects to cloud
            ))
            
            peerCounter += 1
        }
        
        return peers
    }
    
    /// Create mock local peer
    private func createLocalPeer() -> PeerProtocol {
        // Local peer with multiple connection types
        let connections: [MockConnection] = [
            MockConnection(type: .bluetooth, id: "local-bt"),
            MockConnection(type: .accessPoint, id: "local-lan"),
            MockConnection(type: .webSocket, id: "local-ws")
        ]
        
        return MockPeer(
            peerKey: localPeerKey,
            deviceName: "My Test Device",
            connections: connections,
            isConnectedToDittoCloud: true  // Only local peer connects to cloud (realistic behavior)
        )
    }
    
    /// Simulate peer changes (add/remove peers)
    private func simulateChange() {
        // Remove 1-2 random peers (keep minimum of 20)
        let removeCount = Int.random(in: 1...2)
        for _ in 0..<removeCount where mockPeers.count > 20 {
            let index = Int.random(in: 0..<mockPeers.count)
            mockPeers.remove(at: index)
        }
        
        // Add 1-3 new peers (keep maximum of 35)
        let addCount = Int.random(in: 1...3)
        if mockPeers.count + addCount <= 35 {
            let newPeers = generateInitialPeers(count: addCount)
            mockPeers.append(contentsOf: newPeers)
        }
        
        print("📊 Mock data change: \(mockPeers.count) peers")
    }
}
