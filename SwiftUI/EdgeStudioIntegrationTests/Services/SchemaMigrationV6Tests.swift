import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Exercises the real v5 → v6 migration (multicast transport columns).
///
/// Modeled on `SchemaMigrationV5Tests`: the migration SQL is executed against a
/// hand-built v5 table so a typo in a column name — or a removed transaction —
/// fails loudly here instead of bricking an upgrading user's config database.
@Suite("Schema migration v5 → v6", .serialized)
struct SchemaMigrationV6Tests {
    /// Builds the exact v5 `databaseConfigs` table (18 columns, no multicast
    /// columns) and stamps `user_version = 5`.
    private func createVersion5Schema(_ service: SQLCipherService, rows: Int) async throws {
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
                isStrictModeEnabled INTEGER DEFAULT 0,
                collectionSyncScopes TEXT NOT NULL DEFAULT '[]',
                startupSettings TEXT NOT NULL DEFAULT '[]'
            )
        """)
        for index in 0 ..< rows {
            try await service.executeRawForTesting(
                """
                INSERT INTO databaseConfigs
                    (_id, name, databaseId, mode, allowUntrustedCerts, isBluetoothLeEnabled,
                     isLanEnabled, isAwdlEnabled, isCloudSyncEnabled, token, authUrl,
                     httpApiUrl, httpApiKey, secretKey, logLevel, isStrictModeEnabled,
                     collectionSyncScopes, startupSettings)
                VALUES (?, ?, ?, 'development', 0, 1, 1, 1, 1, ?, ?, ?, ?, ?, 'info', 0, '[]', '[]')
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
        try await service.executeRawForTesting("PRAGMA user_version = 5")
    }

    @Test(.tags(.database))
    func `A real v5 database migrates with multicast disabled and SDK defaults`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion5Schema(service, rows: 3)
            #expect(try await service.getSchemaVersion() == 5)

            // ACT — the migration under test.
            try await service.migrateSchema(from: 5, to: 6)

            // ASSERT — version bumped, rows intact, multicast columns defaulted.
            #expect(try await service.getSchemaVersion() == 6)
            let rows = try await service.getAllDatabaseConfigs().sorted { $0.databaseId < $1.databaseId }
            #expect(rows.count == 3)
            for (index, row) in rows.enumerated() {
                #expect(row._id == "id-\(index)")
                #expect(row.name == "Legacy DB \(index)")
                #expect(row.token == "token-\(index)")
                // The new columns: upgrading must never silently enable the beta
                // transport.
                #expect(row.isMulticastEnabled == false)
                #expect(row.multicastGroupAddress == "224.1.2.3")
                #expect(row.multicastPort == 6003)
                #expect(row.multicastInterfaceName == nil)
            }
        }
    }

    /// Same half-applied guard as v5: one column added, `user_version` still 5 —
    /// re-running must complete instead of raising "duplicate column name".
    @Test(.tags(.database))
    func `A half-applied v6 migration completes instead of failing`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion5Schema(service, rows: 1)

            // ARRANGE — simulate dying between two ALTER TABLE statements.
            try await service.executeRawForTesting(
                "ALTER TABLE databaseConfigs ADD COLUMN isMulticastEnabled INTEGER DEFAULT 0"
            )
            #expect(try await service.getSchemaVersion() == 5)

            // ACT
            try await service.migrateSchema(from: 5, to: 6)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 6)
            let rows = try await service.getAllDatabaseConfigs()
            #expect(rows.count == 1)
            #expect(rows[0].multicastGroupAddress == "224.1.2.3")
        }
    }

    @Test(.tags(.database))
    func `Migrating twice is a no-op`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion5Schema(service, rows: 2)

            // ACT
            try await service.migrateSchema(from: 5, to: 6)
            try await service.migrateSchema(from: 5, to: 6)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 6)
            #expect(try await service.getAllDatabaseConfigs().count == 2)
        }
    }

    /// Multicast settings written by the repository survive the round trip through
    /// the migrated columns.
    @Test(.tags(.database))
    func `Multicast settings persist after migrating a v5 database`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            try await createVersion5Schema(service, rows: 0)
            try await service.migrateSchema(from: 5, to: 6)

            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            config.isMulticastEnabled = true
            config.multicastGroupAddress = "239.1.2.3"
            config.multicastPort = 7000
            config.multicastInterfaceName = "en0"

            // ACT
            try await repo.addDittoAppConfig(config)
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded.count == 1)
            #expect(loaded[0].isMulticastEnabled)
            #expect(loaded[0].multicastGroupAddress == "239.1.2.3")
            #expect(loaded[0].multicastPort == 7000)
            #expect(loaded[0].multicastInterfaceName == "en0")
        }
    }

    /// A v1 database runs the whole 1 → 6 chain and ends with multicast defaults.
    @Test(.tags(.database))
    func `A v1 database migrates all the way to v6`() async throws {
        try await TestHelpers.withFreshDatabase {
            let service = SQLCipherContext.current
            // v1 table: no credential columns at all (same fixture as the v5 tests).
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

            // ACT
            try await service.migrateSchema(from: 1, to: 6)

            // ASSERT
            #expect(try await service.getSchemaVersion() == 6)
            let rows = try await service.getAllDatabaseConfigs()
            #expect(rows.count == 1)
            #expect(rows[0].name == "Ancient DB")
            #expect(rows[0].collectionSyncScopes == "[]")
            #expect(rows[0].isMulticastEnabled == false)
            #expect(rows[0].multicastPort == 6003)
        }
    }
}
