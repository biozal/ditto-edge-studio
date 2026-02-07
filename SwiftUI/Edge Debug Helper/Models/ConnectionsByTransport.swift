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
            self.accessPoint = connectionsDict["AccessPoint"] as? Int ?? 0
            self.bluetooth = connectionsDict["Bluetooth"] as? Int ?? 0
            self.dittoServer = connectionsDict["DittoServer"] as? Int ?? 0
            self.p2pWiFi = connectionsDict["P2PWiFi"] as? Int ?? 0
            self.webSocket = connectionsDict["WebSocket"] as? Int ?? 0
        } else {
            self.accessPoint = 0
            self.bluetooth = 0
            self.dittoServer = 0
            self.p2pWiFi = 0
            self.webSocket = 0
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

    /// Array of active (non-zero) transports with display metadata
    /// Uses Ditto Rainbow colors: WebSocket (Purple), Bluetooth (Blue), P2P WiFi (Pink), LAN/Access Point (Green), Ditto Server (Purple)
    var activeTransports: [(name: String, count: Int, icon: FontAwesomeIcon, color: Color)] {
        var transports: [(String, Int, FontAwesomeIcon, Color)] = []

        if webSocket > 0 {
            transports.append(("WebSocket", webSocket, ConnectivityIcon.network, .purple))
        }
        if bluetooth > 0 {
            transports.append(("Bluetooth", bluetooth, ConnectivityIcon.bluetooth, .blue))
        }
        if p2pWiFi > 0 {
            transports.append(("P2P WiFi", p2pWiFi, ConnectivityIcon.wifi, .pink))
        }
        if accessPoint > 0 {
            transports.append(("Access Point", accessPoint, ConnectivityIcon.broadcastTower, .green))
        }
        if dittoServer > 0 {
            transports.append(("Ditto Server", dittoServer, ConnectivityIcon.cloud, .purple))
        }

        return transports
    }

    // MARK: - Static Properties

    /// Empty state with all zeros
    static let empty = ConnectionsByTransport()
}
