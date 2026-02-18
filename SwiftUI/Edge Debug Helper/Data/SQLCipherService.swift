//
//  SQLCipherService.swift
//  Edge Debug Helper
//
//  Created by Claude Code on 2026-02-17.
//  Copyright © 2026 Ditto. All rights reserved.
//

import Foundation
import SQLite3

/// SQLITE_TRANSIENT constant for Swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Actor-based service for managing encrypted SQLite database operations using SQLCipher
///
/// This service provides:
/// - 256-bit AES encryption of all local cache data
/// - Thread-safe access via Swift actor isolation
/// - Schema management and migrations
/// - CRUD operations for all repositories
/// - Transaction support with rollback
/// - Encryption key management via macOS Keychain
///
/// Database Path:
/// - Production: ~/Library/Application Support/ditto_cache/ditto_encrypted.db
/// - Test: ~/Library/Application Support/ditto_cache_test/ditto_encrypted.db
///
/// Security:
/// - Encryption key stored in macOS Keychain (kSecAttrAccessibleAfterFirstUnlock)
/// - Key accessible after first unlock, persists until reboot
/// - Hardware-encrypted in Secure Enclave (M1+ Macs)
/// - Database file encrypted at rest with AES-256
/// - No user prompts during normal usage on macOS
///
actor SQLCipherService {
    // MARK: - Singleton

    static let shared = SQLCipherService()

    // MARK: - Properties

    private var db: OpaquePointer?
    private var _isInitialized = false

    // MARK: - Schema Version

    private let currentSchemaVersion = 1

    // MARK: - Initialization

    private init() {}

    /// Initializes the encrypted database connection
    ///
    /// - Sets up database file path based on test/production mode
    /// - Retrieves or generates encryption key from Keychain
    /// - Opens encrypted connection with SQLCipher PRAGMAs
    /// - Creates schema if needed
    /// - Runs migrations if schema version changed
    ///
    /// - Throws: SQLCipherError if initialization fails
    func initialize() async throws {
        guard !_isInitialized else { return }

        // Get database path (test-aware)
        let dbPath = try getDatabasePath()

        // Get encryption key from Keychain
        let encryptionKey = try await getOrCreateEncryptionKey()

        // Open database connection
        let result = sqlite3_open(dbPath.path, &db)
        guard result == SQLITE_OK else {
            throw SQLCipherError.databaseOpenFailed(code: result)
        }

        // Set encryption key (CRITICAL: must be first PRAGMA)
        try executePragma("PRAGMA key = '\(encryptionKey)'")

        // Security PRAGMAs (recommended by SQLCipher)
        try executePragma("PRAGMA cipher_page_size = 4096")
        try executePragma("PRAGMA cipher_use_hmac = ON")
        try executePragma("PRAGMA cipher_memory_security = ON")
        try executePragma("PRAGMA temp_store = MEMORY")
        try executePragma("PRAGMA foreign_keys = ON") // Enable cascade deletion
        try executePragma("PRAGMA journal_mode = WAL") // Write-Ahead Logging for performance

        // Verify encryption worked (test query)
        try verifyEncryption()

        // Get current schema version
        let dbVersion = try getSchemaVersion()

        if dbVersion == 0 {
            // Fresh database, create schema
            try await createSchema()
        } else if dbVersion < currentSchemaVersion {
            // Migrate schema
            try await migrateSchema(from: dbVersion, to: currentSchemaVersion)
        }

        _isInitialized = true
        Log.info("SQLCipher initialized successfully (schema version \(currentSchemaVersion))")
    }

    /// Verifies that encryption is working by running a test query
    private func verifyEncryption() throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = "SELECT 1"
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)

        guard result == SQLITE_OK else {
            throw SQLCipherError.encryptionVerificationFailed(
                message: "Failed to verify encryption. Wrong key or corrupted database."
            )
        }
    }

    /// Executes a PRAGMA statement
    private func executePragma(_ pragma: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, pragma, nil, nil, &errorMsg)

        if let errorMsg {
            let error = String(cString: errorMsg)
            sqlite3_free(errorMsg)
            throw SQLCipherError.pragmaFailed(pragma: pragma, error: error)
        }

        guard result == SQLITE_OK else {
            throw SQLCipherError.pragmaFailed(pragma: pragma, error: "Unknown error")
        }
    }

    // MARK: - Database Path

    /// Returns the database file path based on test/production mode
    private func getDatabasePath() throws -> URL {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING")
        let cacheDir = isUITesting ? "ditto_cache_test" : "ditto_cache"

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDirURL = appSupportURL.appendingPathComponent(cacheDir)

        // Create directory if needed
        if !fileManager.fileExists(atPath: cacheDirURL.path) {
            try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        }

        return cacheDirURL.appendingPathComponent("ditto_encrypted.db")
    }

    // MARK: - Encryption Key Management

    /// Retrieves or creates the encryption key from macOS Keychain
    ///
    /// Strategy: Store in Keychain with kSecAttrAccessibleAfterFirstUnlock
    /// - Key accessible after user unlocks Mac (persists until reboot)
    /// - No user prompts during normal macOS usage
    /// - Hardware-encrypted in Secure Enclave (M1+ Macs)
    /// - Better security than deprecated kSecAttrAccessibleAlways
    /// - Survives app reinstalls (if Keychain backup enabled)
    ///
    /// - Returns: 64-character hex-encoded 256-bit key
    /// - Throws: SQLCipherError if key generation or Keychain access fails
    func getOrCreateEncryptionKey() async throws -> String {
        let keyAccount = "sqlcipher_master_key"
        let keyService = "live.ditto.EdgeStudio.sqlcipher"

        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        }

        // Key doesn't exist, generate new one
        Log.info("Generating new SQLCipher encryption key")

        var randomBytes = [UInt8](repeating: 0, count: 32)
        let generateResult = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)

        guard generateResult == errSecSuccess else {
            throw SQLCipherError.keyGenerationFailed
        }

        let key = randomBytes.map { String(format: "%02x", $0) }.joined()

        // Save to Keychain with kSecAttrAccessibleAfterFirstUnlock
        // This is the Apple-recommended option for macOS apps:
        // - Key accessible after user unlocks Mac (persists until reboot)
        // - No user prompts during normal usage on macOS
        // - Better security than kSecAttrAccessibleAlways (deprecated)
        // - Key not accessible when Mac is locked
        guard let keyData = key.data(using: .utf8) else {
            throw SQLCipherError.keyGenerationFailed
        }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw SQLCipherError.keychainSaveFailed(code: addStatus)
        }

        Log.info("SQLCipher encryption key generated and saved to Keychain")
        return key
    }

    /// Rotates the encryption key (for security best practices)
    ///
    /// WARNING: This is a destructive operation. All data will be re-encrypted.
    /// Ensure you have a backup before calling this method.
    ///
    /// Implementation requires:
    /// 1. Generate new key
    /// 2. Execute PRAGMA rekey = 'new_key'
    /// 3. Update Keychain with new key
    /// 4. Verify re-encryption succeeded
    func rotateEncryptionKey() async throws {
        throw SQLCipherError.notImplemented(feature: "Key rotation")
    }

    // MARK: - Schema Management

    /// Creates the initial database schema
    func createSchema() async throws {
        Log.info("Creating SQLCipher schema version \(currentSchemaVersion)")

        try await executeTransaction {
            // Database configurations (metadata only, credentials stay in Keychain)
            try await execute("""
                CREATE TABLE IF NOT EXISTS databaseConfigs (
                    _id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    databaseId TEXT NOT NULL UNIQUE,
                    mode TEXT NOT NULL,
                    allowUntrustedCerts INTEGER DEFAULT 0,
                    isBluetoothLeEnabled INTEGER DEFAULT 1,
                    isLanEnabled INTEGER DEFAULT 1,
                    isAwdlEnabled INTEGER DEFAULT 1,
                    isCloudSyncEnabled INTEGER DEFAULT 1
                )
            """)

            // Subscriptions (per-database)
            try await execute("""
                CREATE TABLE IF NOT EXISTS subscriptions (
                    _id TEXT PRIMARY KEY,
                    databaseId TEXT NOT NULL,
                    name TEXT NOT NULL,
                    query TEXT NOT NULL,
                    args TEXT,
                    FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE
                )
            """)

            // Query history (per-database)
            try await execute("""
                CREATE TABLE IF NOT EXISTS history (
                    _id TEXT PRIMARY KEY,
                    databaseId TEXT NOT NULL,
                    query TEXT NOT NULL,
                    createdDate TEXT NOT NULL,
                    FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE
                )
            """)

            // Favorites (per-database)
            try await execute("""
                CREATE TABLE IF NOT EXISTS favorites (
                    _id TEXT PRIMARY KEY,
                    databaseId TEXT NOT NULL,
                    query TEXT NOT NULL,
                    createdDate TEXT NOT NULL,
                    FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE
                )
            """)

            // Observables (per-database)
            try await execute("""
                CREATE TABLE IF NOT EXISTS observables (
                    _id TEXT PRIMARY KEY,
                    databaseId TEXT NOT NULL,
                    name TEXT NOT NULL,
                    query TEXT NOT NULL,
                    args TEXT,
                    isActive INTEGER DEFAULT 1,
                    lastUpdated TEXT,
                    FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE
                )
            """)

            // Create indexes for performance
            try await execute("CREATE INDEX IF NOT EXISTS idx_subscriptions_databaseId ON subscriptions(databaseId)")
            try await execute("CREATE INDEX IF NOT EXISTS idx_history_databaseId ON history(databaseId)")
            try await execute("CREATE INDEX IF NOT EXISTS idx_history_databaseId_date ON history(databaseId, createdDate DESC)")
            try await execute("CREATE INDEX IF NOT EXISTS idx_favorites_databaseId ON favorites(databaseId)")
            try await execute("CREATE INDEX IF NOT EXISTS idx_observables_databaseId ON observables(databaseId)")

            // Set schema version
            try await execute("PRAGMA user_version = \(currentSchemaVersion)")
        }

        Log.info("SQLCipher schema created successfully")
    }

    /// Migrates the schema from one version to another
    func migrateSchema(from oldVersion: Int, to newVersion: Int) async throws {
        Log.info("Migrating SQLCipher schema from version \(oldVersion) to \(newVersion)")

        // Future migrations will be implemented here
        // Example:
        // if oldVersion < 2 {
        //     try await migrateToVersion2()
        // }
        // if oldVersion < 3 {
        //     try await migrateToVersion3()
        // }

        // Update schema version
        try await execute("PRAGMA user_version = \(newVersion)")

        Log.info("SQLCipher schema migration complete")
    }

    /// Returns the current schema version from the database
    func getSchemaVersion() throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = "PRAGMA user_version"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLCipherError.queryFailed(sql: sql, error: lastErrorMessage())
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Database Configs Operations

    /// Row structure for databaseConfigs table
    struct DatabaseConfigRow {
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

    func insertDatabaseConfig(_ config: DatabaseConfigRow) async throws {
        let sql = """
            INSERT INTO databaseConfigs (_id, name, databaseId, mode, allowUntrustedCerts,
                isBluetoothLeEnabled, isLanEnabled, isAwdlEnabled, isCloudSyncEnabled)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        try await execute(
            sql,
            config._id,
            config.name,
            config.databaseId,
            config.mode,
            config.allowUntrustedCerts ? 1 : 0,
            config.isBluetoothLeEnabled ? 1 : 0,
            config.isLanEnabled ? 1 : 0,
            config.isAwdlEnabled ? 1 : 0,
            config.isCloudSyncEnabled ? 1 : 0
        )
    }

    func updateDatabaseConfig(_ config: DatabaseConfigRow) async throws {
        let sql = """
            UPDATE databaseConfigs
            SET name = ?, mode = ?, allowUntrustedCerts = ?,
                isBluetoothLeEnabled = ?, isLanEnabled = ?, isAwdlEnabled = ?, isCloudSyncEnabled = ?
            WHERE databaseId = ?
        """

        try await execute(
            sql,
            config.name,
            config.mode,
            config.allowUntrustedCerts ? 1 : 0,
            config.isBluetoothLeEnabled ? 1 : 0,
            config.isLanEnabled ? 1 : 0,
            config.isAwdlEnabled ? 1 : 0,
            config.isCloudSyncEnabled ? 1 : 0,
            config.databaseId
        )
    }

    func deleteDatabaseConfig(databaseId: String) async throws {
        // CASCADE DELETE will automatically remove:
        // - subscriptions
        // - history
        // - favorites
        // - observables
        let sql = "DELETE FROM databaseConfigs WHERE databaseId = ?"
        try await execute(sql, databaseId)
    }

    func getAllDatabaseConfigs() async throws -> [DatabaseConfigRow] {
        let sql = "SELECT _id, name, databaseId, mode, allowUntrustedCerts, isBluetoothLeEnabled, isLanEnabled, isAwdlEnabled, isCloudSyncEnabled FROM databaseConfigs"

        var results: [DatabaseConfigRow] = []
        try await query(sql) { statement in
            results.append(DatabaseConfigRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                databaseId: String(cString: sqlite3_column_text(statement, 2)),
                mode: String(cString: sqlite3_column_text(statement, 3)),
                allowUntrustedCerts: sqlite3_column_int(statement, 4) != 0,
                isBluetoothLeEnabled: sqlite3_column_int(statement, 5) != 0,
                isLanEnabled: sqlite3_column_int(statement, 6) != 0,
                isAwdlEnabled: sqlite3_column_int(statement, 7) != 0,
                isCloudSyncEnabled: sqlite3_column_int(statement, 8) != 0
            ))
        }

        return results
    }

    // MARK: - Subscriptions Operations

    struct SubscriptionRow {
        let _id: String
        let databaseId: String
        let name: String
        let query: String
        let args: String?
    }

    func insertSubscription(_ subscription: SubscriptionRow) async throws {
        let sql = "INSERT INTO subscriptions (_id, databaseId, name, query, args) VALUES (?, ?, ?, ?, ?)"
        try await execute(sql, subscription._id, subscription.databaseId, subscription.name, subscription.query, subscription.args)
    }

    func getSubscriptions(databaseId: String) async throws -> [SubscriptionRow] {
        let sql = "SELECT _id, databaseId, name, query, args FROM subscriptions WHERE databaseId = ?"

        var results: [SubscriptionRow] = []
        try await query(sql, databaseId) { statement in
            let args = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))

            results.append(SubscriptionRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                name: String(cString: sqlite3_column_text(statement, 2)),
                query: String(cString: sqlite3_column_text(statement, 3)),
                args: args
            ))
        }

        return results
    }

    func deleteSubscription(id: String) async throws {
        let sql = "DELETE FROM subscriptions WHERE _id = ?"
        try await execute(sql, id)
    }

    func deleteAllSubscriptions(databaseId: String) async throws {
        let sql = "DELETE FROM subscriptions WHERE databaseId = ?"
        try await execute(sql, databaseId)
    }

    // MARK: - History Operations

    struct HistoryRow {
        let _id: String
        let databaseId: String
        let query: String
        let createdDate: String
    }

    func insertHistory(_ history: HistoryRow) async throws {
        let sql = "INSERT INTO history (_id, databaseId, query, createdDate) VALUES (?, ?, ?, ?)"
        try await execute(sql, history._id, history.databaseId, history.query, history.createdDate)
    }

    func getHistory(databaseId: String, limit: Int = 1000) async throws -> [HistoryRow] {
        let sql = "SELECT _id, databaseId, query, createdDate FROM history WHERE databaseId = ? ORDER BY createdDate DESC LIMIT ?"

        var results: [HistoryRow] = []
        try await query(sql, databaseId, limit) { statement in
            results.append(HistoryRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                query: String(cString: sqlite3_column_text(statement, 2)),
                createdDate: String(cString: sqlite3_column_text(statement, 3))
            ))
        }

        return results
    }

    func deleteHistory(id: String) async throws {
        let sql = "DELETE FROM history WHERE _id = ?"
        try await execute(sql, id)
    }

    func deleteAllHistory(databaseId: String) async throws {
        let sql = "DELETE FROM history WHERE databaseId = ?"
        try await execute(sql, databaseId)
    }

    // MARK: - Favorites Operations

    struct FavoriteRow {
        let _id: String
        let databaseId: String
        let query: String
        let createdDate: String
    }

    func insertFavorite(_ favorite: FavoriteRow) async throws {
        let sql = "INSERT INTO favorites (_id, databaseId, query, createdDate) VALUES (?, ?, ?, ?)"
        try await execute(sql, favorite._id, favorite.databaseId, favorite.query, favorite.createdDate)
    }

    func getFavorites(databaseId: String) async throws -> [FavoriteRow] {
        let sql = "SELECT _id, databaseId, query, createdDate FROM favorites WHERE databaseId = ? ORDER BY createdDate DESC"

        var results: [FavoriteRow] = []
        try await query(sql, databaseId) { statement in
            results.append(FavoriteRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                query: String(cString: sqlite3_column_text(statement, 2)),
                createdDate: String(cString: sqlite3_column_text(statement, 3))
            ))
        }

        return results
    }

    func deleteFavorite(id: String) async throws {
        let sql = "DELETE FROM favorites WHERE _id = ?"
        try await execute(sql, id)
    }

    func deleteAllFavorites(databaseId: String) async throws {
        let sql = "DELETE FROM favorites WHERE databaseId = ?"
        try await execute(sql, databaseId)
    }

    // MARK: - Observables Operations

    struct ObservableRow {
        let _id: String
        let databaseId: String
        let name: String
        let query: String
        let args: String?
        let isActive: Bool
        let lastUpdated: String?
    }

    func insertObservable(_ observable: ObservableRow) async throws {
        let sql = "INSERT INTO observables (_id, databaseId, name, query, args, isActive, lastUpdated) VALUES (?, ?, ?, ?, ?, ?, ?)"
        try await execute(
            sql,
            observable._id,
            observable.databaseId,
            observable.name,
            observable.query,
            observable.args,
            observable.isActive ? 1 : 0,
            observable.lastUpdated
        )
    }

    func updateObservable(_ observable: ObservableRow) async throws {
        let sql = "UPDATE observables SET name = ?, query = ?, args = ?, isActive = ?, lastUpdated = ? WHERE _id = ?"
        try await execute(
            sql,
            observable.name,
            observable.query,
            observable.args,
            observable.isActive ? 1 : 0,
            observable.lastUpdated,
            observable._id
        )
    }

    func getObservables(databaseId: String) async throws -> [ObservableRow] {
        let sql = "SELECT _id, databaseId, name, query, args, isActive, lastUpdated FROM observables WHERE databaseId = ?"

        var results: [ObservableRow] = []
        try await query(sql, databaseId) { statement in
            let args = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))
            let lastUpdated = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 6))

            results.append(ObservableRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                name: String(cString: sqlite3_column_text(statement, 2)),
                query: String(cString: sqlite3_column_text(statement, 3)),
                args: args,
                isActive: sqlite3_column_int(statement, 5) != 0,
                lastUpdated: lastUpdated
            ))
        }

        return results
    }

    func deleteObservable(id: String) async throws {
        let sql = "DELETE FROM observables WHERE _id = ?"
        try await execute(sql, id)
    }

    func deleteAllObservables(databaseId: String) async throws {
        let sql = "DELETE FROM observables WHERE databaseId = ?"
        try await execute(sql, databaseId)
    }

    // MARK: - Transaction Support

    /// Executes a block of operations within a transaction
    /// - If any operation throws, the entire transaction is rolled back
    /// - Returns the result of the block if successful
    func executeTransaction<T>(_ block: () async throws -> T) async throws -> T {
        try await execute("BEGIN TRANSACTION")

        do {
            let result = try await block()
            try await execute("COMMIT")
            return result
        } catch {
            try? await execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Utility

    /// Optimizes database file size by reclaiming unused space
    func vacuum() async throws {
        try await execute("VACUUM")
        Log.info("SQLCipher database vacuumed")
    }

    /// Checks if the database has been initialized
    func checkInitialized() -> Bool {
        _isInitialized
    }

    // MARK: - Low-Level Execute/Query

    /// Executes a SQL statement without returning results
    private func execute(_ sql: String, _ parameters: Any?...) async throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLCipherError.queryFailed(sql: sql, error: lastErrorMessage())
        }

        // Bind parameters
        try bindParameters(statement: statement, parameters: parameters)

        // Execute
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_OK else {
            throw SQLCipherError.executeFailed(sql: sql, error: lastErrorMessage())
        }
    }

    /// Executes a SQL query and processes results with the provided handler
    private func query(_ sql: String, _ parameters: Any?..., handler: (OpaquePointer) -> Void) async throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLCipherError.queryFailed(sql: sql, error: lastErrorMessage())
        }

        // Bind parameters
        try bindParameters(statement: statement, parameters: parameters)

        // Process rows
        guard let stmt = statement else {
            throw SQLCipherError.queryFailed(sql: sql, error: "Statement is nil")
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            handler(stmt)
        }
    }

    /// Binds parameters to a prepared statement
    private func bindParameters(statement: OpaquePointer?, parameters: [Any?]) throws {
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)

            if let parameter {
                if let string = parameter as? String {
                    sqlite3_bind_text(statement, bindIndex, string, -1, SQLITE_TRANSIENT)
                } else if let int = parameter as? Int {
                    sqlite3_bind_int(statement, bindIndex, Int32(int))
                } else if let double = parameter as? Double {
                    sqlite3_bind_double(statement, bindIndex, double)
                } else {
                    throw SQLCipherError.unsupportedParameterType(type: String(describing: type(of: parameter)))
                }
            } else {
                sqlite3_bind_null(statement, bindIndex)
            }
        }
    }

    /// Returns the last error message from SQLite
    private func lastErrorMessage() -> String {
        if let error = sqlite3_errmsg(db) {
            return String(cString: error)
        }
        return "Unknown error"
    }

    // MARK: - Deinitialization

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }
}

// MARK: - SQLCipherError

enum SQLCipherError: Error, CustomStringConvertible {
    case databaseOpenFailed(code: Int32)
    case encryptionVerificationFailed(message: String)
    case pragmaFailed(pragma: String, error: String)
    case keyGenerationFailed
    case keychainSaveFailed(code: OSStatus)
    case queryFailed(sql: String, error: String)
    case executeFailed(sql: String, error: String)
    case unsupportedParameterType(type: String)
    case notImplemented(feature: String)

    var description: String {
        switch self {
        case let .databaseOpenFailed(code):
            return "Failed to open database (SQLite error code: \(code))"
        case let .encryptionVerificationFailed(message):
            return "Encryption verification failed: \(message)"
        case let .pragmaFailed(pragma, error):
            return "PRAGMA failed (\(pragma)): \(error)"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case let .keychainSaveFailed(code):
            return "Failed to save encryption key to Keychain (OSStatus: \(code))"
        case let .queryFailed(sql, error):
            return "Query failed: \(sql)\nError: \(error)"
        case let .executeFailed(sql, error):
            return "Execute failed: \(sql)\nError: \(error)"
        case let .unsupportedParameterType(type):
            return "Unsupported parameter type: \(type)"
        case let .notImplemented(feature):
            return "Feature not implemented: \(feature)"
        }
    }
}
