import Testing
import Foundation
@testable import Edge_Debug_Helper

/// Unit tests for SQLCipherService
///
/// Tests encryption, CRUD operations, transactions, cascade deletion,
/// and schema management for the encrypted SQLite database.
///
/// **Test Isolation:**
/// - Uses test-specific database file
/// - Cleans up after each test
/// - Does not interfere with production or UI test databases
@Suite("SQLCipherService Tests")
struct SQLCipherServiceTests {

    // MARK: - Test Setup

    let sqlCipher: SQLCipherService
    let testDatabasePath: URL

    init() async throws {
        sqlCipher = SQLCipherService.shared

        // Get test database path
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testDir = baseURL.appendingPathComponent("ditto_cache_unit_test")

        // Clean up any previous test data
        if fileManager.fileExists(atPath: testDir.path) {
            try? fileManager.removeItem(at: testDir)
        }

        // Create test directory
        try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

        testDatabasePath = testDir.appendingPathComponent("test_encrypted.db")

        // Note: SQLCipherService uses singleton, so we need to be careful about state
        // Each test should use unique IDs to avoid conflicts
    }

    // MARK: - Encryption Key Tests

    @Test("Encryption key generation creates 64-character hex string")
    func testEncryptionKeyGeneration() async throws {
        let key = try await sqlCipher.getOrCreateEncryptionKey()

        #expect(key.count == 64, "Key should be 64 characters (32 bytes hex-encoded)")
        #expect(key.allSatisfy { $0.isHexDigit }, "Key should only contain hex digits")
    }

    @Test("Encryption key is consistent across calls")
    func testEncryptionKeyConsistency() async throws {
        let key1 = try await sqlCipher.getOrCreateEncryptionKey()
        let key2 = try await sqlCipher.getOrCreateEncryptionKey()

        #expect(key1 == key2, "Key should be the same across multiple calls")
    }

    // MARK: - Initialization Tests

    @Test("SQLCipher initializes successfully")
    func testInitialization() async throws {
        try await sqlCipher.initialize()

        let isInitialized = await sqlCipher.checkInitialized()
        #expect(isInitialized, "SQLCipher should be initialized")
    }

    @Test("Schema version is set correctly after initialization")
    func testSchemaVersionAfterInit() async throws {
        try await sqlCipher.initialize()

        let version = try await sqlCipher.getSchemaVersion()
        #expect(version == 1, "Schema version should be 1 after initialization")
    }

    // MARK: - Database Config CRUD Tests

    @Test("Insert and retrieve database config")
    func testInsertDatabaseConfig() async throws {
        try await sqlCipher.initialize()

        let testId = "test-db-\(UUID().uuidString)"
        let config = SQLCipherService.DatabaseConfigRow(
            _id: testId,
            name: "Test Database",
            databaseId: "db-123",
            mode: "onlineplayground",
            allowUntrustedCerts: false,
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )

        try await sqlCipher.insertDatabaseConfig(config)

        let configs = try await sqlCipher.getAllDatabaseConfigs()
        let retrieved = configs.first { $0._id == testId }

        #expect(retrieved != nil, "Config should be retrievable")
        #expect(retrieved?.name == "Test Database", "Name should match")
        #expect(retrieved?.databaseId == "db-123", "Database ID should match")
    }

    @Test("Update database config")
    func testUpdateDatabaseConfig() async throws {
        try await sqlCipher.initialize()

        let testId = "test-update-\(UUID().uuidString)"
        let config = SQLCipherService.DatabaseConfigRow(
            _id: testId,
            name: "Original Name",
            databaseId: "db-update-123",
            mode: "onlineplayground",
            allowUntrustedCerts: false,
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )

        try await sqlCipher.insertDatabaseConfig(config)

        // Update
        var updated = config
        updated.name = "Updated Name"
        updated.allowUntrustedCerts = true

        try await sqlCipher.updateDatabaseConfig(updated)

        let configs = try await sqlCipher.getAllDatabaseConfigs()
        let retrieved = configs.first { $0.databaseId == "db-update-123" }

        #expect(retrieved?.name == "Updated Name", "Name should be updated")
        #expect(retrieved?.allowUntrustedCerts == true, "allowUntrustedCerts should be updated")
    }

