import Testing
import Foundation
@testable import Edge_Debug_Helper

/// Integration tests for DatabaseRepository add database flow
///
/// Tests the complete flow of adding a database configuration:
/// 1. Directory creation when needed
/// 2. Credentials storage in Keychain
/// 3. Metadata storage in cache file
/// 4. Fresh install scenarios
///
/// These tests use a separate test cache directory to avoid interfering with production data.
@Suite("DatabaseRepository Integration Tests")
struct DatabaseRepositoryIntegrationTests {
    
    // MARK: - Test Setup
    
    let testCacheDirectory: URL
    let keychainService: KeychainService
    let cacheService: SecureCacheService
    let repository: DatabaseRepository
    
    init() async throws {
        // Use test cache directory
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        testCacheDirectory = baseURL.appendingPathComponent("ditto_cache_integration_test")
        
        // Clean up any previous test data
        if fileManager.fileExists(atPath: testCacheDirectory.path) {
            try? fileManager.removeItem(at: testCacheDirectory)
        }
        
        keychainService = KeychainService.shared
        cacheService = SecureCacheService.shared
        repository = DatabaseRepository.shared
    }
    
    // MARK: - Directory Creation Tests
    
    @Test("Directory is created when adding first database")
    func testAddDatabaseCreatesDirectoryIfNeeded() async throws {
        // ARRANGE: Ensure test cache directory doesn't exist
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: testCacheDirectory.path) {
            try fileManager.removeItem(at: testCacheDirectory)
        }
        
