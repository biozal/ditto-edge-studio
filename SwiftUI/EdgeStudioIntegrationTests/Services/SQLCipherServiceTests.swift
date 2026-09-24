import Testing
@testable import Ditto_Edge_Studio

/// Comprehensive test suite for SQLCipherService
///
/// Tests cover:
/// - Encryption key management
/// - Database initialization
/// - Schema creation and versioning
/// - Schema migration (v1 → v2)
/// - CRUD operations for database configs
/// - Transaction support and rollback
/// - Error handling
///
/// Each test uses a fresh database instance with cleanup
/// Target: 95% code coverage
@Suite("SQLCipher Service Tests")
struct SQLCipherServiceTests {
    // MARK: - Initialization & Encryption Tests

    @Suite("Initialization & Encryption")
    struct InitializationTests {
        @Test(.tags(.database, .encryption))
        func `Service initializes successfully`() async throws {
            try await TestHelpers.withUninitializedDatabase {
                let service = SQLCipherContext.current

                // Service should initialize without errors
                try await service.initialize()

                // Should be able to query. Proves the connection opened and the schema is
                // usable — not that anything is encrypted (`docs/CREDENTIAL_STORAGE.md`).
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty) // Fresh database
            }
        }

        @Test(.tags(.encryption))
        func `Encryption key is generated and stored`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                // Key was generated during initialize() — retrieve and verify length
                let key = try await service.getOrCreateEncryptionKey()
                #expect(key.count == 64) // 256-bit hex key
            }
        }

        @Test(.tags(.encryption))
        func `Encryption key persists across reinitializations`() async throws {
            try await TestHelpers.withUninitializedDatabase {
                let service = SQLCipherContext.current
                // First initialization — generates key
                try await service.initialize()
                let key1 = try await service.getOrCreateEncryptionKey()
                // Reset service (close DB connection)
                await service.resetForTesting()
                // Re-initialize — should load same key from file
                try await service.initialize()
                let key2 = try await service.getOrCreateEncryptionKey()
                #expect(key1 == key2)
            }
        }
    }

    // MARK: - Schema Tests

    @Suite("Schema Management")
    struct SchemaTests {
        @Test(.tags(.database))
        func `Fresh database creates schema version 6`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let version = try await service.getSchemaVersion()
                #expect(version == 6) // Current schema version
            }
        }

        /// The v5 migration adds two columns and bumps `user_version` inside one
        /// transaction, and each `ALTER TABLE` is skipped when the column already
        /// exists. Re-running it must therefore be a no-op rather than a "duplicate
        /// column name" error — which would otherwise make `initialize()` throw on
        /// every subsequent launch and lock the user out of all stored configs.
        @Test(.tags(.database))
        func `Re-running the v5 migration is idempotent`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // ARRANGE — a config written under the current schema.
                let config = DatabaseConfigFixtures.validServerConfig()
                try await DatabaseRepository.shared.addDittoAppConfig(config)

                // ACT — force the migration to run again over an already-migrated DB.
                try await service.migrateSchema(from: 4, to: 5)

                // ASSERT — still readable, still version 5.
                #expect(try await service.getSchemaVersion() == 5)
                let rows = try await service.getAllDatabaseConfigs()
                #expect(rows.count == 1)
                #expect(rows[0].collectionSyncScopes == "[]")
                #expect(rows[0].startupSettings == "[]")
            }
        }

        /// Advanced settings persist through the new JSON columns.
        @Test(.tags(.database))
        func `Advanced settings round-trip through the v5 columns`() async throws {
            try await TestHelpers.withFreshDatabase {
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                config.collectionSyncScopes = [
                    CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
                    CollectionSyncScope(collection: "audit", scope: .smallPeersOnly)
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

        /// Regression guard for the trap that already bit `logLevel`: saving an
        /// unrelated field must not wipe the advanced settings.
        @Test(.tags(.database))
        func `Updating an unrelated field preserves sync scopes`() async throws {
            try await TestHelpers.withFreshDatabase {
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                config.collectionSyncScopes = [
                    CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
                ]
                try await repo.addDittoAppConfig(config)

                // ACT — change only the name, the way the editor's Save does.
                config.name = "Renamed"
                try await repo.updateDittoAppConfig(config)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded[0].name == "Renamed")
                #expect(loaded[0].collectionSyncScopes == [
                    CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
                ])
            }
        }

        @Test(.tags(.database))
        func `Database has all required tables`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Query to verify tables exist
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty) // Proves databaseConfigs table exists
            }
        }

        @Test(.tags(.database))
        func `Database configs table has credential columns`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Insert a config with credentials
                let config = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(),
                    name: "Test DB",
                    databaseId: "test-db-id",
                    mode: "server",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: true,
                    token: "test-token",
                    authUrl: "https://auth.test.com",
                    httpApiUrl: "https://api.test.com",
                    httpApiKey: "test-api-key",
                    secretKey: "test-secret", logLevel: "info"
                )

                try await service.insertDatabaseConfig(config)

                // Retrieve and verify credentials are stored
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)
                #expect(configs[0].token == "test-token")
                #expect(configs[0].authUrl == "https://auth.test.com")
                #expect(configs[0].httpApiUrl == "https://api.test.com")
                #expect(configs[0].httpApiKey == "test-api-key")
                #expect(configs[0].secretKey == "test-secret")
            }
        }
    }

    // MARK: - CRUD Tests

    @Suite("Database Config CRUD Operations")
    struct CRUDTests {
        @Test(.tags(.database))
        func `Insert database config stores all fields`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let config = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(),
                    name: "Test Database",
                    databaseId: "db-test-123",
                    mode: "server",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: false,
                    isCloudSyncEnabled: true,
                    token: "my-token",
                    authUrl: "https://auth.example.com",
                    httpApiUrl: "https://api.example.com",
                    httpApiKey: "api-key-123",
                    secretKey: "", logLevel: "info"
                )

                try await service.insertDatabaseConfig(config)

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)
                #expect(configs[0]._id == config._id)
                #expect(configs[0].name == "Test Database")
                #expect(configs[0].databaseId == "db-test-123")
                #expect(configs[0].token == "my-token")
            }
        }

        @Test(.tags(.database))
        func `Insert multiple configs stores all`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Insert 3 configs
                for i in 1 ... 3 {
                    let config = SQLCipherService.DatabaseConfigRow(
                        _id: TestHelpers.uniqueTestId(),
                        name: "Database \(i)",
                        databaseId: "db-\(i)",
                        mode: "server",
                        allowUntrustedCerts: false,
                        isBluetoothLeEnabled: true,
                        isLanEnabled: true,
                        isAwdlEnabled: true,
                        isCloudSyncEnabled: true,
                        token: "token-\(i)",
                        authUrl: "https://auth\(i).com",
                        httpApiUrl: "https://api\(i).com",
                        httpApiKey: "key-\(i)",
                        secretKey: "", logLevel: "info"
                    )
                    try await service.insertDatabaseConfig(config)
                }

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 3)
            }
        }

        @Test(.tags(.database))
        func `Update config changes all fields`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Insert initial config
                let id = TestHelpers.uniqueTestId()
                let initialConfig = SQLCipherService.DatabaseConfigRow(
                    _id: id,
                    name: "Original Name",
                    databaseId: "db-original",
                    mode: "server",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: true,
                    token: "original-token",
                    authUrl: "https://original.com",
                    httpApiUrl: "https://original-api.com",
                    httpApiKey: "original-key",
                    secretKey: "", logLevel: "info"
                )
                try await service.insertDatabaseConfig(initialConfig)

                // Update config
                let updatedConfig = SQLCipherService.DatabaseConfigRow(
                    _id: id,
                    name: "Updated Name",
                    databaseId: "db-original",
                    mode: "smallPeersOnly",
                    allowUntrustedCerts: true,
                    isBluetoothLeEnabled: false,
                    isLanEnabled: false,
                    isAwdlEnabled: false,
                    isCloudSyncEnabled: false,
                    token: "updated-token",
                    authUrl: "https://updated.com",
                    httpApiUrl: "https://updated-api.com",
                    httpApiKey: "updated-key",
                    secretKey: "new-secret", logLevel: "info"
                )
                try await service.updateDatabaseConfig(updatedConfig)

                // Verify changes
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)
                #expect(configs[0].name == "Updated Name")
                #expect(configs[0].mode == "smallPeersOnly")
                #expect(configs[0].token == "updated-token")
                #expect(configs[0].secretKey == "new-secret")
            }
        }

        @Test(.tags(.database))
        func `Delete config removes entry`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Insert config
                let config = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(),
                    name: "To Delete",
                    databaseId: "db-delete",
                    mode: "server",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: true,
                    token: "token",
                    authUrl: "https://auth.com",
                    httpApiUrl: "https://api.com",
                    httpApiKey: "key",
                    secretKey: "", logLevel: "info"
                )
                try await service.insertDatabaseConfig(config)

                // Verify it exists
                var configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)

                // Delete it
                try await service.deleteDatabaseConfig(databaseId: "db-delete")

                // Verify it's gone
                configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty)
            }
        }

        @Test(.tags(.database))
        func `Get all configs returns empty for fresh database`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty)
            }
        }
    }

    // MARK: - Credential Storage Tests

    @Suite("Credential Storage")
    struct CredentialTests {
        /// Round-trips credentials through the local store.
        ///
        /// **This test cannot and does not prove encryption.** It writes strings and reads
        /// the same strings back, which is equally true of a plaintext file — and the store
        /// *is* plaintext (`docs/CREDENTIAL_STORAGE.md`). It was named
        /// `Credentials stored encrypted at rest`, which made the suite look like evidence
        /// for a property nothing in the codebase provides. Proving encryption would mean
        /// asserting on the bytes on disk — that the file does not begin with
        /// `SQLite format 3` and that `super-secret-token` does not appear in it — and that
        /// assertion would fail today.
        @Test(.tags(.database))
        func `Credentials round-trip through the local store`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Insert config with sensitive credentials
                let config = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(),
                    name: "Secure DB",
                    databaseId: "db-secure",
                    mode: "server",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: true,
                    token: "super-secret-token",
                    authUrl: "https://secure-auth.com",
                    httpApiUrl: "https://secure-api.com",
                    httpApiKey: "super-secret-api-key",
                    secretKey: "super-secret-key", logLevel: "info"
                )
                try await service.insertDatabaseConfig(config)

                // Verify credentials can be retrieved. Proves persistence and column
                // mapping — nothing about confidentiality.
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs[0].token == "super-secret-token")
                #expect(configs[0].httpApiKey == "super-secret-api-key")
                #expect(configs[0].secretKey == "super-secret-key")
            }
        }

        @Test(.tags(.database))
        func `Empty credentials stored correctly`() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let config = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(),
                    name: "Offline DB",
                    databaseId: "db-offline",
                    mode: "smallPeersOnly",
                    allowUntrustedCerts: false,
                    isBluetoothLeEnabled: true,
                    isLanEnabled: true,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: false,
                    token: "",
                    authUrl: "",
                    httpApiUrl: "",
                    httpApiKey: "",
                    secretKey: "", logLevel: "info"
                )
                try await service.insertDatabaseConfig(config)

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs[0].token == "")
                #expect(configs[0].authUrl == "")
                #expect(configs[0].secretKey == "")
            }
        }
    }

    // MARK: - History CRUD Tests

    @Suite("History CRUD Operations")
    struct HistoryCRUDTests {
        @Test(.tags(.database, .repository))
        func `Insert history stores entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-db-\(UUID().uuidString)"
                // Insert parent DatabaseConfigRow to satisfy FK constraint
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT * FROM cars",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await service.insertHistory(row)

                // ASSERT
                let rows = try await service.getHistory(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0]._id == row._id)
                #expect(rows[0].query == "SELECT * FROM cars")
                #expect(rows[0].databaseId == dbId)
            }
        }

        @Test(.tags(.database, .repository))
        func `Get history returns entries ordered by date descending`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-order-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let firstRow = SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT 1",
                    createdDate: "2024-01-01T00:00:00Z"
                )
                let secondRow = SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT 2",
                    createdDate: "2024-06-01T00:00:00Z"
                )

                // ACT
                try await service.insertHistory(firstRow)
                try await service.insertHistory(secondRow)

                // ASSERT — most recent first
                let rows = try await service.getHistory(databaseId: dbId)
                #expect(rows.count == 2)
                #expect(rows[0].query == "SELECT 2")
                #expect(rows[1].query == "SELECT 1")
            }
        }

        @Test(.tags(.database, .repository))
        func `Delete history removes entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT * FROM orders",
                    createdDate: Date().ISO8601Format()
                )
                try await service.insertHistory(row)

                // ACT
                try await service.deleteHistory(id: row._id)

                // ASSERT
                let rows = try await service.getHistory(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.database, .repository))
        func `Delete all history removes all entries for database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                for i in 1 ... 3 {
                    let row = SQLCipherService.HistoryRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        query: "SELECT \(i)",
                        createdDate: Date().ISO8601Format()
                    )
                    try await service.insertHistory(row)
                }

                // ACT
                try await service.deleteAllHistory(databaseId: dbId)

                // ASSERT
                let rows = try await service.getHistory(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.database, .repository))
        func `History is scoped per database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "hist-scope-1-\(UUID().uuidString)"
                let dbId2 = "hist-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertHistory(SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId1,
                    query: "SELECT * FROM db1", createdDate: Date().ISO8601Format()
                ))
                try await service.insertHistory(SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId2,
                    query: "SELECT * FROM db2", createdDate: Date().ISO8601Format()
                ))

                // ACT & ASSERT
                let rows1 = try await service.getHistory(databaseId: dbId1)
                let rows2 = try await service.getHistory(databaseId: dbId2)
                #expect(rows1.count == 1)
                #expect(rows1[0].query == "SELECT * FROM db1")
                #expect(rows2.count == 1)
                #expect(rows2[0].query == "SELECT * FROM db2")
            }
        }
    }

    // MARK: - Favorites CRUD Tests

    @Suite("Favorites CRUD Operations")
    struct FavoritesCRUDTests {
        @Test(.tags(.database, .repository))
        func `Insert favorite stores entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-db-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.FavoriteRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT * FROM users",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await service.insertFavorite(row)

                // ASSERT
                let rows = try await service.getFavorites(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0]._id == row._id)
                #expect(rows[0].query == "SELECT * FROM users")
            }
        }

        @Test(.tags(.database, .repository))
        func `Get favorites returns multiple entries`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-multi-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                for i in 1 ... 4 {
                    let row = SQLCipherService.FavoriteRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        query: "SELECT \(i) FROM table\(i)",
                        createdDate: Date().ISO8601Format()
                    )
                    try await service.insertFavorite(row)
                }

                // ACT
                let rows = try await service.getFavorites(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 4)
            }
        }

        @Test(.tags(.database, .repository))
        func `Delete favorite removes entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.FavoriteRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    query: "SELECT * FROM products",
                    createdDate: Date().ISO8601Format()
                )
                try await service.insertFavorite(row)

                // ACT
                try await service.deleteFavorite(id: row._id)

                // ASSERT
                let rows = try await service.getFavorites(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.database, .repository))
        func `Favorites are scoped per database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "fav-scope-1-\(UUID().uuidString)"
                let dbId2 = "fav-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertFavorite(SQLCipherService.FavoriteRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId1,
                    query: "Q1", createdDate: Date().ISO8601Format()
                ))
                try await service.insertFavorite(SQLCipherService.FavoriteRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId2,
                    query: "Q2", createdDate: Date().ISO8601Format()
                ))

                // ACT & ASSERT
                let rows1 = try await service.getFavorites(databaseId: dbId1)
                let rows2 = try await service.getFavorites(databaseId: dbId2)
                #expect(rows1.count == 1)
                #expect(rows2.count == 1)
                #expect(rows1[0].query == "Q1")
                #expect(rows2[0].query == "Q2")
            }
        }
    }

    // MARK: - Subscriptions CRUD Tests

    @Suite("Subscriptions CRUD Operations")
    struct SubscriptionsCRUDTests {
        @Test(.tags(.database, .repository))
        func `Insert subscription stores entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // First insert a database config so foreign key constraint is satisfied
                let dbId = "sub-db-\(UUID().uuidString)"
                let dbConfig = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "Test DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                )
                try await service.insertDatabaseConfig(dbConfig)

                let row = SQLCipherService.SubscriptionRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "All Cars",
                    query: "SELECT * FROM cars"
                )

                // ACT
                try await service.insertSubscription(row)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0]._id == row._id)
                #expect(rows[0].name == "All Cars")
                #expect(rows[0].query == "SELECT * FROM cars")
            }
        }

        @Test(.tags(.database, .repository))
        func `Delete subscription removes entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "sub-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.SubscriptionRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "To Delete",
                    query: "SELECT * FROM items"
                )
                try await service.insertSubscription(row)

                // ACT
                try await service.deleteSubscription(id: row._id)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.database, .repository))
        func `Get all subscriptions returns entries for database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "sub-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                for i in 1 ... 3 {
                    let row = SQLCipherService.SubscriptionRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        name: "Sub \(i)",
                        query: "SELECT \(i)"
                    )
                    try await service.insertSubscription(row)
                }

                // ACT
                let rows = try await service.getSubscriptions(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 3)
            }
        }
    }

    // MARK: - Observables CRUD Tests

    @Suite("Observables CRUD Operations")
    struct ObservablesCRUDTests {
        @Test(.tags(.database, .repository))
        func `Insert observable stores entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-db-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "Cars Observer",
                    query: "SELECT * FROM cars",
                    isActive: true,
                    lastUpdated: nil
                )

                // ACT
                try await service.insertObservable(row)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0]._id == row._id)
                #expect(rows[0].name == "Cars Observer")
                #expect(rows[0].isActive == true)
            }
        }

        @Test(.tags(.database, .repository))
        func `Get all observables returns entries for database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                for i in 1 ... 3 {
                    let row = SQLCipherService.ObservableRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        name: "Observer \(i)",
                        query: "SELECT \(i)",
                        isActive: true,
                        lastUpdated: nil
                    )
                    try await service.insertObservable(row)
                }

                // ACT
                let rows = try await service.getObservables(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 3)
            }
        }

        @Test(.tags(.database, .repository))
        func `Delete observable removes entry`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let row = SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "To Delete",
                    query: "SELECT * FROM items",
                    isActive: false,
                    lastUpdated: nil
                )
                try await service.insertObservable(row)

                // ACT
                try await service.deleteObservable(id: row._id)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.database, .repository))
        func `Update observable changes fields`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-upd-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let id = TestHelpers.uniqueTestId()
                let original = SQLCipherService.ObservableRow(
                    _id: id, databaseId: dbId, name: "Original",
                    query: "SELECT 1", isActive: false, lastUpdated: nil
                )
                try await service.insertObservable(original)

                let updated = SQLCipherService.ObservableRow(
                    _id: id, databaseId: dbId, name: "Updated",
                    query: "SELECT 2", isActive: true, lastUpdated: "2026-01-01T00:00:00Z"
                )

                // ACT
                try await service.updateObservable(updated)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0].name == "Updated")
                #expect(rows[0].query == "SELECT 2")
                #expect(rows[0].isActive == true)
            }
        }

        @Test(.tags(.database, .repository))
        func `Observables are scoped per database`() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "obs-scope-1-\(UUID().uuidString)"
                let dbId2 = "obs-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId1, name: "Obs1",
                    query: "Q1", isActive: true, lastUpdated: nil
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId2, name: "Obs2",
                    query: "Q2", isActive: true, lastUpdated: nil
                ))

                // ACT & ASSERT
                let rows1 = try await service.getObservables(databaseId: dbId1)
                let rows2 = try await service.getObservables(databaseId: dbId2)
                #expect(rows1.count == 1)
                #expect(rows2.count == 1)
                #expect(rows1[0].name == "Obs1")
                #expect(rows2[0].name == "Obs2")
            }
        }
    }

    // MARK: - Test Isolation Tests

    @Suite("Test Isolation")
    struct IsolationTests {
        @Test(.tags(.database))
        func `withFreshDatabase provides task-local isolated service`() async throws {
            try await TestHelpers.withFreshDatabase {
                let taskLocalService = SQLCipherContext.current
                // Task-local service is a different instance from the production singleton
                #expect(ObjectIdentifier(taskLocalService) != ObjectIdentifier(SQLCipherService.shared))
            }
        }

        @Test(.tags(.database))
        func `Separate withFreshDatabase calls start with empty databases`() async throws {
            let dbId = "isolation-test-\(UUID().uuidString)"
            let configId = TestHelpers.uniqueTestId()

            // First scope: insert a config
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: configId, name: "IsolationDB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)
            }

            // Second scope: separate database — previous data is gone
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty, "Each withFreshDatabase call starts with an empty database")
            }
        }
    }
}
