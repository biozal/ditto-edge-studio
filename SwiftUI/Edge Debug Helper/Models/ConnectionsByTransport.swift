import Foundation
import SwiftUI

/// Represents the count of connections by transport type from Ditto's presence graph and sync status
struct ConnectionsByTransport: Codable, Equatable {
    let accessPoint: Int
    let bluetooth: Int
    let dittoServer: Int
    let p2pWiFi: Int
    let webSocket: Int

    enum CodingKeys: String, CodingKey {
        case accessPoint = "AccessPoint"
        case bluetooth = "Bluetooth"
        case dittoServer = "DittoServer"
        case p2pWiFi = "P2PWiFi"
        case webSocket = "WebSocket"
    }

    // MARK: - Initializers

    /// Default initializer with all zeros
    init(accessPoint: Int = 0, bluetooth: Int = 0, dittoServer: Int = 0, p2pWiFi: Int = 0, webSocket: Int = 0) {
        self.accessPoint = accessPoint
        self.bluetooth = bluetooth
        self.dittoServer = dittoServer
        self.p2pWiFi = p2pWiFi
        self.webSocket = webSocket
    }

    /// Convenience initializer from dictionary (parses {"connections_by_transport": {...}})
    init(from dictionary: [String: Any]) {
        if let connectionsDict = dictionary["connections_by_transport"] as? [String: Any] {
            accessPoint = connectionsDict["AccessPoint"] as? Int ?? 0
            bluetooth = connectionsDict["Bluetooth"] as? Int ?? 0
            dittoServer = connectionsDict["DittoServer"] as? Int ?? 0
            p2pWiFi = connectionsDict["P2PWiFi"] as? Int ?? 0
            webSocket = connectionsDict["WebSocket"] as? Int ?? 0
        } else {
            accessPoint = 0
            bluetooth = 0
            dittoServer = 0
            p2pWiFi = 0
            webSocket = 0
        }
    }

    // MARK: - Computed Properties

    /// Total number of connections across all transports
    var totalConnections: Int {
        accessPoint + bluetooth + dittoServer + p2pWiFi + webSocket
    }

    /// True if there are any active connections
    var hasActiveConnections: Bool {
        totalConnections > 0
    }

    /// Information about an active transport with display metadata
    struct TransportInfo {
        let name: String
        let count: Int
        let icon: FontAwesomeIcon
        let color: Color
    }

    /// Array of active (non-zero) transports with display metadata
    /// Uses Ditto Rainbow colors: WebSocket (Purple), Bluetooth (Blue), P2P WiFi (Pink), LAN/Access Point (Green), Ditto Server (Purple)
    var activeTransports: [TransportInfo] {
        var transports: [TransportInfo] = []

        if webSocket > 0 {
            transports.append(TransportInfo(name: "WebSocket", count: webSocket, icon: ConnectivityIcon.network, color: .purple))
        }
        if bluetooth > 0 {
            transports.append(TransportInfo(name: "Bluetooth", count: bluetooth, icon: ConnectivityIcon.bluetooth, color: .blue))
        }
        if p2pWiFi > 0 {
            transports.append(TransportInfo(name: "P2P WiFi", count: p2pWiFi, icon: ConnectivityIcon.wifi, color: .pink))
        }
        if accessPoint > 0 {
            transports.append(TransportInfo(name: "Access Point", count: accessPoint, icon: ConnectivityIcon.broadcastTower, color: .green))
        }
        if dittoServer > 0 {
            transports.append(TransportInfo(name: "Ditto Server", count: dittoServer, icon: ConnectivityIcon.cloud, color: .purple))
        }

        return transports
    }

    // MARK: - Static Properties

    /// Empty state with all zeros
    static let empty = ConnectionsByTransport()
}
