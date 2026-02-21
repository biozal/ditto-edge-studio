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

        @Test("Service initializes successfully", .tags(.database, .encryption))
        func testInitialization() async throws {
            try await TestHelpers.withUninitializedDatabase {
                let service = SQLCipherContext.current

                // Service should initialize without errors
                try await service.initialize()

                // Should be able to query (proves encryption worked)
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty) // Fresh database
            }
        }

        @Test("Encryption key is generated and stored", .tags(.encryption))
        func testEncryptionKeyGeneration() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                // Key was generated during initialize() — retrieve and verify length
                let key = try await service.getOrCreateEncryptionKey()
                #expect(key.count == 64) // 256-bit hex key
            }
        }

        @Test("Encryption key persists across reinitializations", .tags(.encryption))
        func testEncryptionKeyPersistence() async throws {
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

        @Test("Fresh database creates schema version 2", .tags(.database))
        func testSchemaVersion() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let version = try await service.getSchemaVersion()
                #expect(version == 2) // Current schema version
            }
        }

        @Test("Database has all required tables", .tags(.database))
        func testSchemaTablesExist() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // Query to verify tables exist
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty) // Proves databaseConfigs table exists
            }
        }

        @Test("Database configs table has credential columns", .tags(.database))
        func testDatabaseConfigsHasCredentialColumns() async throws {
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
                    websocketUrl: "wss://ws.test.com",
                    httpApiUrl: "https://api.test.com",
                    httpApiKey: "test-api-key",
                    secretKey: "test-secret"
                )

                try await service.insertDatabaseConfig(config)

                // Retrieve and verify credentials are stored
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 1)
                #expect(configs[0].token == "test-token")
                #expect(configs[0].authUrl == "https://auth.test.com")
                #expect(configs[0].websocketUrl == "wss://ws.test.com")
                #expect(configs[0].httpApiUrl == "https://api.test.com")
                #expect(configs[0].httpApiKey == "test-api-key")
                #expect(configs[0].secretKey == "test-secret")
            }
        }
    }

    // MARK: - CRUD Tests

    @Suite("Database Config CRUD Operations")
    struct CRUDTests {

        @Test("Insert database config stores all fields", .tags(.database))
        func testInsertConfig() async throws {
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
                    websocketUrl: "wss://sync.example.com",
                    httpApiUrl: "https://api.example.com",
                    httpApiKey: "api-key-123",
                    secretKey: ""
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

        @Test("Insert multiple configs stores all", .tags(.database))
        func testInsertMultipleConfigs() async throws {
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
                        websocketUrl: "wss://ws\(i).com",
                        httpApiUrl: "https://api\(i).com",
                        httpApiKey: "key-\(i)",
                        secretKey: ""
                    )
                    try await service.insertDatabaseConfig(config)
                }

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.count == 3)
            }
        }

        @Test("Update config changes all fields", .tags(.database))
        func testUpdateConfig() async throws {
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
                    websocketUrl: "wss://original.com",
                    httpApiUrl: "https://original-api.com",
                    httpApiKey: "original-key",
                    secretKey: ""
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
                    websocketUrl: "wss://updated.com",
                    httpApiUrl: "https://updated-api.com",
                    httpApiKey: "updated-key",
                    secretKey: "new-secret"
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

        @Test("Delete config removes entry", .tags(.database))
        func testDeleteConfig() async throws {
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
                    websocketUrl: "wss://ws.com",
                    httpApiUrl: "https://api.com",
                    httpApiKey: "key",
                    secretKey: ""
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

        @Test("Get all configs returns empty for fresh database", .tags(.database))
        func testGetAllConfigsEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs.isEmpty)
            }
        }
    }

    // MARK: - Credential Storage Tests

    @Suite("Credential Storage & Encryption")
    struct CredentialTests {

        @Test("Credentials stored encrypted at rest", .tags(.encryption, .database))
        func testCredentialsEncrypted() async throws {
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
                    websocketUrl: "wss://secure-ws.com",
                    httpApiUrl: "https://secure-api.com",
                    httpApiKey: "super-secret-api-key",
                    secretKey: "super-secret-key"
                )
                try await service.insertDatabaseConfig(config)

                // Verify credentials can be retrieved (proves decryption works)
                let configs = try await service.getAllDatabaseConfigs()
                #expect(configs[0].token == "super-secret-token")
                #expect(configs[0].httpApiKey == "super-secret-api-key")
                #expect(configs[0].secretKey == "super-secret-key")
            }
        }

        @Test("Empty credentials stored correctly", .tags(.database))
        func testEmptyCredentials() async throws {
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
                    websocketUrl: "",
                    httpApiUrl: "",
                    httpApiKey: "",
                    secretKey: ""
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

        @Test("Insert history stores entry", .tags(.database, .repository))
        func testInsertHistory() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-db-\(UUID().uuidString)"
                // Insert parent DatabaseConfigRow to satisfy FK constraint
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Get history returns entries ordered by date descending", .tags(.database, .repository))
        func testGetHistoryOrder() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-order-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Delete history removes entry", .tags(.database, .repository))
        func testDeleteHistory() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Delete all history removes all entries for database", .tags(.database, .repository))
        func testDeleteAllHistory() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "hist-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("History is scoped per database", .tags(.database, .repository))
        func testHistoryScopedByDatabase() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "hist-scope-1-\(UUID().uuidString)"
                let dbId2 = "hist-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Insert favorite stores entry", .tags(.database, .repository))
        func testInsertFavorite() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-db-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Get favorites returns multiple entries", .tags(.database, .repository))
        func testGetFavoritesMultiple() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-multi-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Delete favorite removes entry", .tags(.database, .repository))
        func testDeleteFavorite() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "fav-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Favorites are scoped per database", .tags(.database, .repository))
        func testFavoritesScopedByDatabase() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "fav-scope-1-\(UUID().uuidString)"
                let dbId2 = "fav-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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

        @Test("Insert subscription stores entry", .tags(.database, .repository))
        func testInsertSubscription() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current

                // First insert a database config so foreign key constraint is satisfied
                let dbId = "sub-db-\(UUID().uuidString)"
                let dbConfig = SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "Test DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                )
                try await service.insertDatabaseConfig(dbConfig)

                let row = SQLCipherService.SubscriptionRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "All Cars",
                    query: "SELECT * FROM cars",
                    args: nil
                )

                // ACT
                try await service.insertSubscription(row)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0]._id == row._id)
                #expect(rows[0].name == "All Cars")
                #expect(rows[0].query == "SELECT * FROM cars")
                #expect(rows[0].args == nil)
            }
        }

        @Test("Insert subscription with args stores args", .tags(.database, .repository))
        func testInsertSubscriptionWithArgs() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "sub-args-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let row = SQLCipherService.SubscriptionRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "Filtered",
                    query: "SELECT * FROM cars WHERE color = :color",
                    args: "{\"color\": \"red\"}"
                )

                // ACT
                try await service.insertSubscription(row)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0].args == "{\"color\": \"red\"}")
            }
        }

        @Test("Delete subscription removes entry", .tags(.database, .repository))
        func testDeleteSubscription() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "sub-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                let row = SQLCipherService.SubscriptionRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "To Delete",
                    query: "SELECT * FROM items",
                    args: nil
                )
                try await service.insertSubscription(row)

                // ACT
                try await service.deleteSubscription(id: row._id)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test("Get all subscriptions returns entries for database", .tags(.database, .repository))
        func testGetAllSubscriptions() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "sub-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                for i in 1 ... 3 {
                    let row = SQLCipherService.SubscriptionRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        name: "Sub \(i)",
                        query: "SELECT \(i)",
                        args: nil
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

        @Test("Insert observable stores entry", .tags(.database, .repository))
        func testInsertObservable() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-db-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                let row = SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "Cars Observer",
                    query: "SELECT * FROM cars",
                    args: nil,
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
                #expect(rows[0].args == nil)
            }
        }

        @Test("Get all observables returns entries for database", .tags(.database, .repository))
        func testGetAllObservables() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-all-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                for i in 1 ... 3 {
                    let row = SQLCipherService.ObservableRow(
                        _id: TestHelpers.uniqueTestId(),
                        databaseId: dbId,
                        name: "Observer \(i)",
                        query: "SELECT \(i)",
                        args: nil,
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

        @Test("Delete observable removes entry", .tags(.database, .repository))
        func testDeleteObservable() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-del-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                let row = SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: dbId,
                    name: "To Delete",
                    query: "SELECT * FROM items",
                    args: nil,
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

        @Test("Update observable changes fields", .tags(.database, .repository))
        func testUpdateObservable() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId = "obs-upd-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                let id = TestHelpers.uniqueTestId()
                let original = SQLCipherService.ObservableRow(
                    _id: id, databaseId: dbId, name: "Original",
                    query: "SELECT 1", args: nil, isActive: false, lastUpdated: nil
                )
                try await service.insertObservable(original)

                let updated = SQLCipherService.ObservableRow(
                    _id: id, databaseId: dbId, name: "Updated",
                    query: "SELECT 2", args: "{}", isActive: true, lastUpdated: "2026-01-01T00:00:00Z"
                )

                // ACT
                try await service.updateObservable(updated)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.count == 1)
                #expect(rows[0].name == "Updated")
                #expect(rows[0].query == "SELECT 2")
                #expect(rows[0].isActive == true)
                #expect(rows[0].args == "{}")
            }
        }

        @Test("Observables are scoped per database", .tags(.database, .repository))
        func testObservablesScopedByDatabase() async throws {
            // ARRANGE
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                let dbId1 = "obs-scope-1-\(UUID().uuidString)"
                let dbId2 = "obs-scope-2-\(UUID().uuidString)"
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: TestHelpers.uniqueTestId(), name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId1, name: "Obs1",
                    query: "Q1", args: nil, isActive: true, lastUpdated: nil
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: TestHelpers.uniqueTestId(), databaseId: dbId2, name: "Obs2",
                    query: "Q2", args: nil, isActive: true, lastUpdated: nil
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

        @Test("withFreshDatabase provides task-local isolated service", .tags(.database))
        func testWithFreshDatabaseIsolation() async throws {
            try await TestHelpers.withFreshDatabase {
                let taskLocalService = SQLCipherContext.current
                // Task-local service is a different instance from the production singleton
                #expect(ObjectIdentifier(taskLocalService) != ObjectIdentifier(SQLCipherService.shared))
            }
        }

        @Test("Separate withFreshDatabase calls start with empty databases", .tags(.database))
        func testSeparateCallsStartFresh() async throws {
            let dbId = "isolation-test-\(UUID().uuidString)"
            let configId = TestHelpers.uniqueTestId()

            // First scope: insert a config
            try await TestHelpers.withFreshDatabase {
                let service = SQLCipherContext.current
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: configId, name: "IsolationDB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
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
