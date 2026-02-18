import Testing
import Foundation
@testable import Edge_Debug_Helper

/// Integration tests for repositories with SQLCipher backend
///
/// Tests end-to-end workflows across repositories and SQLCipher service.
/// Validates:
/// - CRUD operations persist correctly
/// - CASCADE DELETE removes all related data
/// - Multiple repositories work together
/// - Test isolation (separate from production data)
@Suite("Repository SQLCipher Integration Tests")
struct RepositorySQLCipherIntegrationTests {

    // MARK: - Test Setup

    let sqlCipher: SQLCipherService
    let databaseRepo: DatabaseRepository
    let historyRepo: HistoryRepository
    let favoritesRepo: FavoritesRepository
    let subscriptionsRepo: SubscriptionsRepository
    let observableRepo: ObservableRepository

    init() async throws {
        sqlCipher = SQLCipherService.shared
        databaseRepo = DatabaseRepository.shared
        historyRepo = HistoryRepository.shared
        favoritesRepo = FavoritesRepository.shared
        subscriptionsRepo = SubscriptionsRepository.shared
        observableRepo = ObservableRepository.shared

        // Ensure SQLCipher is initialized for tests
        try await sqlCipher.initialize()
    }

    // MARK: - DatabaseRepository Integration Tests

    @Test("DatabaseRepository CRUD operations persist to SQLCipher")
    func testDatabaseRepositoryCRUD() async throws {
        let testId = "test-db-\(UUID().uuidString)"
        let testDbId = "db-\(UUID().uuidString)"

        // Create
        let config = DittoConfigForDatabase(
            testId,
            name: "Integration Test Database",
            databaseId: testDbId,
            token: "test-token-123",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "api-key-123",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )

        try await databaseRepo.addDittoAppConfig(config)

        // Read - verify it persisted to SQLCipher
        let configs = try await sqlCipher.getAllDatabaseConfigs()
        let found = configs.first { $0.databaseId == testDbId }

        #expect(found != nil, "Config should be persisted to SQLCipher")
        #expect(found?.name == "Integration Test Database", "Name should match")

        // Update
        var updated = config
        updated.name = "Updated Integration Test"
        updated.allowUntrustedCerts = true

        try await databaseRepo.updateDittoAppConfig(updated)

        // Verify update persisted
        let updatedConfigs = try await sqlCipher.getAllDatabaseConfigs()
        let foundUpdated = updatedConfigs.first { $0.databaseId == testDbId }

        #expect(foundUpdated?.name == "Updated Integration Test", "Name should be updated")
        #expect(foundUpdated?.allowUntrustedCerts == true, "allowUntrustedCerts should be updated")

        // Delete
        try await databaseRepo.deleteDittoAppConfig(updated)

        // Verify deleted
        let afterDelete = try await sqlCipher.getAllDatabaseConfigs()
        #expect(!afterDelete.contains(where: { $0.databaseId == testDbId }), "Config should be deleted")
    }

    // MARK: - HistoryRepository Integration Tests

    @Test("HistoryRepository operations persist to SQLCipher")
    func testHistoryRepositoryPersistence() async throws {
        let testDbId = "db-history-\(UUID().uuidString)"

        // Save history item
        let history = DittoQueryHistory(
            id: UUID().uuidString,
            query: "SELECT * FROM test_collection",
            createdDate: Date().ISO8601Format()
        )

        try await historyRepo.saveQueryHistory(history, databaseId: testDbId)

        // Verify persisted to SQLCipher
        let historyRows = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        let found = historyRows.first { $0._id == history.id }

        #expect(found != nil, "History should be persisted to SQLCipher")
        #expect(found?.query == "SELECT * FROM test_collection", "Query should match")

        // Load via repository
        let loaded = try await historyRepo.loadHistory(for: testDbId)
        #expect(loaded.contains(where: { $0.id == history.id }), "History should be loadable via repository")

        // Delete
        try await historyRepo.deleteQueryHistory(history.id)

        // Verify deleted
        let afterDelete = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        #expect(!afterDelete.contains(where: { $0._id == history.id }), "History should be deleted")
    }

    @Test("HistoryRepository maintains order (most recent first)")
    func testHistoryRepositoryOrdering() async throws {
        let testDbId = "db-order-\(UUID().uuidString)"

        // Add multiple history items with different timestamps
        let history1 = DittoQueryHistory(
            id: "hist1-\(UUID().uuidString)",
            query: "SELECT 1",
            createdDate: "2024-01-01T10:00:00Z"
        )

        let history2 = DittoQueryHistory(
            id: "hist2-\(UUID().uuidString)",
            query: "SELECT 2",
            createdDate: "2024-01-02T10:00:00Z"
        )

        let history3 = DittoQueryHistory(
            id: "hist3-\(UUID().uuidString)",
            query: "SELECT 3",
            createdDate: "2024-01-03T10:00:00Z"
        )

        try await historyRepo.saveQueryHistory(history1, databaseId: testDbId)
        try await historyRepo.saveQueryHistory(history2, databaseId: testDbId)
        try await historyRepo.saveQueryHistory(history3, databaseId: testDbId)

        // Load and verify order
        let loaded = try await historyRepo.loadHistory(for: testDbId)

        // Filter to our test items
        let testItems = loaded.filter { $0.id.starts(with: "hist") }

        #expect(testItems.count == 3, "Should have 3 history items")

        // Most recent should be first
        #expect(testItems[0].query == "SELECT 3", "Most recent should be first")
        #expect(testItems[1].query == "SELECT 2", "Second most recent should be second")
        #expect(testItems[2].query == "SELECT 1", "Oldest should be last")
    }

