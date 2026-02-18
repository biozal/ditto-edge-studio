import DittoSwift
import Foundation

/// Repository for managing database configurations with secure storage
///
/// **Storage Strategy:**
/// - All data (credentials + metadata) → SQLCipher encrypted database
/// - In-memory cache for fast access during session
///
/// **Performance:**
/// - Load: < 30ms (SQLCipher query only)
/// - Save: < 15ms (SQLCipher write only)
/// - In-memory access: < 1ms
///
/// **Security:**
/// - All data encrypted at rest with AES-256 (SQLCipher)
/// - Encryption key stored in local file with 0600 permissions
actor DatabaseRepository {
    static let shared = DatabaseRepository()

    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

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
        // 1. Load all data from SQLCipher (includes credentials)
        let rows = try await sqlCipher.getAllDatabaseConfigs()

        // 2. Convert rows to DittoConfigForDatabase objects
        let configs = rows.map { row in
            DittoConfigForDatabase(
                row._id,
                name: row.name,
                databaseId: row.databaseId,
                token: row.token,
                authUrl: row.authUrl,
                websocketUrl: row.websocketUrl,
                httpApiUrl: row.httpApiUrl,
                httpApiKey: row.httpApiKey,
                mode: AuthMode(rawValue: row.mode) ?? .server,
                allowUntrustedCerts: row.allowUntrustedCerts,
                secretKey: row.secretKey,
                isBluetoothLeEnabled: row.isBluetoothLeEnabled,
                isLanEnabled: row.isLanEnabled,
                isAwdlEnabled: row.isAwdlEnabled,
                isCloudSyncEnabled: row.isCloudSyncEnabled
            )
        }

        // 3. Update in-memory cache
        cachedConfigs = configs

        return configs
    }

    /// Adds a new database configuration
    /// - Parameter appConfig: Configuration to add
    /// - Throws: Error if save fails
    func addDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        do {
            // 1. Save all data to SQLCipher (includes credentials)
            let row = SQLCipherService.DatabaseConfigRow(
                _id: appConfig._id,
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                mode: appConfig.mode.rawValue,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                isBluetoothLeEnabled: appConfig.isBluetoothLeEnabled,
                isLanEnabled: appConfig.isLanEnabled,
                isAwdlEnabled: appConfig.isAwdlEnabled,
                isCloudSyncEnabled: appConfig.isCloudSyncEnabled,
                token: appConfig.token,
                authUrl: appConfig.authUrl,
                websocketUrl: appConfig.websocketUrl,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey
            )
            try await sqlCipher.insertDatabaseConfig(row)

            // 2. Update in-memory cache
            cachedConfigs.append(appConfig)

            // 3. Notify UI
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
            // 1. Update all data in SQLCipher (includes credentials)
            let row = SQLCipherService.DatabaseConfigRow(
                _id: appConfig._id,
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                mode: appConfig.mode.rawValue,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                isBluetoothLeEnabled: appConfig.isBluetoothLeEnabled,
                isLanEnabled: appConfig.isLanEnabled,
                isAwdlEnabled: appConfig.isAwdlEnabled,
                isCloudSyncEnabled: appConfig.isCloudSyncEnabled,
                token: appConfig.token,
                authUrl: appConfig.authUrl,
                websocketUrl: appConfig.websocketUrl,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey
            )
            try await sqlCipher.updateDatabaseConfig(row)

            // 2. Update in-memory cache
            if let index = cachedConfigs.firstIndex(where: { $0._id == appConfig._id }) {
                cachedConfigs[index] = appConfig
            }

            // 3. Notify UI
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
            // 1. Delete from SQLCipher (includes credentials)
            // CASCADE DELETE automatically removes:
            // - All subscriptions for this database
            // - All history for this database
            // - All favorites for this database
            // - All observables for this database
            try await sqlCipher.deleteDatabaseConfig(databaseId: appConfig.databaseId)

            // 2. Update in-memory cache
            cachedConfigs.removeAll { $0._id == appConfig._id }

            // 3. Notify UI
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
