import Foundation
import DittoSwift

/// Repository for managing database configurations with secure storage
///
/// **Storage Strategy:**
/// - Sensitive credentials → macOS Keychain (encrypted)
/// - Non-sensitive metadata → JSON cache files
/// - In-memory cache for fast access during session
///
/// **Performance:**
/// - Load: < 100ms total (Keychain reads + JSON parsing)
/// - Save: < 50ms (write-through to Keychain + cache)
/// - In-memory access: < 1ms
actor DatabaseRepository {
    static let shared = DatabaseRepository()

    private let keychainService = KeychainService.shared
    private let cacheService = SecureCacheService.shared
    private var appState: AppState?

    // In-memory cache for fast access
    private var cachedConfigs: [DittoConfigForDatabase] = []

    // Callback for UI updates
    private var onDittoDatabaseConfigUpdate: (([DittoConfigForDatabase]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads all database configurations from secure storage
    /// - Returns: Array of database configurations
    /// - Throws: Error if load fails
    func loadDatabaseConfigs() async throws -> [DittoConfigForDatabase] {
        // 1. Load metadata from cache
        let metadataList = try await cacheService.loadDatabaseConfigs()

        var configs: [DittoConfigForDatabase] = []

        // 2. For each metadata, load credentials from Keychain
        for metadata in metadataList {
            guard let credentials = try await keychainService.loadDatabaseCredentials(metadata.databaseId) else {
                print("⚠️ No credentials found for database: \(metadata.name)")
                continue
            }

            // 3. Combine metadata + credentials into DittoConfigForDatabase
            let config = DittoConfigForDatabase(
                metadata._id,
                name: credentials.name,  // Name comes from Keychain (source of truth)
                databaseId: metadata.databaseId,
                token: credentials.token,
                authUrl: credentials.authUrl,
                websocketUrl: credentials.websocketUrl,
                httpApiUrl: credentials.httpApiUrl,
                httpApiKey: credentials.httpApiKey,
                mode: AuthMode(rawValue: metadata.mode) ?? .server,
                allowUntrustedCerts: metadata.allowUntrustedCerts,
                secretKey: credentials.secretKey,
                isBluetoothLeEnabled: metadata.isBluetoothLeEnabled,
                isLanEnabled: metadata.isLanEnabled,
                isAwdlEnabled: metadata.isAwdlEnabled,
                isCloudSyncEnabled: metadata.isCloudSyncEnabled
            )
            configs.append(config)
        }

        // 4. Update in-memory cache
        cachedConfigs = configs

        return configs
    }

    /// Adds a new database configuration
    /// - Parameter appConfig: Configuration to add
    /// - Throws: Error if save fails
    func addDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        do {
            // 1. Save credentials to Keychain
            let credentials = KeychainService.DatabaseCredentials(
                name: appConfig.name,
                token: appConfig.token,
                authUrl: appConfig.authUrl,
                websocketUrl: appConfig.websocketUrl,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey
            )
            try await keychainService.saveDatabaseCredentials(appConfig.databaseId, credentials: credentials)

            // 2. Save metadata to cache
            let metadata = SecureCacheService.DatabaseConfigMetadata(
                _id: appConfig._id,
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                mode: appConfig.mode.rawValue,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                isBluetoothLeEnabled: appConfig.isBluetoothLeEnabled,
                isLanEnabled: appConfig.isLanEnabled,
                isAwdlEnabled: appConfig.isAwdlEnabled,
                isCloudSyncEnabled: appConfig.isCloudSyncEnabled
            )
            try await cacheService.saveDatabaseConfig(metadata)

            // 3. Update in-memory cache
            cachedConfigs.append(appConfig)

            // 4. Notify UI
            notifyConfigUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Updates an existing database configuration
    /// - Parameter appConfig: Configuration to update
    /// - Throws: Error if update fails
    func updateDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        do {
            // 1. Update credentials in Keychain
            let credentials = KeychainService.DatabaseCredentials(
                name: appConfig.name,
                token: appConfig.token,
                authUrl: appConfig.authUrl,
                websocketUrl: appConfig.websocketUrl,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey
            )
            try await keychainService.saveDatabaseCredentials(appConfig.databaseId, credentials: credentials)

            // 2. Update metadata in cache
            let metadata = SecureCacheService.DatabaseConfigMetadata(
                _id: appConfig._id,
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                mode: appConfig.mode.rawValue,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                isBluetoothLeEnabled: appConfig.isBluetoothLeEnabled,
                isLanEnabled: appConfig.isLanEnabled,
                isAwdlEnabled: appConfig.isAwdlEnabled,
                isCloudSyncEnabled: appConfig.isCloudSyncEnabled
            )
            try await cacheService.saveDatabaseConfig(metadata)

            // 3. Update in-memory cache
            if let index = cachedConfigs.firstIndex(where: { $0._id == appConfig._id }) {
                cachedConfigs[index] = appConfig
            }

            // 4. Notify UI
            notifyConfigUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Deletes a database configuration
    /// - Parameter appConfig: Configuration to delete
    /// - Throws: Error if delete fails
    func deleteDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        do {
            // 1. Delete credentials from Keychain
            try await keychainService.deleteDatabaseCredentials(appConfig.databaseId)

            // 2. Delete metadata from cache
            try await cacheService.deleteDatabaseConfig(appConfig._id)

            // 3. Delete all per-database data (history, favorites, observers)
            try await cacheService.deleteDatabaseData(appConfig.databaseId)

            // 4. Update in-memory cache
            cachedConfigs.removeAll { $0._id == appConfig._id }

            // 5. Notify UI
            notifyConfigUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnDittoDatabaseConfigUpdate(_ callback: @escaping ([DittoConfigForDatabase]) -> Void) {
        self.onDittoDatabaseConfigUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyConfigUpdate() {
        // Notify UI of changes
        onDittoDatabaseConfigUpdate?(cachedConfigs)
    }
}