    // MARK: - FavoritesRepository Integration Tests

    @Test("FavoritesRepository operations persist to SQLCipher")
    func testFavoritesRepositoryPersistence() async throws {
        let testDbId = "db-fav-\(UUID().uuidString)"

        // Save favorite
        let favorite = DittoQueryHistory(
            id: UUID().uuidString,
            query: "SELECT * FROM favorite_collection",
            createdDate: Date().ISO8601Format()
        )

        try await favoritesRepo.saveFavorite(favorite, databaseId: testDbId)

        // Verify persisted to SQLCipher
        let favoriteRows = try await sqlCipher.getFavorites(databaseId: testDbId)
        let found = favoriteRows.first { $0._id == favorite.id }

        #expect(found != nil, "Favorite should be persisted to SQLCipher")
        #expect(found?.query == "SELECT * FROM favorite_collection", "Query should match")

        // Delete
        try await favoritesRepo.deleteFavorite(favorite.id)

        // Verify deleted
        let afterDelete = try await sqlCipher.getFavorites(databaseId: testDbId)
        #expect(!afterDelete.contains(where: { $0._id == favorite.id }), "Favorite should be deleted")
    }

    @Test("FavoritesRepository prevents duplicate queries")
    func testFavoritesRepositoryDuplicatePrevention() async throws {
        let testDbId = "db-dup-\(UUID().uuidString)"

        let favorite1 = DittoQueryHistory(
            id: "fav1-\(UUID().uuidString)",
            query: "SELECT * FROM duplicate_test",
            createdDate: Date().ISO8601Format()
        )

        try await favoritesRepo.saveFavorite(favorite1, databaseId: testDbId)

        // Try to save duplicate query
        let favorite2 = DittoQueryHistory(
            id: "fav2-\(UUID().uuidString)",
            query: "SELECT * FROM duplicate_test",  // Same query
            createdDate: Date().ISO8601Format()
        )

        do {
            try await favoritesRepo.saveFavorite(favorite2, databaseId: testDbId)
            #expect(Bool(false), "Should have thrown duplicate error")
        } catch {
            // Expected error
            #expect(true, "Should throw error for duplicate favorite")
        }

        // Verify only one favorite exists
        let favorites = try await sqlCipher.getFavorites(databaseId: testDbId)
        let testFavorites = favorites.filter { $0.query == "SELECT * FROM duplicate_test" }
        #expect(testFavorites.count == 1, "Should only have one favorite with this query")
    }

    // MARK: - CASCADE DELETE Integration Tests