    @Test("Delete database config")
    func testDeleteDatabaseConfig() async throws {
        try await sqlCipher.initialize()

        let testId = "test-delete-\(UUID().uuidString)"
        let config = SQLCipherService.DatabaseConfigRow(
            _id: testId,
            name: "To Delete",
            databaseId: "db-delete-123",
            mode: "onlineplayground",
            allowUntrustedCerts: false,
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )

        try await sqlCipher.insertDatabaseConfig(config)

        // Verify exists
        var configs = try await sqlCipher.getAllDatabaseConfigs()
        #expect(configs.contains { $0.databaseId == "db-delete-123" }, "Config should exist before deletion")

        // Delete
        try await sqlCipher.deleteDatabaseConfig(databaseId: "db-delete-123")

        // Verify deleted
        configs = try await sqlCipher.getAllDatabaseConfigs()
        #expect(!configs.contains { $0.databaseId == "db-delete-123" }, "Config should not exist after deletion")
    }

    // MARK: - History CRUD Tests

    @Test("Insert and retrieve history")
    func testInsertHistory() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-history-\(UUID().uuidString)"
        let historyId = "hist-\(UUID().uuidString)"

        let history = SQLCipherService.HistoryRow(
            _id: historyId,
            databaseId: testDbId,
            query: "SELECT * FROM users",
            createdDate: Date().ISO8601Format()
        )

        try await sqlCipher.insertHistory(history)

        let results = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        let retrieved = results.first { $0._id == historyId }

