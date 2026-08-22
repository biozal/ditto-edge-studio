import DittoSwift
import Foundation

/// Repository for managing database configurations, persisted in the local store
///
/// **Storage Strategy:**
/// - All data (credentials + metadata) → the local SQLite store managed by
///   `SQLCipherService`
/// - In-memory cache for fast access during session
///
/// **Performance:**
/// - Load: < 30ms (SQLCipher query only)
/// - Save: < 15ms (SQLCipher write only)
/// - In-memory access: < 1ms
///
/// **Security:**
/// - **Not encrypted at rest.** The `SQLCipher*` names throughout this codebase are
///   historical: no SQLCipher library is linked, so `PRAGMA key` is a silent no-op on
///   Apple's system SQLite and the file on disk begins with `SQLite format 3`. See
///   `docs/CREDENTIAL_STORAGE.md` — this is a recorded, accepted decision, not an
///   oversight.
/// - A 64-character key file **is** generated and stored 0600, and it does protect the
///   *key* — but the key currently encrypts nothing, because nothing consumes it.
/// - Credentials (`developmentToken`, `secretKey`, `httpApiKey`) are therefore readable
///   by anything that can read the file, which on macOS means the user's own processes.
actor DatabaseRepository {
    static let shared = DatabaseRepository()

    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

    private let dittoManager = DittoManager.shared
    private var appState: AppState?

    /// In-memory cache for fast access
    private var cachedConfigs: [DittoConfigForDatabase] = []

    /// Callback for UI updates. @MainActor-isolated so call sites get a
    /// compile-time guarantee they're on the main thread; matches the pattern
    /// used by HistoryRepository, FavoritesRepository, ObservableRepository.
    private var onDittoDatabaseConfigUpdate: (@MainActor @Sendable ([DittoConfigForDatabase]) -> Void)?

    private init() {}

    // MARK: - Advanced Settings JSON Bridging

    /// Strict, but **per row**: a malformed block marks only that config unopenable.
    ///
    /// Aborting the whole load (which `try rows.map` used to do) meant one bad row hid
    /// every other database behind a "couldn't load" screen — and the error told the
    /// user to fix it in the editor, which is only reachable through the list that had
    /// just failed to load.
    private static func decodeSyncScopes(
        _ json: String,
        databaseId: String
    ) -> (scopes: [CollectionSyncScope], isCorrupt: Bool) {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return ([], false) }
        do {
            return try (JSONDecoder().decode([CollectionSyncScope].self, from: Data(trimmed.utf8)), false)
        } catch {
            Log.error("[Advanced] Corrupt collectionSyncScopes for '\(databaseId)': \(error)")
            return ([], true)
        }
    }

    /// Lenient: startup settings are tuning knobs, so a malformed block degrades to
    /// none rather than blocking access to the database.
    private static func decodeStartupSettings(_ json: String, databaseId: String) -> [StartupSetting] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        do {
            return try JSONDecoder().decode([StartupSetting].self, from: Data(trimmed.utf8))
        } catch {
            Log.warning("[Advanced] Ignoring unreadable startupSettings for '\(databaseId)': \(error)")
            return []
        }
    }

    /// Encodes an advanced-settings list for storage. Returns `"[]"` if encoding
    /// somehow fails, which is safe for both lists on the write path.
    private static func encodeJSON(_ value: some Encodable) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - Test Support

    #if DEBUG
    /// Drops the in-memory cache. Test-only, compiled out of Release: the singleton's
    /// cache survives a swapped SQLCipher context, which otherwise leaks state between
    /// suites.
    func clearCacheForTesting() {
        cachedConfigs = []
    }
    #endif

    // MARK: - Public API

    /// Loads all database configurations from secure storage
    /// - Returns: Array of database configurations
    /// - Throws: Error if load fails
    func loadDatabaseConfigs() async throws -> [DittoConfigForDatabase] {
        // 1. Load all data from SQLCipher (includes credentials)
        let rows = try await sqlCipher.getAllDatabaseConfigs()

        // 2. Convert rows to DittoConfigForDatabase objects
        let configs = rows.map { row in
            let decodedScopes = Self.decodeSyncScopes(row.collectionSyncScopes, databaseId: row.databaseId)
            let config = DittoConfigForDatabase(
                row._id,
                name: row.name,
                databaseId: row.databaseId,
                // SQL columns keep their legacy names (`token`, `authUrl`); the
                // model exposes the v5 names (`developmentToken`, `url`).
                developmentToken: row.token,
                url: row.authUrl,
                httpApiUrl: row.httpApiUrl,
                httpApiKey: row.httpApiKey,
                // Legacy-tolerant: old stored mode strings ("server"/"smallpeersonly")
                // still map to the current v5 cases.
                mode: DittoAppConfigLoader.parseMode(from: row.mode) ?? .default,
                allowUntrustedCerts: row.allowUntrustedCerts,
                secretKey: row.secretKey,
                isBluetoothLeEnabled: row.isBluetoothLeEnabled,
                isLanEnabled: row.isLanEnabled,
                isAwdlEnabled: row.isAwdlEnabled,
                isCloudSyncEnabled: row.isCloudSyncEnabled,
                logLevel: row.logLevel,
                isStrictModeEnabled: row.isStrictModeEnabled,
                collectionSyncScopes: decodedScopes.scopes,
                startupSettings: Self.decodeStartupSettings(row.startupSettings, databaseId: row.databaseId)
            )
            // Marked, not thrown: the config still appears in the list (so the user can
            // reach the editor and fix it) but `hydrate` refuses to open it, because a
            // dropped `LocalPeerOnly` scope would otherwise start syncing.
            config.hasCorruptSyncScopes = decodedScopes.isCorrupt
            return config
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
                token: appConfig.developmentToken,
                authUrl: appConfig.url,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey,
                logLevel: appConfig.logLevel,
                isStrictModeEnabled: appConfig.isStrictModeEnabled,
                collectionSyncScopes: Self.encodeJSON(appConfig.collectionSyncScopes),
                startupSettings: Self.encodeJSON(appConfig.startupSettings)
            )
            try await sqlCipher.insertDatabaseConfig(row)

            // 2. Update in-memory cache
            cachedConfigs.append(appConfig)

            // 3. Notify UI
            await notifyConfigUpdate()

            Log.info("Added database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to add database configuration: \(error)")
            await appState?.setError(error)
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
                token: appConfig.developmentToken,
                authUrl: appConfig.url,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                secretKey: appConfig.secretKey,
                logLevel: appConfig.logLevel,
                isStrictModeEnabled: appConfig.isStrictModeEnabled,
                collectionSyncScopes: Self.encodeJSON(appConfig.collectionSyncScopes),
                startupSettings: Self.encodeJSON(appConfig.startupSettings)
            )
            try await sqlCipher.updateDatabaseConfig(row)

            // 2. Update in-memory cache
            if let index = cachedConfigs.firstIndex(where: { $0._id == appConfig._id }) {
                cachedConfigs[index] = appConfig
            }

            // 3. Notify UI
            await notifyConfigUpdate()

            Log.info("Updated database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to update database configuration: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Deletes a database configuration
    /// - Parameter appConfig: Configuration to delete
    /// - Throws: Error if delete fails
    func deleteDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        do {
            // 1. Stop sync and release file handles if this database is currently open
            await dittoManager.closeDatabaseIfSelected(databaseId: appConfig.databaseId)

            // 2. Delete from SQLCipher (includes credentials)
            // CASCADE DELETE automatically removes:
            // - All subscriptions for this database
            // - All history for this database
            // - All favorites for this database
            // - All observables for this database
            try await sqlCipher.deleteDatabaseConfig(databaseId: appConfig.databaseId)

            // 3. Delete database files from disk
            let dbDirectory = DittoManager.localDirectoryPath(for: appConfig)
            if FileManager.default.fileExists(atPath: dbDirectory.path) {
                do {
                    try FileManager.default.removeItem(at: dbDirectory)
                    Log.info("Deleted database files at: \(dbDirectory.path)")
                } catch {
                    // Log but don't propagate — the SQLCipher record is gone so the database
                    // won't load again. Orphaned files are benign but worth investigating.
                    Log.warning("Failed to delete database files at \(dbDirectory.path): \(error.localizedDescription)")
                }
            }

            // 4. Update in-memory cache
            cachedConfigs.removeAll { $0._id == appConfig._id }

            // 5. Notify UI
            await notifyConfigUpdate()

            Log.info("Deleted database configuration: \(appConfig.name)")
        } catch {
            Log.error("Failed to delete database configuration: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnDittoDatabaseConfigUpdate(_ callback: @escaping @MainActor @Sendable ([DittoConfigForDatabase]) -> Void) {
        onDittoDatabaseConfigUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyConfigUpdate() async {
        // Notify UI of changes
        await onDittoDatabaseConfigUpdate?(cachedConfigs)
    }
}

// MARK: - Protocol Conformance

extension DatabaseRepository: DatabaseRepositoryProtocol {}
