import DittoSwift
import Foundation

/// Protocol abstraction for peer data to allow both real DittoPeer and mock test data
protocol PeerProtocol {
    var peerKeyString: String { get }
    var deviceName: String { get }
    var connectionProtocols: [any ConnectionProtocol] { get }
    var isConnectedToDittoCloud: Bool { get }
}

/// Protocol abstraction for connection data
/// Note: approximateDistanceInMeters was removed in Ditto SDK v5.
protocol ConnectionProtocol {
    var type: DittoConnectionType { get }
    var id: String { get }
    var peerKeyString1: String { get }
    var peerKeyString2: String { get }
}

// MARK: - DittoPeer Conformance

/// Extend DittoPeer to conform to PeerProtocol.
/// In v5, DittoPeer uses `peerKey` (was `peerKeyString`) and
/// `isConnectedToDittoServer` (was `isConnectedToDittoCloud`).
/// We bridge those renames here so all callsites use the stable protocol names.
extension DittoPeer: PeerProtocol {
    /// Bridge v5 `peerKey` to the stable protocol name `peerKeyString`.
    var peerKeyString: String {
        peerKey
    }

    /// Bridge v5 `isConnectedToDittoServer` to the legacy protocol name `isConnectedToDittoCloud`.
    var isConnectedToDittoCloud: Bool {
        isConnectedToDittoServer
    }

    var connectionProtocols: [any ConnectionProtocol] {
        connections.map { $0 as ConnectionProtocol }
    }
}

/// Extend DittoConnection to conform to ConnectionProtocol.
/// In v5, DittoConnection uses `peer1`/`peer2` (were `peerKeyString1`/`peerKeyString2`).
/// We bridge those renames here so all callsites use the stable protocol names.
extension DittoConnection: ConnectionProtocol {
    /// Bridge v5 `peer1` to the stable protocol name `peerKeyString1`.
    var peerKeyString1: String {
        peer1
    }

    /// Bridge v5 `peer2` to the stable protocol name `peerKeyString2`.
    var peerKeyString2: String {
        peer2
    }
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
        peerKeyString = peerKey
        self.deviceName = deviceName
        connectionProtocols = connections.map { $0 as ConnectionProtocol }
        self.isConnectedToDittoCloud = isConnectedToDittoCloud
    }
}

/// Mock connection for testing (conforms to ConnectionProtocol)
/// Note: approximateDistanceInMeters was removed from DittoConnection in Ditto SDK v5.
struct MockConnection: ConnectionProtocol {
    let type: DittoConnectionType
    let id: String
    let peerKeyString1: String
    let peerKeyString2: String

    init(
        type: DittoConnectionType,
        id: String,
        peerKeyString1: String = "",
        peerKeyString2: String = ""
    ) {
        self.type = type
        self.id = id
        self.peerKeyString1 = peerKeyString1
        self.peerKeyString2 = peerKeyString2
    }
}
