import Foundation

/// Loads DittoAppConfig from various sources and handles legacy formats
enum DittoAppConfigLoader {

    /// Converts mode string values to AuthMode enum, supporting legacy formats
    static func parseMode(from string: String) -> AuthMode? {
        switch string.lowercased() {
        // Current format - direct mappings
        case "onlineplayground":
            return .onlinePlayground
        case "offlineplayground":
            return .offlinePlayground
        case "sharedkey":
            return .sharedKey

        // Legacy format mappings
        case "online":
            return .onlinePlayground
        case "offline":
            return .offlinePlayground

        default:
            return nil
        }
    }

    /// Prepares a JSON dictionary for decoding by handling legacy formats
    static func prepare(_ dictionary: inout [String: Any]) {
        // Handle mode field if it's a string
        if let modeString = dictionary["mode"] as? String {
            if let authMode = parseMode(from: modeString) {
                // Convert to the raw value that AuthMode expects
                dictionary["mode"] = authMode.rawValue
            }
        }

        // Add any other legacy field handling here in the future
    }

    /// Loads DittoAppConfig from Data, handling both current and legacy formats
    static func loadConfig(from data: Data) throws -> DittoAppConfig {
        // First try to decode directly (for current format)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(DittoAppConfig.self, from: data)
        } catch {
            // If direct decoding fails, try handling legacy format
            guard var jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw error
            }

            // Prepare the dictionary for decoding
            prepare(&jsonObject)

            // Convert back to Data and decode
            let preparedData = try JSONSerialization.data(withJSONObject: jsonObject)
            let decoder = JSONDecoder()
            return try decoder.decode(DittoAppConfig.self, from: preparedData)
        }
    }
}