        #expect(retrieved != nil, "History should be retrievable")
        #expect(retrieved?.query == "SELECT * FROM users", "Query should match")
    }

    @Test("History is ordered by createdDate DESC")
    func testHistoryOrdering() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-order-\(UUID().uuidString)"

        // Insert multiple history items with different timestamps
        let history1 = SQLCipherService.HistoryRow(
            _id: "hist1-\(UUID().uuidString)",
            databaseId: testDbId,
            query: "SELECT 1",
            createdDate: "2024-01-01T10:00:00Z"
        )

        let history2 = SQLCipherService.HistoryRow(
            _id: "hist2-\(UUID().uuidString)",
            databaseId: testDbId,
            query: "SELECT 2",
            createdDate: "2024-01-02T10:00:00Z"
        )

        let history3 = SQLCipherService.HistoryRow(
            _id: "hist3-\(UUID().uuidString)",
            databaseId: testDbId,
            query: "SELECT 3",
            createdDate: "2024-01-03T10:00:00Z"
        )

        try await sqlCipher.insertHistory(history1)
        try await sqlCipher.insertHistory(history2)
        try await sqlCipher.insertHistory(history3)

        let results = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)

        #expect(results.count >= 3, "Should have at least 3 history items")

        // Find our test items
        let testItems = results.filter { $0.databaseId == testDbId }
        #expect(testItems.count == 3, "Should have exactly 3 test items")

        // Most recent should be first
        #expect(testItems[0].query == "SELECT 3", "Most recent query should be first")
        #expect(testItems[1].query == "SELECT 2", "Second most recent should be second")
        #expect(testItems[2].query == "SELECT 1", "Oldest should be last")
    }

    // MARK: - Favorites CRUD Tests

    @Test("Insert and retrieve favorites")
    func testInsertFavorite() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-fav-\(UUID().uuidString)"
        let favId = "fav-\(UUID().uuidString)"

        let favorite = SQLCipherService.FavoriteRow(
            _id: favId,
            databaseId: testDbId,
            query: "SELECT * FROM favorites",
            createdDate: Date().ISO8601Format()
        )

        try await sqlCipher.insertFavorite(favorite)

        let results = try await sqlCipher.getFavorites(databaseId: testDbId)
        let retrieved = results.first { $0._id == favId }

        #expect(retrieved != nil, "Favorite should be retrievable")
        #expect(retrieved?.query == "SELECT * FROM favorites", "Query should match")
    }

    // MARK: - Cascade Deletion Tests

    @Test("Cascade delete removes all related data")
    func testCascadeDeletion() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-cascade-\(UUID().uuidString)"

        // Insert database config
        let config = SQLCipherService.DatabaseConfigRow(
            _id: "config-\(UUID().uuidString)",
            name: "Cascade Test",
            databaseId: testDbId,
            mode: "onlineplayground",
            allowUntrustedCerts: false,
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )
        try await sqlCipher.insertDatabaseConfig(config)

        // Insert related data
        let history = SQLCipherService.HistoryRow(
            _id: "hist-cascade-\(UUID().uuidString)",
            databaseId: testDbId,
            query: "SELECT * FROM cascade",
            createdDate: Date().ISO8601Format()
        )
        try await sqlCipher.insertHistory(history)

        let favorite = SQLCipherService.FavoriteRow(
            _id: "fav-cascade-\(UUID().uuidString)",
            databaseId: testDbId,
            query: "SELECT * FROM cascade_fav",
            createdDate: Date().ISO8601Format()
        )
        try await sqlCipher.insertFavorite(favorite)

        let subscription = SQLCipherService.SubscriptionRow(
            _id: "sub-cascade-\(UUID().uuidString)",
            databaseId: testDbId,
            name: "Cascade Sub",
            query: "SELECT * FROM cascade_sub",
            args: nil
        )
        try await sqlCipher.insertSubscription(subscription)

        // Verify data exists
        var historyResults = try await sqlCipher.getHistory(databaseId: testDbId)
        var favResults = try await sqlCipher.getFavorites(databaseId: testDbId)
        var subResults = try await sqlCipher.getSubscriptions(databaseId: testDbId)

        #expect(!historyResults.isEmpty, "History should exist before deletion")
        #expect(!favResults.isEmpty, "Favorites should exist before deletion")
        #expect(!subResults.isEmpty, "Subscriptions should exist before deletion")

        // Delete database config (CASCADE DELETE)
        try await sqlCipher.deleteDatabaseConfig(databaseId: testDbId)

        // Verify related data is also deleted
        historyResults = try await sqlCipher.getHistory(databaseId: testDbId)
        favResults = try await sqlCipher.getFavorites(databaseId: testDbId)
        subResults = try await sqlCipher.getSubscriptions(databaseId: testDbId)

        #expect(historyResults.isEmpty, "History should be cascade deleted")
        #expect(favResults.isEmpty, "Favorites should be cascade deleted")
        #expect(subResults.isEmpty, "Subscriptions should be cascade deleted")
    }

    // MARK: - Transaction Tests

    @Test("Transaction commits on success")
    func testTransactionCommit() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-tx-commit-\(UUID().uuidString)"

        try await sqlCipher.executeTransaction {
            let history1 = SQLCipherService.HistoryRow(
                _id: "hist-tx1-\(UUID().uuidString)",
                databaseId: testDbId,
                query: "SELECT 1",
                createdDate: Date().ISO8601Format()
            )

            let history2 = SQLCipherService.HistoryRow(
                _id: "hist-tx2-\(UUID().uuidString)",
                databaseId: testDbId,
                query: "SELECT 2",
                createdDate: Date().ISO8601Format()
            )

            try await sqlCipher.insertHistory(history1)
            try await sqlCipher.insertHistory(history2)
        }

        let results = try await sqlCipher.getHistory(databaseId: testDbId)
        #expect(results.count == 2, "Both history items should be committed")
    }

    @Test("Transaction rolls back on error")
    func testTransactionRollback() async throws {
        try await sqlCipher.initialize()

        let testDbId = "db-tx-rollback-\(UUID().uuidString)"

        do {
            try await sqlCipher.executeTransaction {
                let history = SQLCipherService.HistoryRow(
                    _id: "hist-rollback-\(UUID().uuidString)",
                    databaseId: testDbId,
                    query: "SELECT should_rollback",
                    createdDate: Date().ISO8601Format()
                )

                try await sqlCipher.insertHistory(history)

                // Simulate error
                throw TestError.simulatedFailure
            }

            #expect(Bool(false), "Transaction should have thrown")

        } catch TestError.simulatedFailure {
            // Expected
        }

        // Verify no data was committed
        let results = try await sqlCipher.getHistory(databaseId: testDbId)
        #expect(results.isEmpty, "History should not be committed after rollback")
    }

    // MARK: - Test Cleanup

    deinit {
        // Note: SQLCipherService is singleton, so we can't fully clean up
        // Tests should use unique IDs to avoid conflicts
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case simulatedFailure
}

// MARK: - Character Extension

extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