        #expect(!fileManager.fileExists(atPath: testCacheDirectory.path),
                "Test cache directory should not exist before test")
        
        // Create test database config
        let testConfig = createTestDatabaseConfig(
            name: "Test Database",
            databaseId: "test-db-001"
        )
        
        // ACT: Add database configuration
        try await repository.addDittoAppConfig(testConfig)
        
        // ASSERT: Verify cache directory was created
        let actualCacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ditto_cache")
        
        #expect(fileManager.fileExists(atPath: actualCacheDir.path),
                "Cache directory should be created automatically")
        
        // ASSERT: Verify database_configs.json exists
        let configFilePath = actualCacheDir.appendingPathComponent("database_configs.json")
        #expect(fileManager.fileExists(atPath: configFilePath.path),
                "database_configs.json should be created")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    @Test("Multiple databases can be added to existing cache directory")
    func testAddMultipleDatabases() async throws {
        // ARRANGE: Add first database
        let config1 = createTestDatabaseConfig(name: "Database 1", databaseId: "test-db-1")
        try await repository.addDittoAppConfig(config1)
        
        // ACT: Add second database
        let config2 = createTestDatabaseConfig(name: "Database 2", databaseId: "test-db-2")
        try await repository.addDittoAppConfig(config2)
        
        // ASSERT: Load all configs and verify both exist
        let allConfigs = try await repository.loadDatabaseConfigs()
        
        let config1Exists = allConfigs.contains { $0.databaseId == "test-db-1" }
        let config2Exists = allConfigs.contains { $0.databaseId == "test-db-2" }
        
        #expect(config1Exists, "First database should exist")
        #expect(config2Exists, "Second database should exist")
        #expect(allConfigs.count >= 2, "Should have at least 2 databases")
        
        // Cleanup
        try await cleanupTestDatabase(config1)
        try await cleanupTestDatabase(config2)
    }
    
    // MARK: - Keychain Storage Tests
    
    @Test("Credentials are stored in Keychain after adding database")
    func testAddDatabaseStoresCredentialsInKeychain() async throws {
        // ARRANGE: Create test config with credentials
        let testConfig = createTestDatabaseConfig(
            name: "Keychain Test Database",
            databaseId: "test-keychain-001"
        )
        
        // ACT: Add database
        try await repository.addDittoAppConfig(testConfig)
        
        // ASSERT: Verify credentials exist in Keychain
        let credentials = try await keychainService.loadDatabaseCredentials(testConfig.databaseId)
        
        #expect(credentials != nil, "Credentials should be stored in Keychain")
        #expect(credentials?.name == testConfig.name, "Name should match")
        #expect(credentials?.token == testConfig.token, "Token should match")
        #expect(credentials?.authUrl == testConfig.authUrl, "Auth URL should match")
        #expect(credentials?.websocketUrl == testConfig.websocketUrl, "WebSocket URL should match")
        #expect(credentials?.httpApiUrl == testConfig.httpApiUrl, "HTTP API URL should match")
        #expect(credentials?.httpApiKey == testConfig.httpApiKey, "HTTP API key should match")
        #expect(credentials?.secretKey == testConfig.secretKey, "Secret key should match")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    @Test("Updating database updates Keychain credentials")
    func testUpdateDatabaseUpdatesKeychain() async throws {
        // ARRANGE: Add initial database
        let testConfig = createTestDatabaseConfig(
            name: "Original Name",
            databaseId: "test-update-001"
        )
        try await repository.addDittoAppConfig(testConfig)
        
        // ACT: Update database with new credentials
        testConfig.name = "Updated Name"
        testConfig.token = "updated-token-xyz"
        try await repository.updateDittoAppConfig(testConfig)
        
        // ASSERT: Verify updated credentials in Keychain
        let credentials = try await keychainService.loadDatabaseCredentials(testConfig.databaseId)
        
        #expect(credentials?.name == "Updated Name", "Name should be updated")
        #expect(credentials?.token == "updated-token-xyz", "Token should be updated")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    // MARK: - Cache File Storage Tests
    
    @Test("Metadata is stored in cache file after adding database")
    func testAddDatabaseStoresMetadataInCache() async throws {
        // ARRANGE: Create test config
        let testConfig = createTestDatabaseConfig(
            name: "Cache Test Database",
            databaseId: "test-cache-001"
        )
        
        // ACT: Add database
        try await repository.addDittoAppConfig(testConfig)
        
        // ASSERT: Verify metadata in cache file
        let metadata = try await cacheService.loadDatabaseConfigs()
        let matchingMetadata = metadata.first { $0.databaseId == testConfig.databaseId }
        
        #expect(matchingMetadata != nil, "Metadata should be stored in cache")
        #expect(matchingMetadata?.name == testConfig.name, "Name should match")
        #expect(matchingMetadata?.databaseId == testConfig.databaseId, "Database ID should match")
        #expect(matchingMetadata?.mode == testConfig.mode.rawValue, "Mode should match")
        #expect(matchingMetadata?.isBluetoothLeEnabled == testConfig.isBluetoothLeEnabled, "Bluetooth setting should match")
        #expect(matchingMetadata?.isLanEnabled == testConfig.isLanEnabled, "LAN setting should match")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    @Test("Deleting database removes both Keychain and cache entries")
    func testDeleteDatabaseRemovesAllData() async throws {
        // ARRANGE: Add database
        let testConfig = createTestDatabaseConfig(
            name: "Delete Test Database",
            databaseId: "test-delete-001"
        )
        try await repository.addDittoAppConfig(testConfig)
        
        // Verify database exists
        let credentialsBefore = try await keychainService.loadDatabaseCredentials(testConfig.databaseId)
        #expect(credentialsBefore != nil, "Credentials should exist before delete")
        
        // ACT: Delete database
        try await repository.deleteDittoAppConfig(testConfig)
        
        // ASSERT: Verify credentials removed from Keychain
        let credentialsAfter = try await keychainService.loadDatabaseCredentials(testConfig.databaseId)
        #expect(credentialsAfter == nil, "Credentials should be removed from Keychain")
        
        // ASSERT: Verify metadata removed from cache
        let metadataList = try await cacheService.loadDatabaseConfigs()
        let metadataExists = metadataList.contains { $0.databaseId == testConfig.databaseId }
        #expect(!metadataExists, "Metadata should be removed from cache")
    }
    
    // MARK: - Fresh Install Tests
    
    @Test("Fresh install with no existing data creates all necessary structures")
    func testAddDatabaseWithFreshInstall() async throws {
        // ARRANGE: Simulate fresh install by clearing all test data
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ditto_cache")
        
        // Clean up cache directory to simulate fresh install
        if fileManager.fileExists(atPath: cacheDir.path) {
            let configFile = cacheDir.appendingPathComponent("database_configs.json")
            if fileManager.fileExists(atPath: configFile.path) {
                try fileManager.removeItem(at: configFile)
            }
        }
        
        // ACT: Add first database on "fresh install"
        let testConfig = createTestDatabaseConfig(
            name: "Fresh Install Database",
            databaseId: "test-fresh-001"
        )
        try await repository.addDittoAppConfig(testConfig)
        
        // ASSERT: Verify all structures created
        #expect(fileManager.fileExists(atPath: cacheDir.path),
                "Cache directory should be created")
        
        let configFile = cacheDir.appendingPathComponent("database_configs.json")
        #expect(fileManager.fileExists(atPath: configFile.path),
                "Config file should be created")
        
        let credentials = try await keychainService.loadDatabaseCredentials(testConfig.databaseId)
        #expect(credentials != nil, "Credentials should be stored")
        
        // ASSERT: Verify database can be loaded
        let configs = try await repository.loadDatabaseConfigs()
        let matchingConfig = configs.first { $0.databaseId == testConfig.databaseId }
        #expect(matchingConfig != nil, "Database should be loadable")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    @Test("Loading databases with empty cache returns empty array")
    func testLoadDatabasesWithEmptyCache() async throws {
        // ARRANGE: Ensure cache is empty by deleting config file
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ditto_cache")
        let configFile = cacheDir.appendingPathComponent("database_configs.json")
        
        if fileManager.fileExists(atPath: configFile.path) {
            try fileManager.removeItem(at: configFile)
        }
        
        // ACT: Load databases
        let configs = try await repository.loadDatabaseConfigs()
        
        // ASSERT: Should return empty array, not error
        #expect(configs.isEmpty, "Should return empty array when no databases exist")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Adding database with duplicate ID updates existing database")
    func testAddDatabaseWithDuplicateId() async throws {
        // ARRANGE: Add initial database
        let testConfig = createTestDatabaseConfig(
            name: "Original Database",
            databaseId: "test-duplicate-001"
        )
        try await repository.addDittoAppConfig(testConfig)
        
        // ACT: Add database with same ID but different name
        let duplicateConfig = testConfig
        duplicateConfig.name = "Updated Database"
        try await repository.addDittoAppConfig(duplicateConfig)
        
        // ASSERT: Should have updated, not duplicated
        let configs = try await repository.loadDatabaseConfigs()
        let matchingConfigs = configs.filter { $0.databaseId == "test-duplicate-001" }
        
        #expect(matchingConfigs.count == 1, "Should only have one database with this ID")
        #expect(matchingConfigs.first?.name == "Updated Database", "Name should be updated")
        
        // Cleanup
        try await cleanupTestDatabase(testConfig)
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test database configuration with default values
    private func createTestDatabaseConfig(name: String, databaseId: String) -> Edge_Debug_Helper.DittoConfigForDatabase {
        return Edge_Debug_Helper.DittoConfigForDatabase(
            UUID().uuidString,
            name: name,
            databaseId: databaseId,
            token: "test-token-\(databaseId)",
            authUrl: "https://cloud.ditto.live/auth",
            websocketUrl: "wss://cloud.ditto.live/ws",
            httpApiUrl: "https://cloud.ditto.live/api",
            httpApiKey: "test-api-key-\(databaseId)",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "test-secret-key-\(databaseId)",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )
    }
    
    /// Cleans up test database from Keychain and cache
    private func cleanupTestDatabase(_ config: Edge_Debug_Helper.DittoConfigForDatabase) async throws {
        // Delete from repository (removes Keychain + cache)
        try await repository.deleteDittoAppConfig(config)

        // Also delete per-database data files if they exist
        try await cacheService.deleteDatabaseData(config.databaseId)
    }
}
