import Foundation
import LocalAuthentication
import SQLite3

/// SQLITE_TRANSIENT constant for Swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Actor-based service for the local configuration store.
///
/// This service provides:
/// - Thread-safe access via Swift actor isolation
/// - Schema management and atomic, idempotent migrations
/// - CRUD operations for all repositories
/// - Transaction support with rollback
///
/// Database Path:
/// - Production: ~/Library/Application Support/ditto_edge_studio/ditto_encrypted.db
/// - Test: ~/Library/Application Support/ditto_edge_studio_test/ditto_encrypted.db
///
/// # ⚠️ THE STORE IS NOT CURRENTLY ENCRYPTED
///
/// The type name, the file name and the `PRAGMA key` / `cipher_*` calls in
/// `initialize()` all imply SQLCipher, but **no SQLCipher dependency is linked** —
/// `import SQLite3` resolves to Apple's system libsqlite3, which silently ignores
/// unknown pragmas. The file is a plain SQLite database, and every stored database
/// token, offline license token, shared secret key and HTTP API key is readable by any
/// process with file access. The only real protection today is the **app sandbox
/// container**, whose whole path is `drwx------`. Note what it is *not*: the database file
/// itself is `0644`, and nothing here `chmod`s it — the only `setAttributes` call in this
/// file is on `sqlcipher.key`, which encrypts nothing. Measured, not assumed.
///
/// Do not add claims of encryption to this file until a remediation ships. See
/// `docs/CREDENTIAL_STORAGE.md` for the evidence, the options, and the migration each
/// one requires.
///
actor SQLCipherService {
    // MARK: - Singleton

    static let shared = SQLCipherService()

    // MARK: - Properties

    private var db: OpaquePointer?
    private var _isInitialized = false

    /// Custom database directory name for test instances (nil = use environment detection)
    private let customTestPath: String?

    // MARK: - Schema Version

    private let currentSchemaVersion = 6

    // MARK: - Initialization

    private init() {
        customTestPath = nil
    }

    /// Creates an isolated test instance pointing to a unique directory.
    ///
    /// Use with `SQLCipherContext.$current.withValue(testService) { }` to inject
    /// this instance into the current Swift task and all its children.
    ///
    /// - Parameter testPath: Directory name (relative to Application Support) for this instance.
    init(testPath: String) {
        customTestPath = testPath
    }

    /// Initializes the local database connection
    ///
    /// - Sets up database file path based on test/production mode
    /// - Retrieves or generates the key file (no Keychain — see `getOrCreateEncryptionKey`)
    /// - Opens the connection and issues the `PRAGMA key` / `cipher_*` statements, which
    ///   Apple's system SQLite silently ignores (see the type-level ⚠️ note)
    /// - Creates schema if needed
    /// - Runs migrations if schema version changed
    ///
    /// - Throws: SQLCipherError if initialization fails
    func initialize() async throws {
        guard !_isInitialized else { return }

        // Get database path (test-aware)
        let dbPath = try getDatabasePath()

        // Get the key from its file (no Keychain — see `getOrCreateEncryptionKey`)
        let encryptionKey = try await getOrCreateEncryptionKey()

        // Open database connection.
        //
        // `sqlite3_open` allocates a connection handle even when it fails, so the failure
        // path closes it too.
        let result = sqlite3_open(dbPath.path, &db)
        guard result == SQLITE_OK else {
            closeConnection()
            throw SQLCipherError.databaseOpenFailed(code: result)
        }

        // EVERY throw from here on must release the handle. `_isInitialized` stays false
        // until the very end, and the failure is surfaced with a Retry button
        // (`ContentView.sqlCipherInitErrorView`) that calls straight back into this
        // method — which overwrote `db` and leaked the previous connection, its file
        // descriptor, its WAL/SHM references and its lock, once per press. A failing
        // migration never clears on its own, so repeated Retry is exactly what the UI
        // invites. (`keyFileUnreadable` throws *before* the open and leaks nothing.)
        do {
            // Set encryption key (CRITICAL: must be first PRAGMA)
            try executePragma("PRAGMA key = '\(encryptionKey)'")

            // Security PRAGMAs (recommended by SQLCipher)
            try executePragma("PRAGMA cipher_page_size = 4096")
            try executePragma("PRAGMA cipher_use_hmac = ON")
            try executePragma("PRAGMA cipher_memory_security = ON")
            try executePragma("PRAGMA temp_store = MEMORY")
            try executePragma("PRAGMA foreign_keys = ON") // Enable cascade deletion
            try executePragma("PRAGMA journal_mode = WAL") // Write-Ahead Logging for performance

            // Prove the file is readable with this key. It cannot prove the file is
            // encrypted — see `verifyEncryption`.
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
        } catch {
            closeConnection()
            throw error
        }

        _isInitialized = true
        Log.info("SQLCipher initialized successfully (schema version \(currentSchemaVersion))")
    }

    /// Closes the connection handle if one is open and clears `db`.
    ///
    /// Idempotent, and the single teardown used by both `initialize()`'s failure paths and
    /// `resetForTesting()`: the correct teardown already existed in the latter and simply
    /// wasn't reachable from the path that needed it.
    private func closeConnection() {
        guard db != nil else { return }
        sqlite3_close(db)
        db = nil
    }

    /// Verifies the database is readable with the configured key.
    ///
    /// Reads `sqlite_master`, which forces an actual page read — the previous version
    /// prepared `SELECT 1` and never stepped it, so it touched no page and could not
    /// detect a wrong key despite its error message saying otherwise.
    ///
    /// NOTE: this proves the file is *readable*, not that it is *encrypted*. See
    /// `docs/CREDENTIAL_STORAGE.md` — this build links Apple's system SQLite, where the
    /// `PRAGMA key` calls above are silently ignored no-ops.
    private func verifyEncryption() throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = "SELECT count(*) FROM sqlite_master"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLCipherError.encryptionVerificationFailed(
                message: "Failed to read the database. Wrong key or corrupted database."
            )
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLCipherError.encryptionVerificationFailed(
                message: "Failed to read the database. Wrong key or corrupted database."
            )
        }
    }

    /// Executes a PRAGMA statement.
    ///
    /// The thrown error names the pragma **redacted**: `PRAGMA key = '<64 hex chars>'` is one
    /// of the statements that comes through here, and since `SQLCipherError` gained
    /// `LocalizedError` its text reaches an on-screen alert *and*
    /// `~/Library/Logs/io.ditto.EdgeStudio/` — the log file users are asked to attach to
    /// GitHub issues. Echoing the failing statement verbatim would put the key in both.
    private func executePragma(_ pragma: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, pragma, nil, nil, &errorMsg)

        if let errorMsg {
            let error = String(cString: errorMsg)
            sqlite3_free(errorMsg)
            throw SQLCipherError.pragmaFailed(pragma: Self.redactedPragma(pragma), error: error)
        }

        guard result == SQLITE_OK else {
            throw SQLCipherError.pragmaFailed(pragma: Self.redactedPragma(pragma), error: "Unknown error")
        }
    }

    /// A pragma statement safe to show a user and write to a log file: everything after the
    /// first `=` in a key-bearing pragma is replaced. Non-secret pragmas pass through, since
    /// knowing which one failed is the useful half of the message.
    static func redactedPragma(_ pragma: String) -> String {
        let secretPragmas = ["key", "rekey"]
        let lowered = pragma.lowercased()
        guard secretPragmas.contains(where: { lowered.contains("pragma \($0) ") || lowered.contains("pragma \($0)=") }),
              let separator = pragma.firstIndex(of: "=") else
        {
            return pragma
        }
        return pragma[pragma.startIndex ..< separator] + "= <redacted>"
    }

    // MARK: - Database Path

    /// Returns the database file path based on test/production mode
    private func getDatabasePath() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // Test instances always use their custom path — no environment detection needed
        if let customPath = customTestPath {
            let cacheDirURL = appSupportURL.appendingPathComponent(customPath)
            if !fileManager.fileExists(atPath: cacheDirURL.path) {
                try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
            }
            return cacheDirURL.appendingPathComponent("ditto_encrypted.db")
        }

        // Singleton: detect test environment at runtime
        let isUnitTesting = NSClassFromString("XCTest") != nil
        let isUITesting = isRunningUITests()

        let cacheDir = if isUnitTesting && !isUITesting {
            // Unit tests (XCTest framework is loaded, but not UI testing)
            "ditto_edge_studio_unit_test"
        } else if isUITesting {
            // UI tests
            "ditto_edge_studio_test"
        } else {
            // Normal app usage
            "ditto_edge_studio"
        }

        let cacheDirURL = appSupportURL.appendingPathComponent(cacheDir)

        // Create directory if needed
        if !fileManager.fileExists(atPath: cacheDirURL.path) {
            try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        }

        return cacheDirURL.appendingPathComponent("ditto_encrypted.db")
    }

    // MARK: - Encryption Key Management

    /// Retrieves or creates the key file.
    ///
    /// **There is no Keychain involvement.** The paragraph that used to sit here described
    /// a Keychain implementation — `kSecAttrAccessibleAfterFirstUnlock`, Secure Enclave,
    /// "accessible after the user unlocks the Mac" — that the code below replaced and that
    /// nothing has honoured since. It is deleted rather than corrected because it was the
    /// source of a review finding against the file-protection class chosen below: the class
    /// is deliberate and correct for a file, and the stale comment was the actual defect.
    ///
    /// A 64-character hex key in a `0600` file next to the store, protected by
    /// `.completeFileProtection` and — on the store it nominally guards — by nothing else,
    /// because the store is not encrypted. See `docs/CREDENTIAL_STORAGE.md`.
    ///
    /// **There is no test-mode key branch.** An earlier version of this comment described
    /// "a fixed 64-character key under `UI-TESTING`"; no such branch has ever existed here.
    /// Test isolation comes from `getDatabasePath`, which gives unit tests, UI tests and
    /// production separate directories — so each gets its own generated key for free.
    ///
    /// - Returns: 64-character hex-encoded 256-bit key
    /// - Throws: SQLCipherError if key generation or Keychain access fails
    func getOrCreateEncryptionKey() async throws -> String {
        // FINAL FIX: Store encryption key in local file (NO KEYCHAIN)
        // This is simpler, more reliable, and perfect for a developer tool
        // Key still secure: Protected by macOS FileVault + file permissions (0600)

        let dbPath = try getDatabasePath()
        let keyFilePath = dbPath.deletingLastPathComponent().appendingPathComponent("sqlcipher.key")

        let fileManager = FileManager.default

        // Try to load existing key from file.
        //
        // If the file EXISTS but cannot be read or parsed we must fail, never regenerate:
        // overwriting it discards the only key for a store holding every database token,
        // offline license and HTTP API key, and the resulting failure ("wrong key") has no
        // in-app recovery. A transient read error must not be a data-loss event.
        //
        // Today that loss is hypothetical — the store is plaintext, so the key is not
        // consulted (`docs/CREDENTIAL_STORAGE.md`). The guard stays anyway: the moment a real
        // SQLCipher product is linked it becomes load-bearing, and a silent-rotation habit
        // written into the code now is what would make it destructive then.
        if fileManager.fileExists(atPath: keyFilePath.path) {
            let keyData: Data
            do {
                keyData = try Data(contentsOf: keyFilePath)
            } catch {
                Log.error("Existing encryption key file could not be read: \(error)")
                throw SQLCipherError.keyFileUnreadable(reason: error.localizedDescription)
            }
            guard let key = String(data: keyData, encoding: .utf8), key.count == 64 else {
                Log.error("Existing encryption key file is malformed (\(keyData.count) bytes)")
                throw SQLCipherError.keyFileUnreadable(reason: "malformed, \(keyData.count) bytes")
            }
            Log.info("Loaded SQLCipher encryption key from file")
            return key
        }

        // Generate new 256-bit key
        Log.info("Generating new SQLCipher encryption key")

        var randomBytes = [UInt8](repeating: 0, count: 32)
        let generateResult = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)

        guard generateResult == errSecSuccess else {
            throw SQLCipherError.keyGenerationFailed
        }

        let key = randomBytes.map { String(format: "%02x", $0) }.joined()

        // Save to file with restricted permissions
        guard let keyData = key.data(using: .utf8) else {
            throw SQLCipherError.keyGenerationFailed
        }

        do {
            // Create directory if needed
            let keyDir = keyFilePath.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: keyDir.path) {
                try fileManager.createDirectory(at: keyDir, withIntermediateDirectories: true)
            }

            // This file is the master key for the store holding every database token,
            // offline license and HTTP API key, so it is written with the strongest
            // protection the platform accepts.
            //
            // `.completeFileProtection` is what keeps it unreadable while an iPadOS
            // device is locked and out of unencrypted backups — it must not be dropped
            // to make a sandboxed test host happy. macOS has no data-protection classes,
            // and a sandboxed host can reject the option with NSFileWriteNoPermission, so
            // fall back only there and only after the protected write has been attempted.
            do {
                try keyData.write(to: keyFilePath, options: [.atomic, .completeFileProtection])
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                && (error.code == NSFileWriteNoPermissionError || error.code == NSFeatureUnsupportedError)
            {
                Log.warning(
                    "SQLCipher key file: data protection unavailable on this platform " +
                        "(\(error.code)); falling back to an atomic write with 0600 permissions"
                )
                try keyData.write(to: keyFilePath, options: .atomic)
            }

            // Set file permissions to 0600 (read/write owner only)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFilePath.path)

            Log.info("SQLCipher encryption key saved to file: \(keyFilePath.path)")
        } catch {
            throw SQLCipherError.keyFileWriteFailed(code: Int32((error as NSError).code))
        }

        return key
    }

    /// Rotates the key. **Unimplemented, and cannot be implemented as written** while the
    /// store is plaintext: `PRAGMA rekey` is another no-op on Apple's system SQLite, so
    /// there is nothing to re-encrypt. Any real implementation belongs with the D1
    /// remediation (`docs/CREDENTIAL_STORAGE.md`), not before it.
    func rotateEncryptionKey() async throws {
        throw SQLCipherError.notImplemented(feature: "Key rotation")
    }

    // MARK: - Schema Management

    /// Creates the initial database schema
    func createSchema() async throws {
        Log.info("Creating SQLCipher schema version \(currentSchemaVersion)")

        try await executeTransaction {
            // Database configurations (includes credentials — stored in the clear, see the
            // type-level ⚠️ note and `docs/CREDENTIAL_STORAGE.md`)
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
                    isCloudSyncEnabled INTEGER DEFAULT 1,
                    token TEXT NOT NULL DEFAULT '',
                    authUrl TEXT NOT NULL DEFAULT '',
                    httpApiUrl TEXT NOT NULL DEFAULT '',
                    httpApiKey TEXT NOT NULL DEFAULT '',
                    secretKey TEXT NOT NULL DEFAULT '',
                    logLevel TEXT NOT NULL DEFAULT 'info',
                    isStrictModeEnabled INTEGER DEFAULT 0,
                    collectionSyncScopes TEXT NOT NULL DEFAULT '[]',
                    startupSettings TEXT NOT NULL DEFAULT '[]',
                    isMulticastEnabled INTEGER DEFAULT 0,
                    multicastGroupAddress TEXT NOT NULL DEFAULT '224.1.2.3',
                    multicastPort INTEGER DEFAULT 6003,
                    multicastInterfaceName TEXT
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

    /// Migrates the schema from one version to another.
    ///
    /// Every step is **atomic and idempotent**: each migration adds only the columns that
    /// are absent, and stamps its own `user_version` inside the same transaction. That
    /// matters because a process death (jetsam, force-quit, full disk) between two
    /// `ALTER TABLE`s used to leave `user_version` behind with one column already added —
    /// the next launch re-ran the migration, hit "duplicate column name", `initialize()`
    /// threw, and **every stored config and credential became permanently
    /// inaccessible** with no in-app recovery.
    func migrateSchema(from oldVersion: Int, to newVersion: Int) async throws {
        Log.info("Migrating SQLCipher schema from version \(oldVersion) to \(newVersion)")

        // Migrate from version 1 to 2: Add credential columns
        if oldVersion < 2 {
            try await migrateToVersion2()
        }

        // Migrate from version 2 to 3: Add logLevel column
        if oldVersion < 3 {
            try await migrateToVersion3()
        }

        // Migrate from version 3 to 4: Add isStrictModeEnabled column
        if oldVersion < 4 {
            try await migrateToVersion4()
        }

        // Migrate from version 4 to 5: Add advanced configuration columns
        if oldVersion < 5 {
            try await migrateToVersion5()
        }

        // Migrate from version 5 to 6: Add multicast (beta) transport columns
        if oldVersion < 6 {
            try await migrateToVersion6()
        }

        // Belt and braces: each step already stamped its own version inside its
        // transaction, so this only matters when `newVersion` is ahead of every step.
        try await execute("PRAGMA user_version = \(newVersion)")

        Log.info("SQLCipher schema migration complete")
    }

    /// Adds `column` to `databaseConfigs` only if it is missing.
    private func addColumnIfMissing(_ column: String, definition: String) async throws {
        guard try await !columnExists(column, inTable: "databaseConfigs") else {
            Log.info("Schema: column '\(column)' already present — skipping")
            return
        }
        try await execute("ALTER TABLE databaseConfigs ADD COLUMN \(column) \(definition)")
    }

    /// Migration to version 2: Add credential columns to databaseConfigs table
    private func migrateToVersion2() async throws {
        Log.info("Migrating to schema version 2: Adding credential columns")

        try await executeTransaction {
            // Add credential columns with default empty strings
            try await addColumnIfMissing("token", definition: "TEXT NOT NULL DEFAULT ''")
            try await addColumnIfMissing("authUrl", definition: "TEXT NOT NULL DEFAULT ''")
            try await addColumnIfMissing("httpApiUrl", definition: "TEXT NOT NULL DEFAULT ''")
            try await addColumnIfMissing("httpApiKey", definition: "TEXT NOT NULL DEFAULT ''")
            try await addColumnIfMissing("secretKey", definition: "TEXT NOT NULL DEFAULT ''")
            try await execute("PRAGMA user_version = 2")
        }

        Log.info("Schema version 2 migration complete: Credential columns added")
    }

    /// Migration to version 3: Add logLevel column to databaseConfigs table
    private func migrateToVersion3() async throws {
        Log.info("Migrating to schema version 3: Adding logLevel column")

        try await executeTransaction {
            try await addColumnIfMissing("logLevel", definition: "TEXT NOT NULL DEFAULT 'info'")
            try await execute("PRAGMA user_version = 3")
        }

        Log.info("Schema version 3 migration complete: logLevel column added")
    }

    /// Migration to version 4: Add isStrictModeEnabled column to databaseConfigs table
    private func migrateToVersion4() async throws {
        Log.info("Migrating to schema version 4: Adding isStrictModeEnabled column")

        try await executeTransaction {
            try await addColumnIfMissing("isStrictModeEnabled", definition: "INTEGER DEFAULT 0")
            try await execute("PRAGMA user_version = 4")
        }

        Log.info("Schema version 4 migration complete")
    }

    /// Migration to version 5: Add advanced configuration columns
    private func migrateToVersion5() async throws {
        Log.info("Migrating to schema version 5: Adding advanced configuration columns")

        try await executeTransaction {
            try await addColumnIfMissing("collectionSyncScopes", definition: "TEXT NOT NULL DEFAULT '[]'")
            try await addColumnIfMissing("startupSettings", definition: "TEXT NOT NULL DEFAULT '[]'")
            // Inside the transaction so the version and the columns land together.
            try await execute("PRAGMA user_version = 5")
        }

        Log.info("Schema version 5 migration complete: advanced configuration columns added")
    }

    /// Migration to version 6: Add multicast (beta) transport columns
    ///
    /// Existing rows default to multicast DISABLED with the SDK-default group/port
    /// (Ditto SDK 5.1.0 `peerToPeer.multicastBeta`), so an upgrade never silently
    /// changes a database's transport behavior.
    private func migrateToVersion6() async throws {
        Log.info("Migrating to schema version 6: Adding multicast transport columns")

        try await executeTransaction {
            try await addColumnIfMissing("isMulticastEnabled", definition: "INTEGER DEFAULT 0")
            try await addColumnIfMissing("multicastGroupAddress", definition: "TEXT NOT NULL DEFAULT '224.1.2.3'")
            try await addColumnIfMissing("multicastPort", definition: "INTEGER DEFAULT 6003")
            try await addColumnIfMissing("multicastInterfaceName", definition: "TEXT")
            // Inside the transaction so the version and the columns land together.
            try await execute("PRAGMA user_version = 6")
        }

        Log.info("Schema version 6 migration complete: multicast transport columns added")
    }

    /// True when `table` already has a column named `column`.
    private func columnExists(_ column: String, inTable table: String) async throws -> Bool {
        var found = false
        try await query("PRAGMA table_info(\(table))") { statement in
            // PRAGMA table_info columns: 0 = cid, 1 = name, 2 = type, …
            if let namePointer = sqlite3_column_text(statement, 1),
               String(cString: namePointer) == column
            {
                found = true
            }
        }
        return found
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

    /// Reads a TEXT column, falling back to `default` when the value is NULL.
    private static func text(_ statement: OpaquePointer?, _ index: Int32, default fallback: String) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return fallback }
        return String(cString: pointer)
    }

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
        // Credentials (stored in the clear — `docs/CREDENTIAL_STORAGE.md`)
        let token: String
        let authUrl: String
        let httpApiUrl: String
        let httpApiKey: String
        let secretKey: String
        /// Developer Options
        let logLevel: String
        let isStrictModeEnabled: Bool
        /// Advanced Configuration, stored as JSON text (see `DatabaseRepository` for
        /// the model bridging). Small, always read and written with the parent row,
        /// and never queried independently — hence columns rather than child tables.
        let collectionSyncScopes: String
        let startupSettings: String
        /// Multicast (beta) transport settings (schema v6+). Default: disabled with
        /// SDK-default group/port.
        let isMulticastEnabled: Bool
        let multicastGroupAddress: String
        let multicastPort: Int
        let multicastInterfaceName: String?

        // swiftformat:disable:next init
        init(
            _id: String, name: String, databaseId: String, mode: String,
            allowUntrustedCerts: Bool, isBluetoothLeEnabled: Bool, isLanEnabled: Bool,
            isAwdlEnabled: Bool, isCloudSyncEnabled: Bool,
            token: String, authUrl: String,
            httpApiUrl: String, httpApiKey: String, secretKey: String,
            logLevel: String, isStrictModeEnabled: Bool = false,
            collectionSyncScopes: String = "[]", startupSettings: String = "[]",
            isMulticastEnabled: Bool = false,
            multicastGroupAddress: String = MulticastConfig.defaultGroupAddress,
            multicastPort: Int = MulticastConfig.defaultPort,
            multicastInterfaceName: String? = nil
        ) {
            self._id = _id
            self.name = name
            self.databaseId = databaseId
            self.mode = mode
            self.allowUntrustedCerts = allowUntrustedCerts
            self.isBluetoothLeEnabled = isBluetoothLeEnabled
            self.isLanEnabled = isLanEnabled
            self.isAwdlEnabled = isAwdlEnabled
            self.isCloudSyncEnabled = isCloudSyncEnabled
            self.token = token
            self.authUrl = authUrl
            self.httpApiUrl = httpApiUrl
            self.httpApiKey = httpApiKey
            self.secretKey = secretKey
            self.logLevel = logLevel
            self.isStrictModeEnabled = isStrictModeEnabled
            self.collectionSyncScopes = collectionSyncScopes
            self.startupSettings = startupSettings
            self.isMulticastEnabled = isMulticastEnabled
            self.multicastGroupAddress = multicastGroupAddress
            self.multicastPort = multicastPort
            self.multicastInterfaceName = multicastInterfaceName
        }
    }

    func insertDatabaseConfig(_ config: DatabaseConfigRow) async throws {
        let sql = """
            INSERT INTO databaseConfigs (_id, name, databaseId, mode, allowUntrustedCerts,
                isBluetoothLeEnabled, isLanEnabled, isAwdlEnabled, isCloudSyncEnabled,
                token, authUrl, httpApiUrl, httpApiKey, secretKey, logLevel,
                isStrictModeEnabled, collectionSyncScopes, startupSettings,
                isMulticastEnabled, multicastGroupAddress, multicastPort, multicastInterfaceName)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            config.isCloudSyncEnabled ? 1 : 0,
            config.token,
            config.authUrl,
            config.httpApiUrl,
            config.httpApiKey,
            config.secretKey,
            config.logLevel,
            config.isStrictModeEnabled ? 1 : 0,
            config.collectionSyncScopes,
            config.startupSettings,
            config.isMulticastEnabled ? 1 : 0,
            config.multicastGroupAddress,
            config.multicastPort,
            config.multicastInterfaceName
        )
    }

    /// Updates every editable column of a database configuration.
    ///
    /// **`databaseId` is deliberately NOT in the `SET` list.** It is the parent key that
    /// `subscriptions`, `history`, `favorites` and `observables` reference with
    /// `FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE`
    /// and **no `ON UPDATE`** clause, while `PRAGMA foreign_keys = ON`. Reproduced on
    /// SQLite 3.50.6: updating the parent key with even one child row present raises
    /// `FOREIGN KEY constraint failed (19)` and changes nothing. Since every database
    /// that has ever run a query has a `history` row, including `databaseId` here meant
    /// editing it threw and **discarded the name, token and sync-scope edits submitted in
    /// the same save**.
    ///
    /// It also names the on-disk Ditto store directory
    /// (`DittoManager.localDirectoryPath` embeds `name-databaseId`), so changing the
    /// column without moving that directory would orphan the local data. Changing a
    /// database's identity is therefore a delete-and-re-register operation, and
    /// `DatabaseEditorView` disables the field for an existing config.
    func updateDatabaseConfig(_ config: DatabaseConfigRow) async throws {
        let sql = """
            UPDATE databaseConfigs
            SET name = ?, mode = ?, allowUntrustedCerts = ?,
                isBluetoothLeEnabled = ?, isLanEnabled = ?, isAwdlEnabled = ?, isCloudSyncEnabled = ?,
                token = ?, authUrl = ?, httpApiUrl = ?, httpApiKey = ?, secretKey = ?,
                logLevel = ?, isStrictModeEnabled = ?,
                collectionSyncScopes = ?, startupSettings = ?,
                isMulticastEnabled = ?, multicastGroupAddress = ?, multicastPort = ?,
                multicastInterfaceName = ?
            WHERE _id = ?
        """

        let changedRows = try await execute(
            sql,
            config.name,
            config.mode,
            config.allowUntrustedCerts ? 1 : 0,
            config.isBluetoothLeEnabled ? 1 : 0,
            config.isLanEnabled ? 1 : 0,
            config.isAwdlEnabled ? 1 : 0,
            config.isCloudSyncEnabled ? 1 : 0,
            config.token,
            config.authUrl,
            config.httpApiUrl,
            config.httpApiKey,
            config.secretKey,
            config.logLevel,
            config.isStrictModeEnabled ? 1 : 0,
            config.collectionSyncScopes,
            config.startupSettings,
            config.isMulticastEnabled ? 1 : 0,
            config.multicastGroupAddress,
            config.multicastPort,
            config.multicastInterfaceName,
            config._id
        )
        // `WHERE databaseId = ?` bound the NEW id, so editing a Database ID matched no
        // row and reported success — or, if it matched a DIFFERENT config's id, wrote
        // this config's name and credentials over that row. `_id` is the primary key and
        // is never edited. With `databaseId` also out of the SET list (see above), a
        // cross-row overwrite is now structurally impossible rather than merely rejected
        // by the UNIQUE index.
        //
        // The count comes back from `execute` itself rather than from a follow-up
        // `sqlite3_changes` read: that value is connection-wide, and reading it after the
        // statement was finalized only worked because nothing happened to run in between.
        guard changedRows == 1 else {
            throw SQLCipherError.queryFailed(
                sql: "updateDatabaseConfig",
                error: "no database configuration matched _id \(config._id)"
            )
        }
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
        let sql = """
            SELECT _id, name, databaseId, mode, allowUntrustedCerts, isBluetoothLeEnabled,
                   isLanEnabled, isAwdlEnabled, isCloudSyncEnabled,
                   token, authUrl, httpApiUrl, httpApiKey, secretKey, logLevel,
                   isStrictModeEnabled, collectionSyncScopes, startupSettings,
                   isMulticastEnabled, multicastGroupAddress, multicastPort, multicastInterfaceName
            FROM databaseConfigs
        """

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
                isCloudSyncEnabled: sqlite3_column_int(statement, 8) != 0,
                token: String(cString: sqlite3_column_text(statement, 9)),
                authUrl: String(cString: sqlite3_column_text(statement, 10)),
                httpApiUrl: String(cString: sqlite3_column_text(statement, 11)),
                httpApiKey: String(cString: sqlite3_column_text(statement, 12)),
                secretKey: String(cString: sqlite3_column_text(statement, 13)),
                logLevel: String(cString: sqlite3_column_text(statement, 14)),
                isStrictModeEnabled: sqlite3_column_int(statement, 15) != 0,
                // Defensive: `String(cString:)` traps on NULL. These columns are
                // NOT NULL with a default, but a hand-edited database shouldn't be
                // able to crash the app on launch.
                collectionSyncScopes: Self.text(statement, 16, default: "[]"),
                startupSettings: Self.text(statement, 17, default: "[]"),
                isMulticastEnabled: sqlite3_column_int(statement, 18) != 0,
                multicastGroupAddress: Self.text(statement, 19, default: MulticastConfig.defaultGroupAddress),
                multicastPort: Int(sqlite3_column_int(statement, 20)),
                // The only genuinely NULL-able column: NULL means "let the OS pick
                // the interface", which is distinct from the empty string.
                multicastInterfaceName: sqlite3_column_text(statement, 21).map { String(cString: $0) }
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
    }

    func insertSubscription(_ subscription: SubscriptionRow) async throws {
        let sql = "INSERT INTO subscriptions (_id, databaseId, name, query) VALUES (?, ?, ?, ?)"
        try await execute(sql, subscription._id, subscription.databaseId, subscription.name, subscription.query)
    }

    func getSubscriptions(databaseId: String) async throws -> [SubscriptionRow] {
        let sql = "SELECT _id, databaseId, name, query FROM subscriptions WHERE databaseId = ?"

        var results: [SubscriptionRow] = []
        try await query(sql, databaseId) { statement in
            results.append(SubscriptionRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                name: String(cString: sqlite3_column_text(statement, 2)),
                query: String(cString: sqlite3_column_text(statement, 3))
            ))
        }

        return results
    }

    func updateSubscription(_ subscription: SubscriptionRow) async throws {
        let sql = "UPDATE subscriptions SET name = ?, query = ? WHERE _id = ?"
        try await execute(sql, subscription.name, subscription.query, subscription._id)
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
        let isActive: Bool
        let lastUpdated: String?
    }

    func insertObservable(_ observable: ObservableRow) async throws {
        let sql = "INSERT INTO observables (_id, databaseId, name, query, isActive, lastUpdated) VALUES (?, ?, ?, ?, ?, ? )"
        try await execute(
            sql,
            observable._id,
            observable.databaseId,
            observable.name,
            observable.query,
            observable.isActive ? 1 : 0,
            observable.lastUpdated
        )
    }

    func updateObservable(_ observable: ObservableRow) async throws {
        let sql = "UPDATE observables SET name = ?, query = ?, isActive = ?, lastUpdated = ? WHERE _id = ?"
        try await execute(
            sql,
            observable.name,
            observable.query,
            observable.isActive ? 1 : 0,
            observable.lastUpdated,
            observable._id
        )
    }

    func getObservables(databaseId: String) async throws -> [ObservableRow] {
        let sql = "SELECT _id, databaseId, name, query, isActive, lastUpdated FROM observables WHERE databaseId = ?"

        var results: [ObservableRow] = []
        try await query(sql, databaseId) { statement in
            let lastUpdated = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 5))

            results.append(ObservableRow(
                _id: String(cString: sqlite3_column_text(statement, 0)),
                databaseId: String(cString: sqlite3_column_text(statement, 1)),
                name: String(cString: sqlite3_column_text(statement, 2)),
                query: String(cString: sqlite3_column_text(statement, 3)),
                isActive: sqlite3_column_int(statement, 4) != 0,
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
            _ = try? await execute("ROLLBACK")
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

    // MARK: - Testing Support

    /// Resets the service for testing (allows reinitialization with fresh database)
    /// **WARNING: Only use in tests!** This closes the database connection and resets state.
    func resetForTesting() async {
        closeConnection()
        _isInitialized = false
    }

    // MARK: - Test Support

    #if DEBUG
    /// Whether a connection handle is currently held.
    ///
    /// **Test-only**, and compiled out of Release. `db` is private and every legitimate
    /// caller goes through `initialize()` / `resetForTesting()`; this exists so a test can
    /// prove that a failed `initialize()` released its handle instead of leaking it, which
    /// is otherwise only observable as a slowly growing file-descriptor count.
    var hasOpenConnectionForTesting: Bool {
        db != nil
    }

    /// Runs a raw statement. **Test-only**, and compiled out of Release: used to build
    /// legacy (pre-migration) schema states and to corrupt stored values deliberately,
    /// neither of which the production API should expose against the credential store.
    func executeRawForTesting(_ sql: String, _ parameters: [Any?] = []) async throws {
        try await executeWithParameters(sql, parameters)
    }
    #endif

    // MARK: - Low-Level Execute/Query

    /// Executes a SQL statement without returning results.
    ///
    /// - Returns: the number of rows the statement changed. `sqlite3_step` returns
    ///   `SQLITE_DONE` for an UPDATE that matched nothing, so a caller that needs to
    ///   distinguish "wrote one row" from "silently did nothing" must check this.
    @discardableResult
    private func execute(_ sql: String, _ parameters: Any?...) async throws -> Int {
        try await executeWithParameters(sql, parameters)
    }

    /// Array-taking form, so both the variadic wrapper and the test seam share one body.
    ///
    /// - Returns: rows changed by this statement, read from `sqlite3_changes` **while the
    ///   statement is still alive** and before any suspension point. It used to be read
    ///   by a separate `changedRowCount()` helper called after this function returned —
    ///   i.e. after the `defer`-ed `sqlite3_finalize` — and `sqlite3_changes` is
    ///   connection-wide, so that was only correct because nothing on that path happened
    ///   to run another statement in between. Returning it here removes the ordering
    ///   assumption entirely.
    ///
    ///   For statements that are not INSERT/UPDATE/DELETE (`BEGIN`, `PRAGMA`,
    ///   `CREATE TABLE`, …) SQLite reports the count from the previous DML on this
    ///   connection. Every such caller ignores the result — hence `@discardableResult`.
    @discardableResult
    private func executeWithParameters(_ sql: String, _ parameters: [Any?]) async throws -> Int {
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
        return Int(sqlite3_changes(db))
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

    /// `isolated deinit` so the actor-isolated `db` handle can be closed safely on
    /// teardown. In practice this is a process-lifetime singleton that never
    /// deinitializes, but the isolation keeps it Swift 6 strict-concurrency clean.
    isolated deinit {
        if let db {
            sqlite3_close(db)
        }
    }
}

// MARK: - SQLCipherError

/// Storage failures surfaced to the user.
///
/// `LocalizedError` as well as `CustomStringConvertible` is load-bearing, not tidiness:
/// the NSError bridge does **not** consult `CustomStringConvertible`, so with only that
/// conformance every case rendered as "The operation couldn't be completed. (… error N.)"
/// at the two places these actually reach a person — `ContentView.sqlCipherInitErrorView`
/// (which reads `error.localizedDescription`) and the app-level alert in
/// `Ditto_Edge_StudioApp`, whose `else` branch catches everything that is not an
/// `AppError`. `keyFileUnreadable`'s explanation of why the key was *not* regenerated was
/// the most expensive casualty. `errorDescription` returns `description` so there is one
/// text, not two that can drift.
enum SQLCipherError: Error, CustomStringConvertible, LocalizedError {
    case databaseOpenFailed(code: Int32)
    case encryptionVerificationFailed(message: String)
    case pragmaFailed(pragma: String, error: String)
    case keyGenerationFailed
    /// The key file could not be written. Named for what it is: the `keychainSaveFailed`
    /// it replaced described a Keychain that has not been in this path for a long time,
    /// and since `LocalizedError` was added that wording reaches the user verbatim.
    case keyFileWriteFailed(code: Int32)
    /// The key file exists but cannot be read or parsed. Deliberately fatal: the alternative
    /// is regenerating the key, which is a data-loss event the moment the store is genuinely
    /// encrypted — and that regeneration path is what made stores unreadable on this
    /// repository before. While the store is plaintext (D1, option 3) nothing is actually at
    /// risk, so the guard is kept for the *code*, not for today's data: this is the one place
    /// that must never learn to rotate a key silently.
    case keyFileUnreadable(reason: String)
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
        case let .keyFileUnreadable(reason):
            return "The database key file could not be read (\(reason)). " +
                "It was not regenerated automatically, because rotating the key without " +
                "warning is unsafe for an encrypted store. Check the file's permissions " +
                "and integrity."
        case let .pragmaFailed(pragma, error):
            return "PRAGMA failed (\(pragma)): \(error)"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case let .keyFileWriteFailed(code):
            return "Failed to write the database key file (error code: \(code)). " +
                "Check that the app's Application Support directory is writable."
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

    /// What the NSError bridge — and therefore every `localizedDescription` render site —
    /// actually reads.
    var errorDescription: String? {
        description
    }
}
