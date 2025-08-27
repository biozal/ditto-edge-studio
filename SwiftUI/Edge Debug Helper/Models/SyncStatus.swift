import Foundation

struct SyncStatusInfo: Identifiable, Equatable {
    let id: String
    let isDittoServer: Bool
    let syncSessionStatus: String
    let syncedUpToLocalCommitId: Int?
    let lastUpdateReceivedTime: TimeInterval?
    
    init(from dictionary: [String: Any]) {
        self.id = dictionary["_id"] as? String ?? UUID().uuidString
        self.isDittoServer = dictionary["is_ditto_server"] as? Bool ?? false
        
        if let documents = dictionary["documents"] as? [String: Any] {
            self.syncSessionStatus = documents["sync_session_status"] as? String ?? "Unknown"
            self.syncedUpToLocalCommitId = documents["synced_up_to_local_commit_id"] as? Int
            self.lastUpdateReceivedTime = documents["last_update_received_time"] as? TimeInterval
        } else {
            self.syncSessionStatus = "Unknown"
            self.syncedUpToLocalCommitId = nil
            self.lastUpdateReceivedTime = nil
        }
    }
    
    init?(_ data: Data) {
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.init(from: jsonObject)
            } else {
                return nil
            }
        } catch {
            print("SyncStatusInfo DECODING ERROR:", error.localizedDescription)
            print("📊 Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
            return nil
        }
    }

    static func == (lhs: SyncStatusInfo, rhs: SyncStatusInfo) -> Bool {
        // Compare the properties that define equality
        return lhs.id == rhs.id &&
        lhs.peerType == rhs.peerType &&
        // Include other properties that define equality
        lhs.syncSessionStatus == rhs.syncSessionStatus &&
        lhs.syncedUpToLocalCommitId == rhs.syncedUpToLocalCommitId
    }

    var formattedLastUpdate: String {
        guard let lastUpdateReceivedTime = lastUpdateReceivedTime else {
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
        return isDittoServer ? "Cloud Server" : "Peer Device"
    }
}
