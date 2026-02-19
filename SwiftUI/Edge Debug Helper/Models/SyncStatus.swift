import Foundation
import SwiftUI

/// Custom enum for peer operating system information
enum PeerOS: Equatable, Codable {
    case iOS(version: String?)
    case android(version: String?)
    case macOS(version: String?)
    case linux(version: String?)
    case windows(version: String?)
    case unknown(name: String?)

    var displayName: String {
        switch self {
        case let .iOS(version):
            return version.map { "iOS \($0)" } ?? "iOS"
        case let .android(version):
            return version.map { "Android \($0)" } ?? "Android"
        case let .macOS(version):
            return version.map { "macOS \($0)" } ?? "macOS"
        case let .linux(version):
            return version.map { "Linux \($0)" } ?? "Linux"
        case let .windows(version):
            return version.map { "Windows \($0)" } ?? "Windows"
        case let .unknown(name):
            return name ?? "Unknown OS"
        }
    }
}

/// Custom enum for connection types
enum ConnectionType: Equatable, Codable {
    case bluetooth
    case accessPoint
    case p2pWiFi
    case webSocket
    case unknown(String)

    var displayName: String {
        switch self {
        case .bluetooth:
            return "Bluetooth"
        case .accessPoint:
            return "WiFi AP"
        case .p2pWiFi:
            return "P2P WiFi"
        case .webSocket:
            return "WebSocket"
        case let .unknown(name):
            return name
        }
    }

    var icon: FAIcon {
        switch self {
        case .bluetooth:
            return ConnectivityIcon.bluetooth
        case .accessPoint:
            return ConnectivityIcon.broadcastTower
        case .p2pWiFi:
            return ConnectivityIcon.wifi
        case .webSocket:
            return ConnectivityIcon.network
        case .unknown:
            return SystemIcon.question
        }
    }

    var cardColor: Color {
        switch self {
        case .bluetooth: return Color(red: 0.0, green: 0.40, blue: 0.85)
        case .accessPoint: return Color(red: 0.05, green: 0.52, blue: 0.25)
        case .p2pWiFi: return Color(red: 0.78, green: 0.10, blue: 0.22)
        case .webSocket: return Color(red: 0.85, green: 0.48, blue: 0.00)
        case .unknown: return Color(red: 0.35, green: 0.35, blue: 0.40)
        }
    }

    var cardDarkColor: Color {
        switch self {
        case .bluetooth: return Color(red: 0.0, green: 0.20, blue: 0.60)
        case .accessPoint: return Color(red: 0.02, green: 0.32, blue: 0.14)
        case .p2pWiFi: return Color(red: 0.50, green: 0.04, blue: 0.12)
        case .webSocket: return Color(red: 0.60, green: 0.30, blue: 0.00)
        case .unknown: return Color(red: 0.20, green: 0.20, blue: 0.25)
        }
    }
}

/// Custom struct for peer address information
struct PeerAddressInfo: Equatable, Codable {
    let connectionType: String // e.g., "WiFi", "Bluetooth", "WebSocket"
    let description: String // Human-readable address

    var displayText: String {
        "\(connectionType): \(description)"
    }
}

/// Custom struct for connection information
struct ConnectionInfo: Identifiable, Equatable, Codable {
    let id: String
    let type: ConnectionType
    let peerKeyString1: String
    let peerKeyString2: String
    let approximateDistanceInMeters: Double?

    var displayDistance: String? {
        guard let distance = approximateDistanceInMeters else { return nil }

        if distance < 1.0 {
            return String(format: "%.0f cm", distance * 100)
        } else if distance < 1000.0 {
            return String(format: "%.1f m", distance)
        } else {
            return String(format: "%.2f km", distance / 1000.0)
        }
    }

    var otherPeerKey: String {
        // Return the peer key that isn't the local peer
        // This will be determined when displaying
        peerKeyString2
    }
}

/// Helper struct for passing peer enrichment data
struct PeerEnrichmentData {
    let deviceName: String?
    let osInfo: PeerOS?
    let dittoSDKVersion: String?
    let addressInfo: PeerAddressInfo?
    let identityMetadata: String?
    let connections: [ConnectionInfo]?
}

struct SyncStatusInfo: Identifiable, Equatable {
    let id: String
    let isDittoServer: Bool
    let syncSessionStatus: String
    let syncedUpToLocalCommitId: Int?
    let lastUpdateReceivedTime: TimeInterval?

    // Peer enrichment fields
    let deviceName: String?
    let osInfo: PeerOS?
    let dittoSDKVersion: String?
    let addressInfo: PeerAddressInfo?
    let identityMetadata: String?
    let connections: [ConnectionInfo]?

    init(from dictionary: [String: Any], peerEnrichment: PeerEnrichmentData? = nil) {
        id = dictionary["_id"] as? String ?? UUID().uuidString
        isDittoServer = dictionary["is_ditto_server"] as? Bool ?? false

        if let documents = dictionary["documents"] as? [String: Any] {
            syncSessionStatus = documents["sync_session_status"] as? String ?? "Unknown"
            syncedUpToLocalCommitId = documents["synced_up_to_local_commit_id"] as? Int
            lastUpdateReceivedTime = documents["last_update_received_time"] as? TimeInterval
        } else {
            syncSessionStatus = "Unknown"
            syncedUpToLocalCommitId = nil
            lastUpdateReceivedTime = nil
        }

        // Peer enrichment fields
        deviceName = peerEnrichment?.deviceName
        osInfo = peerEnrichment?.osInfo
        dittoSDKVersion = peerEnrichment?.dittoSDKVersion
        addressInfo = peerEnrichment?.addressInfo
        identityMetadata = peerEnrichment?.identityMetadata
        connections = peerEnrichment?.connections
    }

    init?(_ data: Data) {
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.init(from: jsonObject)
            } else {
                assertionFailure("SyncStatusInfo: Failed to cast JSON object to [String: Any]")
                return nil
            }
        } catch {
            assertionFailure("SyncStatusInfo decoding error: \(error.localizedDescription)")
            return nil
        }
    }

    static func == (lhs: SyncStatusInfo, rhs: SyncStatusInfo) -> Bool {
        // Compare the properties that define equality
        lhs.id == rhs.id &&
            lhs.peerType == rhs.peerType &&
            lhs.syncSessionStatus == rhs.syncSessionStatus &&
            lhs.syncedUpToLocalCommitId == rhs.syncedUpToLocalCommitId &&
            lhs.deviceName == rhs.deviceName &&
            lhs.osInfo == rhs.osInfo &&
            lhs.dittoSDKVersion == rhs.dittoSDKVersion
        // Note: addressInfo and identityMetadata intentionally excluded
    }

    var formattedLastUpdate: String {
        guard let lastUpdateReceivedTime else {
            return "Never"
        }

        let date = Date(timeIntervalSince1970: lastUpdateReceivedTime / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true

        return formatter.string(from: date)
    }

    var statusColor: String {
        switch syncSessionStatus {
        case "Connected":
            return "green"
        case "Connecting":
            return "orange"
        case "Disconnected":
            return "red"
        default:
            return "gray"
        }
    }

    var peerType: String {
        isDittoServer ? "Cloud Server" : "Peer Device"
    }
}

extension SyncStatusInfo {
    static let cloudCardColor = Color(red: 0.45, green: 0.15, blue: 0.72)
    static let cloudCardDarkColor = Color(red: 0.28, green: 0.07, blue: 0.48)
}
