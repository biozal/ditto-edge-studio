//
//  PresenceProtocols.swift
//  Edge Debug Helper
//
//  Created by Claude on 2026-02-10.
//  Phase 8: Test Mode - Protocol Abstraction for Testing
//

import Foundation
import DittoSwift

/// Protocol abstraction for peer data to allow both real DittoPeer and mock test data
protocol PeerProtocol {
    var peerKeyString: String { get }
    var deviceName: String { get }
    var connectionProtocols: [any ConnectionProtocol] { get }
    var isConnectedToDittoCloud: Bool { get }
}

/// Protocol abstraction for connection data
protocol ConnectionProtocol {
    var type: DittoConnectionType { get }
    var id: String { get }
    var peerKeyString1: String { get }
    var peerKeyString2: String { get }
    var approximateDistanceInMeters: Double? { get }
}

// MARK: - DittoPeer Conformance

/// Extend DittoPeer to conform to PeerProtocol
extension DittoPeer: PeerProtocol {
    // Bridge connections array to protocol type
    var connectionProtocols: [any ConnectionProtocol] {
        return self.connections.map { $0 as ConnectionProtocol }
    }
}

/// Extend DittoConnection to conform to ConnectionProtocol
extension DittoConnection: ConnectionProtocol {
    // Already has required properties: type, id
}

// MARK: - Mock Implementations for Testing

/// Mock peer for testing (conforms to PeerProtocol)
struct MockPeer: PeerProtocol {
    let peerKeyString: String
    let deviceName: String
    let connectionProtocols: [any ConnectionProtocol]
    let isConnectedToDittoCloud: Bool
    
    init(
        peerKey: String,
        deviceName: String,
        connections: [MockConnection],
        isConnectedToDittoCloud: Bool = false
    ) {
        self.peerKeyString = peerKey
        self.deviceName = deviceName
        self.connectionProtocols = connections.map { $0 as ConnectionProtocol }
        self.isConnectedToDittoCloud = isConnectedToDittoCloud
    }
}

/// Mock connection for testing (conforms to ConnectionProtocol)
struct MockConnection: ConnectionProtocol {
    let type: DittoConnectionType
    let id: String
    let peerKeyString1: String
    let peerKeyString2: String
    let approximateDistanceInMeters: Double?
    
    init(
        type: DittoConnectionType,
        id: String,
        peerKeyString1: String = "",
        peerKeyString2: String = "",
        approximateDistanceInMeters: Double? = nil
    ) {
        self.type = type
        self.id = id
        self.peerKeyString1 = peerKeyString1
        self.peerKeyString2 = peerKeyString2
        self.approximateDistanceInMeters = approximateDistanceInMeters
    }
}
