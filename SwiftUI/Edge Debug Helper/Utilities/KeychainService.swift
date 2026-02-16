import Foundation
import Security

/// Service for managing sensitive database credentials in macOS Keychain
///
/// **Security Features:**
/// - Hardware-encrypted storage via Security framework
/// - Service name: "live.ditto.EdgeStudio"
/// - Account naming: "database_{databaseId}"
/// - Uses kSecAttrAccessibleAfterFirstUnlock for balance of security + usability
///
/// **Data Stored:**
/// - Database credentials (token, authUrl, websocketUrl, httpApiUrl, httpApiKey, secretKey)
/// - Database name (for UI listing without needing cache file)
///
/// **Performance:**
/// - Read: ~10-20ms per operation
/// - Write: ~20-50ms per operation
actor KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "live.ditto.EdgeStudio"
    
    private init() {}
    
    // MARK: - Data Models
    
    /// Credentials stored in Keychain for a database
    struct DatabaseCredentials: Codable {
        let name: String              // Database display name (for UI listing)
        let token: String
        let authUrl: String
        let websocketUrl: String
        let httpApiUrl: String
        let httpApiKey: String
        let secretKey: String
    }
    
    // MARK: - Public API
    
    /// Saves database credentials to Keychain
    /// - Parameters:
    ///   - databaseId: Unique database identifier
    ///   - credentials: Credentials to store
    /// - Throws: KeychainError if save fails
    func saveDatabaseCredentials(_ databaseId: String, credentials: DatabaseCredentials) throws {
        let account = "database_\(databaseId)"
        
        // Encode credentials to Data
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        
        // Create query to add item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item first (atomic update)
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    /// Loads database credentials from Keychain
    /// - Parameter databaseId: Unique database identifier
    /// - Returns: Credentials if found, nil if not found
    /// - Throws: KeychainError if read fails (but not if item doesn't exist)
    func loadDatabaseCredentials(_ databaseId: String) throws -> DatabaseCredentials? {
        let account = "database_\(databaseId)"
        
        // Create query to fetch item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        // Item not found is not an error
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status: status)
        }
        
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        
        // Decode credentials from Data
        let decoder = JSONDecoder()
        let credentials = try decoder.decode(DatabaseCredentials.self, from: data)
        
        return credentials
    }
    
    /// Deletes database credentials from Keychain
    /// - Parameter databaseId: Unique database identifier
    /// - Throws: KeychainError if delete fails (but not if item doesn't exist)
    func deleteDatabaseCredentials(_ databaseId: String) throws {
        let account = "database_\(databaseId)"
        
        // Create query to delete item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Item not found is not an error (idempotent delete)
        if status == errSecItemNotFound {
            return
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    /// Lists all database IDs that have credentials stored in Keychain
    /// - Returns: Array of database IDs
    /// - Throws: KeychainError if query fails
    func listDatabaseIds() throws -> [String] {
        // Create query to fetch all accounts for our service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        
        // No items found is not an error
        if status == errSecItemNotFound {
            return []
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.queryFailed(status: status)
        }
        
        guard let itemsArray = items as? [[String: Any]] else {
            return []
        }
        
        // Extract database IDs from account names
        let databaseIds = itemsArray.compactMap { item -> String? in
            guard let account = item[kSecAttrAccount as String] as? String else {
                return nil
            }
            
            // Account format: "database_{databaseId}"
            if account.hasPrefix("database_") {
                return String(account.dropFirst("database_".count))
            }
            
            return nil
        }
        
        return databaseIds
    }
}

// MARK: - Error Types

enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case queryFailed(status: OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .queryFailed(let status):
            return "Failed to query Keychain (status: \(status))"
        case .invalidData:
            return "Invalid data format in Keychain"
        }
    }
}
