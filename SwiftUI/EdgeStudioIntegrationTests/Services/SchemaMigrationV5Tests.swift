import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Exercises the real v4 → v5 migration.
///
/// The original idempotency test ran `migrateSchema(from: 4, to: 5)` against a database
/// `createSchema()` had already built at v5, so both `ALTER TABLE`s were skipped and the
/// migration SQL was never executed by any test. A typo in either column name — or a
/// removed transaction — would have shipped green while permanently bricking every
/// upgrading user's config database.
@Suite("Schema migration v4 → v5", .serialized)
struct SchemaMigrationV5Tests {
    /// Builds the exact v4 `databaseConfigs` table (16 columns, no advanced settings)
    /// and stamps `user_version = 4`.
    private func createVersion4Schema(_ service: SQLCipherService, rows: Int) async throws {
        try await service.executeRawForTesting("DROP TABLE IF EXISTS databaseConfigs")
        try await service.executeRawForTesting("""
            CREATE TABLE databaseConfigs (
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
                isStrictModeEnabled INTEGER DEFAULT 0
            )
        """)
        for index in 0 ..< rows {
            try await service.executeRawForTesting(
                """
                INSERT INTO databaseConfigs
                    (_id, name, databaseId, mode, allowUntrustedCerts, isBluetoothLeEnabled,
                     isLanEnabled, isAwdlEnabled, isCloudSyncEnabled, token, authUrl,
                     httpApiUrl, httpApiKey, secretKey, logLevel, isStrictModeEnabled)
                VALUES (?, ?, ?, 'development', 0, 1, 0, 1, 0, ?, ?, ?, ?, ?, 'debug', 1)
                """,
                [
                    "id-\(index)",
                    "Legacy DB \(index)",
                    "db-\(index)",
                    "token-\(index)",
                    "https://auth-\(index).example.com",
                    "https://api-\(index).example.com",
                    "key-\(index)",
                    "secret-\(index)"
                ]
            )
        }
        try await service.executeRawForTesting("PRAGMA user_version = 4")
    }

    @Test(.tags(.database))
    func `A real v4 database migrates without losing any field`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion4Schema(service, rows: 3)
            #expect(try await service.getSchemaVersion() == 4)

            // ACT — the migration under test.
            try await service.migrateSchema(from: 4, to: 5)

