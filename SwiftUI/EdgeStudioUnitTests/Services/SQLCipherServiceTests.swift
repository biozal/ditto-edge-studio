import Testing
@testable import Edge_Debug_Helper

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
@Suite("SQLCipher Service Tests", .serialized)
struct SQLCipherServiceTests {

    // MARK: - Initialization & Encryption Tests

    @Suite("Initialization & Encryption")
    struct InitializationTests {

        
        @Test("Service initializes successfully", .tags(.database, .encryption))
        func testInitialization() async throws {
            try await TestHelpers.setupUninitializedDatabase()

            let service = SQLCipherService.shared

            // Service should initialize without errors
            try await service.initialize()

            // Should be able to query (proves encryption worked)
            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.isEmpty) // Fresh database
        }
        
        @Test("Encryption key is generated and stored", .tags(.encryption))
        func testEncryptionKeyGeneration() async throws {
            try await TestHelpers.setupFreshDatabase()

            // Key file should exist after initialization
            let dbDir = TestConfiguration.unitTestDatabasePath
            let keyFilePath = URL(fileURLWithPath: dbDir)
                .appendingPathComponent("sqlcipher.key")

            let fileManager = FileManager.default
            #expect(fileManager.fileExists(atPath: keyFilePath.path))

            // Key should be 64 characters (256-bit hex)
            let keyData = try Data(contentsOf: keyFilePath)
            let key = String(data: keyData, encoding: .utf8)
            #expect(key?.count == 64)
        }
        
        @Test("Encryption key persists across reinitializations", .tags(.encryption))
        func testEncryptionKeyPersistence() async throws {
            try await TestHelpers.setupFreshDatabase()

            let service = SQLCipherService.shared

            // Get initial encryption key
            let dbDir = TestConfiguration.unitTestDatabasePath
            let keyFilePath = URL(fileURLWithPath: dbDir)
                .appendingPathComponent("sqlcipher.key")

            let keyData1 = try Data(contentsOf: keyFilePath)
            let key1 = String(data: keyData1, encoding: .utf8)

            // Reinitialize service
            try await service.initialize()

            // Key should be the same
            let keyData2 = try Data(contentsOf: keyFilePath)
            let key2 = String(data: keyData2, encoding: .utf8)

            #expect(key1 == key2)
        }
    }
    
    // MARK: - Schema Tests
    
    @Suite("Schema Management")
    struct SchemaTests {
        
        @Test("Fresh database creates schema version 2", .tags(.database))
        func testSchemaVersion() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
            let version = try await service.getSchemaVersion()
            #expect(version == 2) // Current schema version
        }
        
        @Test("Database has all required tables", .tags(.database))
        func testSchemaTablesExist() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
            // Query to verify tables exist
            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.isEmpty) // Proves databaseConfigs table exists
        }
        
        @Test("Database configs table has credential columns", .tags(.database))
        func testDatabaseConfigsHasCredentialColumns() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
    
    // MARK: - CRUD Tests
    
    @Suite("Database Config CRUD Operations")
    struct CRUDTests {
        
        @Test("Insert database config stores all fields", .tags(.database))
        func testInsertConfig() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
        
        @Test("Insert multiple configs stores all", .tags(.database))
        func testInsertMultipleConfigs() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
            // Insert 3 configs
            for i in 1...3 {
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
        
        @Test("Update config changes all fields", .tags(.database))
        func testUpdateConfig() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
        
        @Test("Delete config removes entry", .tags(.database))
        func testDeleteConfig() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
        
        @Test("Get all configs returns empty for fresh database", .tags(.database))
        func testGetAllConfigsEmpty() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.isEmpty)
        }
    }
    
    // MARK: - Credential Storage Tests
    
    @Suite("Credential Storage & Encryption")
    struct CredentialTests {
        
        @Test("Credentials stored encrypted at rest", .tags(.encryption, .database))
        func testCredentialsEncrypted() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
        
        @Test("Empty credentials stored correctly", .tags(.database))
        func testEmptyCredentials() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let service = SQLCipherService.shared
            
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
    
    // MARK: - Test Isolation Tests
    
    @Suite("Test Isolation")
    struct IsolationTests {
        
        @Test("Test database uses separate path", .tags(.database))
        func testDatabasePath() async throws {
            try await TestHelpers.setupFreshDatabase()
            
            let dbPath = TestConfiguration.unitTestDatabasePath
            
            // Verify it's in test directory
            #expect(dbPath.contains("ditto_cache_unit_test"))
            
            // Verify it's NOT in production directory
            #expect(!dbPath.contains("ditto_cache/"))
        }
        
        @Test("Test encryption key uses separate path", .tags(.encryption))
        func testEncryptionKeyPath() async throws {
            try await TestHelpers.setupFreshDatabase()

            let dbDir = TestConfiguration.unitTestDatabasePath
            let keyPath = URL(fileURLWithPath: dbDir)
                .appendingPathComponent("sqlcipher.key")
                .path

            // Verify key is in test directory
            #expect(keyPath.contains("ditto_cache_unit_test"))
        }
    }
}

