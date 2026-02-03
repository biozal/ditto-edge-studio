import Foundation

struct SmallPeerInfo: Codable, Identifiable {
    let _id: String
    let device_name: String?
    let ditto_sdk_language: String?
    let ditto_sdk_platform: String?
    let ditto_sdk_version: String?
    let local_subscriptions: LocalSubscriptions?

    var id: String { _id }

    var displayName: String {
        device_name ?? id
    }

    var deviceInfo: String {
        let platform = ditto_sdk_platform ?? "Unknown"
        let version = ditto_sdk_version ?? ""
        return "\(platform) \(version)".trimmingCharacters(in: .whitespaces)
    }
}

struct LocalSubscriptions: Codable {
    let queries: [QueryInfo]?
}

struct QueryInfo: Codable {
    let query: String

    // Extract collection name from query string
    // e.g., "SELECT * FROM comments" -> "comments"
    // e.g., "SELECT * FROM COLLECTION __presence WHERE..." -> "__presence"
    var collectionName: String? {
        let components = query.components(separatedBy: " ")

        // Look for "FROM" keyword and get the next token
        if let fromIndex = components.firstIndex(where: { $0.uppercased() == "FROM" }) {
            let nextIndex = fromIndex + 1

            // Handle "FROM COLLECTION name" pattern
            if nextIndex < components.count {
                let nextWord = components[nextIndex]
                if nextWord.uppercased() == "COLLECTION" {
                    // Collection name is after "COLLECTION"
                    let collectionIndex = nextIndex + 1
                    if collectionIndex < components.count {
                        return components[collectionIndex]
                    }
                } else {
                    // Collection name is directly after "FROM"
                    return nextWord
                }
            }
        }

        return nil
    }

    var isSystemCollection: Bool {
        collectionName?.hasPrefix("__") ?? false
    }
}

struct ImportableSubscription: Identifiable {
    let id = UUID()
    let deviceName: String
    let deviceInfo: String
    let collectionName: String
    let query: String
    var isSelected: Bool = false
}