            // ASSERT — version bumped, rows intact, new columns defaulted.
            #expect(try await service.getSchemaVersion() == 5)
            let rows = try await service.getAllDatabaseConfigs().sorted { $0.databaseId < $1.databaseId }
            #expect(rows.count == 3)
            for (index, row) in rows.enumerated() {
                #expect(row._id == "id-\(index)")
                #expect(row.name == "Legacy DB \(index)")
                #expect(row.mode == "development")
                #expect(row.token == "token-\(index)")
                #expect(row.authUrl == "https://auth-\(index).example.com")
                #expect(row.httpApiUrl == "https://api-\(index).example.com")
                #expect(row.httpApiKey == "key-\(index)")
                #expect(row.secretKey == "secret-\(index)")
                #expect(row.logLevel == "debug")
                #expect(row.isStrictModeEnabled)
                #expect(row.isLanEnabled == false)
                #expect(row.isCloudSyncEnabled == false)
                #expect(row.isBluetoothLeEnabled)
                #expect(row.isAwdlEnabled)
                // The new columns.
                #expect(row.collectionSyncScopes == "[]")
                #expect(row.startupSettings == "[]")
            }
        }
    }

    /// The half-migrated state the transaction and the `table_info` guards exist for:
    /// one column already added, `user_version` still 4. Re-running used to raise
    /// "duplicate column name", which made `initialize()` throw on every subsequent
    /// launch — permanently locking the user out of all configs and credentials.
    @Test(.tags(.database))
    func `A half-applied v5 migration completes instead of failing`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion4Schema(service, rows: 1)

            // ARRANGE — simulate dying between the two ALTER TABLE statements.
            try await service.executeRawForTesting(
                "ALTER TABLE databaseConfigs ADD COLUMN collectionSyncScopes TEXT NOT NULL DEFAULT '[]'"
            )
            #expect(try await service.getSchemaVersion() == 4)

            // ACT
            try await service.migrateSchema(from: 4, to: 5)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 5)
            let rows = try await service.getAllDatabaseConfigs()
            #expect(rows.count == 1)
            #expect(rows[0].startupSettings == "[]")
        }
    }

    @Test(.tags(.database))
    func `Migrating twice is a no-op`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion4Schema(service, rows: 2)

            // ACT
            try await service.migrateSchema(from: 4, to: 5)
            try await service.migrateSchema(from: 4, to: 5)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 5)
            #expect(try await service.getAllDatabaseConfigs().count == 2)
        }
    }

    /// Advanced settings written by the repository survive the round trip through the
    /// migrated columns.
    @Test(.tags(.database))
    func `Advanced settings persist after migrating a v4 database`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion4Schema(service, rows: 0)
            try await service.migrateSchema(from: 4, to: 5)

            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            config.collectionSyncScopes = [
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
            ]
            config.startupSettings = [
                StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
            ]

            // ACT
            try await repo.addDittoAppConfig(config)
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded.count == 1)
            #expect(loaded[0].collectionSyncScopes == config.collectionSyncScopes)
            #expect(loaded[0].startupSettings == config.startupSettings)
        }
    }

    /// Builds a v1 table (no credential columns at all) so the full 1 → 5 chain runs.
    private func createVersion1Schema(_ service: SQLCipherService) async throws {
        try await service.executeRawForTesting("DROP TABLE IF EXISTS databaseConfigs")
        try await service.executeRawForTesting("""
            CREATE TABLE databaseConfigs (
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
        try await service.executeRawForTesting(
            """
            INSERT INTO databaseConfigs
                (_id, name, databaseId, mode, allowUntrustedCerts, isBluetoothLeEnabled,
                 isLanEnabled, isAwdlEnabled, isCloudSyncEnabled)
            VALUES ('id-v1', 'Ancient DB', 'db-v1', 'development', 0, 1, 1, 1, 1)
            """
        )
        try await service.executeRawForTesting("PRAGMA user_version = 1")
    }

    /// The whole 1 → 5 chain. Only `from: 4` was covered before, so migrations 2-4 were
    /// never executed by any test even after being made transactional.
    @Test(.tags(.database))
    func `A v1 database migrates all the way to v5`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion1Schema(service)

            // ACT
            try await service.migrateSchema(from: 1, to: 5)

            // ASSERT — every column added along the way is present and the row survived.
            #expect(try await service.getSchemaVersion() == 5)
            let rows = try await service.getAllDatabaseConfigs()
            #expect(rows.count == 1)
            #expect(rows[0].name == "Ancient DB")
            #expect(rows[0].token == "")
            #expect(rows[0].logLevel == "info")
            #expect(rows[0].isStrictModeEnabled == false)
            #expect(rows[0].collectionSyncScopes == "[]")
            #expect(rows[0].startupSettings == "[]")
        }
    }

    /// Each step stamps its own version inside its own transaction, so an interrupted
    /// chain resumes instead of hitting "duplicate column name" forever.
    @Test(.tags(.database))
    func `An interrupted v1 chain resumes from where it stopped`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion1Schema(service)

            // ARRANGE — simulate dying after the v2 step committed.
            try await service.migrateSchema(from: 1, to: 2)
            #expect(try await service.getSchemaVersion() == 2)

            // ACT — resume from the version actually stored.
            try await service.migrateSchema(from: 2, to: 5)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 5)
            #expect(try await service.getAllDatabaseConfigs().count == 1)
        }
    }

    /// Re-running the full chain over an already-migrated database must be a no-op, not
    /// a duplicate-column failure.
    @Test(.tags(.database))
    func `Re-running the whole chain is idempotent`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion1Schema(service)

            // ACT
            try await service.migrateSchema(from: 1, to: 5)
            try await service.migrateSchema(from: 1, to: 5)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 5)
            #expect(try await service.getAllDatabaseConfigs().count == 1)
        }
    }
}
