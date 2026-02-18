import DittoSwift
import Foundation

/// Repository for managing database configurations with secure storage
///
/// **Storage Strategy:**
/// - Sensitive credentials → macOS Keychain (encrypted)
/// - Non-sensitive metadata → SQLCipher encrypted database
/// - In-memory cache for fast access during session
///
/// **Performance:**
/// - Load: < 50ms (SQLCipher query + Keychain reads)
/// - Save: < 20ms (SQLCipher write + Keychain)
/// - In-memory access: < 1ms
///
/// **Security:**
/// - Metadata encrypted at rest with AES-256 (SQLCipher)
/// - Credentials encrypted in macOS Keychain (Secure Enclave)
actor DatabaseRepository {
    static let shared = DatabaseRepository()

    private let keychainService = KeychainService.shared
    private let sqlCipher = SQLCipherService.shared
    private var appState: AppState?

    /// In-memory cache for fast access
    private var cachedConfigs: [DittoConfigForDatabase] = []

    /// Callback for UI updates
    private var onDittoDatabaseConfigUpdate: (([DittoConfigForDatabase]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads all database configurations from secure storage
    /// - Returns: Array of database configurations
    /// - Throws: Error if load fails
    func loadDatabaseConfigs() async throws -> [DittoConfigForDatabase] {
        // 1. Load metadata from SQLCipher
        let metadataRows = try await sqlCipher.getAllDatabaseConfigs()

        var configs: [DittoConfigForDatabase] = []

        // 2. For each metadata, load credentials from Keychain
        for metadata in metadataRows {
            guard let credentials = try await keychainService.loadDatabaseCredentials(metadata.databaseId) else {
                Log.warning("No credentials found for database: \(metadata.name)")
                continue
            }

            // 3. Combine metadata + credentials into DittoConfigForDatabase
            let config = DittoConfigForDatabase(
                metadata._id,
                name: credentials.name, // Name comes from Keychain (source of truth)
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

            // 2. Save metadata to SQLCipher
            let metadata = SQLCipherService.DatabaseConfigRow(
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
            try await sqlCipher.insertDatabaseConfig(metadata)

            // 3. Update in-memory cache
            cachedConfigs.append(appConfig)

            // 4. Notify UI
            notifyConfigUpdate()

            Log.info("Added database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to add database configuration: \(error)")
            appState?.setError(error)
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

            // 2. Update metadata in SQLCipher
            let metadata = SQLCipherService.DatabaseConfigRow(
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
            try await sqlCipher.updateDatabaseConfig(metadata)

            // 3. Update in-memory cache
            if let index = cachedConfigs.firstIndex(where: { $0._id == appConfig._id }) {
                cachedConfigs[index] = appConfig
            }

            // 4. Notify UI
            notifyConfigUpdate()

            Log.info("Updated database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to update database configuration: \(error)")
            appState?.setError(error)
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

            // 2. Delete metadata from SQLCipher
            // CASCADE DELETE automatically removes:
            // - All subscriptions for this database
            // - All history for this database
            // - All favorites for this database
            // - All observables for this database
            try await sqlCipher.deleteDatabaseConfig(databaseId: appConfig.databaseId)

            // 3. Update in-memory cache
            cachedConfigs.removeAll { $0._id == appConfig._id }

            // 4. Notify UI
            notifyConfigUpdate()

            Log.info("Deleted database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to delete database configuration: \(error)")
            appState?.setError(error)
            throw error
        }
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnDittoDatabaseConfigUpdate(_ callback: @escaping ([DittoConfigForDatabase]) -> Void) {
        onDittoDatabaseConfigUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyConfigUpdate() {
        // Notify UI of changes
        onDittoDatabaseConfigUpdate?(cachedConfigs)
    }
}