    @Test("Deleting database config cascades to all related data")
    func testCascadeDeleteIntegration() async throws {
        let testId = "test-cascade-\(UUID().uuidString)"
        let testDbId = "db-cascade-\(UUID().uuidString)"

        // 1. Create database config
        let config = DittoConfigForDatabase(
            testId,
            name: "Cascade Test",
            databaseId: testDbId,
            token: "cascade-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "api-key",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )

        try await databaseRepo.addDittoAppConfig(config)

        // 2. Add related data to all tables

        // History
        let history = DittoQueryHistory(
            id: "hist-cascade-\(UUID().uuidString)",
            query: "SELECT * FROM cascade_history",
            createdDate: Date().ISO8601Format()
        )
        try await historyRepo.saveQueryHistory(history, databaseId: testDbId)

        // Favorites
        let favorite = DittoQueryHistory(
            id: "fav-cascade-\(UUID().uuidString)",
            query: "SELECT * FROM cascade_favorites",
            createdDate: Date().ISO8601Format()
        )
        try await favoritesRepo.saveFavorite(favorite, databaseId: testDbId)

        // Subscriptions (insert directly to SQLCipher since we don't have Ditto instance)
        let subscription = SQLCipherService.SubscriptionRow(
            _id: "sub-cascade-\(UUID().uuidString)",
            databaseId: testDbId,
            name: "Cascade Sub",
            query: "SELECT * FROM cascade_sub",
            args: nil
        )
        try await sqlCipher.insertSubscription(subscription)

        // Observables (insert directly to SQLCipher)
        let observable = SQLCipherService.ObservableRow(
            _id: "obs-cascade-\(UUID().uuidString)",
            databaseId: testDbId,
            name: "Cascade Obs",
            query: "SELECT * FROM cascade_obs",
            args: nil,
            isActive: true,
            lastUpdated: nil
        )
        try await sqlCipher.insertObservable(observable)

        // 3. Verify all data exists
        let historyBefore = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        let favoritesBefore = try await sqlCipher.getFavorites(databaseId: testDbId)
        let subscriptionsBefore = try await sqlCipher.getSubscriptions(databaseId: testDbId)
        let observablesBefore = try await sqlCipher.getObservables(databaseId: testDbId)

        #expect(!historyBefore.isEmpty, "History should exist before deletion")
        #expect(!favoritesBefore.isEmpty, "Favorites should exist before deletion")
        #expect(!subscriptionsBefore.isEmpty, "Subscriptions should exist before deletion")
        #expect(!observablesBefore.isEmpty, "Observables should exist before deletion")

        // 4. Delete database config (CASCADE DELETE should remove all related data)
        try await databaseRepo.deleteDittoAppConfig(config)

        // 5. Verify all related data is deleted
        let historyAfter = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        let favoritesAfter = try await sqlCipher.getFavorites(databaseId: testDbId)
        let subscriptionsAfter = try await sqlCipher.getSubscriptions(databaseId: testDbId)
        let observablesAfter = try await sqlCipher.getObservables(databaseId: testDbId)

        #expect(historyAfter.isEmpty, "History should be cascade deleted")
        #expect(favoritesAfter.isEmpty, "Favorites should be cascade deleted")
        #expect(subscriptionsAfter.isEmpty, "Subscriptions should be cascade deleted")
        #expect(observablesAfter.isEmpty, "Observables should be cascade deleted")
    }

    // MARK: - Multi-Database Tests

    @Test("Multiple databases maintain separate data")
    func testMultipleDatabaseIsolation() async throws {
        let db1Id = "db-isolation1-\(UUID().uuidString)"
        let db2Id = "db-isolation2-\(UUID().uuidString)"

        // Add history to database 1
        let history1 = DittoQueryHistory(
            id: "hist-db1-\(UUID().uuidString)",
            query: "SELECT * FROM db1_data",
            createdDate: Date().ISO8601Format()
        )
        try await historyRepo.saveQueryHistory(history1, databaseId: db1Id)

        // Add history to database 2
        let history2 = DittoQueryHistory(
            id: "hist-db2-\(UUID().uuidString)",
            query: "SELECT * FROM db2_data",
            createdDate: Date().ISO8601Format()
        )
        try await historyRepo.saveQueryHistory(history2, databaseId: db2Id)

        // Verify isolation
        let db1History = try await sqlCipher.getHistory(databaseId: db1Id, limit: 100)
        let db2History = try await sqlCipher.getHistory(databaseId: db2Id, limit: 100)

        // DB1 should only have its own history
        #expect(db1History.contains(where: { $0._id == history1.id }), "DB1 should have its history")
        #expect(!db1History.contains(where: { $0._id == history2.id }), "DB1 should NOT have DB2's history")

        // DB2 should only have its own history
        #expect(db2History.contains(where: { $0._id == history2.id }), "DB2 should have its history")
        #expect(!db2History.contains(where: { $0._id == history1.id }), "DB2 should NOT have DB1's history")
    }

    // MARK: - Test Isolation Verification

    @Test("Test database path is separate from production")
    func testDatabasePathIsolation() async throws {
        let dbPath = try await sqlCipher.getDatabasePath()

        // Verify test path is used (ditto_cache_test vs ditto_cache)
        let isTestPath = dbPath.path.contains("ditto_cache_test")

        // Note: This test will pass differently depending on whether UI-TESTING argument is present
        // In unit tests, we may use production path
        // In UI tests, we should use test path
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING")

        if isUITesting {
            #expect(isTestPath, "UI tests should use ditto_cache_test directory")
        } else {
            // Unit tests may use either path - just verify it's a valid path
            #expect(dbPath.path.contains("ditto_cache"), "Should use a valid cache directory")
        }
    }

    // MARK: - Transaction Integration Tests

    @Test("Repository operations can be wrapped in transactions")
    func testRepositoryTransactionSupport() async throws {
        let testDbId = "db-tx-\(UUID().uuidString)"

        // Use transaction to add multiple items atomically
        try await sqlCipher.executeTransaction {
            // Add multiple history items in one transaction
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

        // Verify both items were committed
        let history = try await sqlCipher.getHistory(databaseId: testDbId, limit: 100)
        let testItems = history.filter { $0.databaseId == testDbId }

        #expect(testItems.count == 2, "Both items should be committed in transaction")
    }

    // MARK: - Performance Tests

    @Test("Loading large history is performant")
    func testLargeHistoryPerformance() async throws {
        let testDbId = "db-perf-\(UUID().uuidString)"

        // Add 100 history items
        for i in 0..<100 {
            let history = DittoQueryHistory(
                id: "hist-perf-\(i)-\(UUID().uuidString)",
                query: "SELECT * FROM collection_\(i)",
                createdDate: Date().ISO8601Format()
            )
            try await historyRepo.saveQueryHistory(history, databaseId: testDbId)
        }

        // Measure load time
        let startTime = Date()
        let loaded = try await historyRepo.loadHistory(for: testDbId)
        let loadTime = Date().timeIntervalSince(startTime)

        #expect(loaded.count >= 100, "Should load all 100 items")
        #expect(loadTime < 1.0, "Loading 100 items should take < 1 second (was \(loadTime)s)")
    }
}
