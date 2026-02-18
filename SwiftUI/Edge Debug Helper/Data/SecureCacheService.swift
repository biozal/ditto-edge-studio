import Foundation

/// Service for managing non-sensitive app data in JSON files
///
/// **Directory Structure:**
/// - Base: ~/Library/Containers/Edge Debug Helper/Data/Library/Application Support/ditto_cache/
/// - Test: ~/Library/Containers/Edge Debug Helper/Data/Library/Application Support/ditto_cache_test/
///
/// **Files:**
/// - database_configs.json - All database metadata
/// - {databaseId}_history.json - Per-database query history
/// - {databaseId}_favorites.json - Per-database favorites
/// - {databaseId}_observers.json - Per-database observers
///
/// **Design:**
/// - Per-database isolation (history/favorites don't leak between databases)
/// - Write-through caching (immediate disk persistence)
/// - Sandboxed storage (uses app container)
///
/// **Performance:**
/// - JSON encode/decode: < 5ms for typical data
/// - File write (atomic): < 10ms
actor SecureCacheService {
    static let shared = SecureCacheService()

    /// cacheDirectory is nonisolated because it's immutable after init
    private nonisolated let cacheDirectory: URL

    private init() {
        let fileManager = FileManager.default
        // Determine if running in UI test mode
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING")
        let directoryName = isUITesting ? "ditto_cache_test" : "ditto_cache"

        // Get sandboxed application support directory
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDirURL = baseURL.appendingPathComponent(directoryName)
        cacheDirectory = cacheDirURL

        Log.info("📁 SecureCacheService initializing with directory: \(cacheDirURL.path)")

        // If in test mode, clean up any previous test data
        if isUITesting && fileManager.fileExists(atPath: cacheDirURL.path) {
            try? fileManager.removeItem(at: cacheDirURL)
            Log.info("🧪 Cleaned up previous test cache directory")
        }

        // Create cache directory with proper error handling
        do {
            if !fileManager.fileExists(atPath: cacheDirURL.path) {
                try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true, attributes: nil)
                Log.info("✅ Created cache directory: \(cacheDirURL.path)")
            } else {
                Log.info("✅ Cache directory already exists: \(cacheDirURL.path)")
            }
        } catch {
            // Fatal error - app cannot function without cache directory
            fatalError("Failed to create cache directory at \(cacheDirURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Data Models

    /// Metadata for database configuration (non-sensitive fields only)
    struct DatabaseConfigMetadata: Codable {
        let _id: String
        let name: String
        let databaseId: String
        let mode: String
        let allowUntrustedCerts: Bool
        let isBluetoothLeEnabled: Bool
        let isLanEnabled: Bool
        let isAwdlEnabled: Bool
        let isCloudSyncEnabled: Bool
    }

    /// Query history (matches DittoQueryHistory model structure)
    struct QueryHistoryItem: Codable {
        let _id: String
        let query: String
        let createdDate: String

        enum CodingKeys: String, CodingKey {
            case _id
            case query
            case createdDate
        }
    }

    /// Observable metadata (persistable fields from DittoObservable)
    struct ObservableMetadata: Codable {
        let _id: String
        let name: String
        let query: String
        let args: String?
        let isActive: Bool
        let lastUpdated: String?

        enum CodingKeys: String, CodingKey {
            case _id
            case name
            case query
            case args
            case isActive
            case lastUpdated
        }
    }

    /// Subscription metadata (persistable fields from DittoSubscription)
    struct SubscriptionMetadata: Codable {
        let _id: String
        let name: String
        let query: String
        let args: String?

        enum CodingKeys: String, CodingKey {
            case _id
            case name
            case query
            case args
        }
    }

    // MARK: - Database Configs

    /// Saves database configuration metadata to cache
    /// - Parameter config: Configuration metadata to save
    /// - Throws: CacheError if save fails
    func saveDatabaseConfig(_ config: DatabaseConfigMetadata) throws {
        var configs = try loadDatabaseConfigs()

        // Remove existing config with same ID
        configs.removeAll { $0._id == config._id }

        // Add new config
        configs.append(config)

        // Write to file
        let fileURL = cacheDirectory.appendingPathComponent("database_configs.json")
        try writeJSON(configs, to: fileURL)
    }

    /// Loads all database configuration metadata from cache
    /// - Returns: Array of database configurations
    /// - Throws: CacheError if load fails
    func loadDatabaseConfigs() throws -> [DatabaseConfigMetadata] {
        let fileURL = cacheDirectory.appendingPathComponent("database_configs.json")

        // If file doesn't exist, return empty array
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try readJSON([DatabaseConfigMetadata].self, from: fileURL)
    }

    /// Deletes database configuration metadata from cache
    /// - Parameter id: Database ID to delete
    /// - Throws: CacheError if delete fails
    func deleteDatabaseConfig(_ id: String) throws {
        var configs = try loadDatabaseConfigs()
        configs.removeAll { $0._id == id }

        let fileURL = cacheDirectory.appendingPathComponent("database_configs.json")
        try writeJSON(configs, to: fileURL)
    }

    // MARK: - Query History

    /// Saves query history for a specific database
    /// - Parameters:
    ///   - databaseId: Database identifier
    ///   - history: Array of query history items
    /// - Throws: CacheError if save fails
    func saveDatabaseHistory(_ databaseId: String, history: [QueryHistoryItem]) throws {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_history.json")
        try writeJSON(history, to: fileURL)
    }

    /// Loads query history for a specific database
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of query history items
    /// - Throws: CacheError if load fails
    func loadDatabaseHistory(_ databaseId: String) throws -> [QueryHistoryItem] {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_history.json")

        // If file doesn't exist, return empty array
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try readJSON([QueryHistoryItem].self, from: fileURL)
    }

    // MARK: - Favorites

    /// Saves favorite queries for a specific database
    /// - Parameters:
    ///   - databaseId: Database identifier
    ///   - favorites: Array of favorite queries
    /// - Throws: CacheError if save fails
    func saveDatabaseFavorites(_ databaseId: String, favorites: [QueryHistoryItem]) throws {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_favorites.json")
        try writeJSON(favorites, to: fileURL)
    }

    /// Loads favorite queries for a specific database
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of favorite queries
    /// - Throws: CacheError if load fails
    func loadDatabaseFavorites(_ databaseId: String) throws -> [QueryHistoryItem] {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_favorites.json")

        // If file doesn't exist, return empty array
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try readJSON([QueryHistoryItem].self, from: fileURL)
    }

    // MARK: - Observers

    /// Saves observer metadata for a specific database
    /// - Parameters:
    ///   - databaseId: Database identifier
    ///   - observers: Array of observer metadata
    /// - Throws: CacheError if save fails
    func saveDatabaseObservers(_ databaseId: String, observers: [ObservableMetadata]) throws {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_observers.json")
        try writeJSON(observers, to: fileURL)
    }

    /// Loads observer metadata for a specific database
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of observer metadata
    /// - Throws: CacheError if load fails
    func loadDatabaseObservers(_ databaseId: String) throws -> [ObservableMetadata] {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_observers.json")

        // If file doesn't exist, return empty array
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try readJSON([ObservableMetadata].self, from: fileURL)
    }

    // MARK: - Subscriptions

    /// Saves subscription metadata for a specific database
    /// - Parameters:
    ///   - databaseId: Database identifier
    ///   - subscriptions: Array of subscription metadata
    /// - Throws: CacheError if save fails
    func saveDatabaseSubscriptions(_ databaseId: String, subscriptions: [SubscriptionMetadata]) throws {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_subscriptions.json")
        try writeJSON(subscriptions, to: fileURL)
    }

    /// Loads subscription metadata for a specific database
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of subscription metadata
    /// - Throws: CacheError if load fails
    func loadDatabaseSubscriptions(_ databaseId: String) throws -> [SubscriptionMetadata] {
        let fileURL = cacheDirectory.appendingPathComponent("\(databaseId)_subscriptions.json")

        // If file doesn't exist, return empty array
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try readJSON([SubscriptionMetadata].self, from: fileURL)
    }

    // MARK: - Cleanup

    /// Deletes all data for a specific database (history, favorites, observers, subscriptions)
    /// - Parameter databaseId: Database identifier
    /// - Throws: CacheError if cleanup fails
    func deleteDatabaseData(_ databaseId: String) throws {
        let files = [
            "\(databaseId)_history.json",
            "\(databaseId)_favorites.json",
            "\(databaseId)_observers.json",
            "\(databaseId)_subscriptions.json"
        ]

        for file in files {
            let fileURL = cacheDirectory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Helper Methods

    /// Ensures cache directory exists before write operations
    /// - Throws: CacheError if directory creation fails
    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                Log.info("✅ Created cache directory on demand: \(cacheDirectory.path)")
            } catch {
                throw CacheError.directoryCreationFailed(error: error)
            }
        }
    }

    /// Writes JSON data to file atomically
    private func writeJSON(_ data: some Encodable, to url: URL) throws {
        // Ensure directory exists before writing
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: url, options: .atomic)
        } catch {
            throw CacheError.writeFailed(url: url.lastPathComponent, error: error)
        }
    }

    /// Reads JSON data from file
    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            throw CacheError.readFailed(url: url.lastPathComponent, error: error)
        }
    }
}

// MARK: - Error Types

enum CacheError: Error, LocalizedError {
    case writeFailed(url: String, error: Error)
    case readFailed(url: String, error: Error)
    case directoryCreationFailed(error: Error)

    var errorDescription: String? {
        switch self {
        case let .writeFailed(url, error):
            return "Failed to write to cache file '\(url)': \(error.localizedDescription)"
        case let .readFailed(url, error):
            return "Failed to read cache file '\(url)': \(error.localizedDescription)"
        case let .directoryCreationFailed(error):
            return "Failed to create cache directory: \(error.localizedDescription)"
        }
    }
}
