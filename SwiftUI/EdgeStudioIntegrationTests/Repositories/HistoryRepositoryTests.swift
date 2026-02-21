import Testing
@testable import Ditto_Edge_Studio

/// Helper: inserts a parent DatabaseConfigRow into SQLCipher to satisfy the
/// FOREIGN KEY constraint on the `history.databaseId` column.
private func insertHistoryParentConfig(dbId: String) async throws {
    try await SQLCipherContext.current.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
        _id: TestHelpers.uniqueTestId(),
        name: "TestDB",
        databaseId: dbId,
        mode: "server",
        allowUntrustedCerts: false,
        isBluetoothLeEnabled: true,
        isLanEnabled: true,
        isAwdlEnabled: true,
        isCloudSyncEnabled: true,
        token: "",
        authUrl: "",
        websocketUrl: "",
        httpApiUrl: "",
        httpApiKey: "",
        secretKey: ""
    ))
}

/// Comprehensive test suite for HistoryRepository
///
/// Tests cover:
/// - Load: fresh DB returns empty, load after save returns items, scoped by databaseId
/// - Save: save persists entry, saving same query replaces with new timestamp
/// - Delete: delete removes single item, delete non-existent is safe
/// - Clear: clearQueryHistory removes all items for current database only
/// - Cache: clearCache resets in-memory state, next loadHistory re-fetches
/// - Observer: setOnHistoryUpdate callback fires on save and delete
///
/// Uses .serialized because all tests share SQLCipherService.shared.
/// Each test calls setupFreshDatabase() for isolation.
/// Target: 80% code coverage for HistoryRepository.
@Suite("HistoryRepository Tests", .serialized)
struct HistoryRepositoryTests {

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {

        @Test("Fresh database returns empty history", .tags(.repository, .database))
        func testFreshDatabaseEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-repo-empty")

                // ACT
                let history = try await repo.loadHistory(for: dbId)

                // ASSERT
                #expect(history.isEmpty)
            }
        }

        @Test("Load returns item saved before load", .tags(.repository, .database))
        func testLoadAfterSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-repo-load")
                try await insertHistoryParentConfig(dbId: dbId)

                // Load first to set currentDatabaseId
                _ = try await repo.loadHistory(for: dbId)

                let entry = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT * FROM cars",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await repo.saveQueryHistory(entry)
                let history = try await repo.loadHistory(for: dbId)

                // ASSERT
                #expect(history.count == 1)
                #expect(history[0].query == "SELECT * FROM cars")
            }
        }

        @Test("History is scoped per databaseId", .tags(.repository, .database))
        func testHistoryScopedByDatabase() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "hist-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "hist-scope-2")

                // Save to dbId1
                try await insertHistoryParentConfig(dbId: dbId1)
                _ = try await repo.loadHistory(for: dbId1)
                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q-DB1", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1)

                // Switch to dbId2 — should see empty
                let history2 = try await repo.loadHistory(for: dbId2)

                // ASSERT
                #expect(history2.isEmpty)
            }
        }

        @Test("Multiple entries are returned in load", .tags(.repository, .database))
        func testLoadMultipleEntries() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-multi")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                // ACT — save 3 distinct queries
                for i in 1 ... 3 {
                    let entry = DittoQueryHistory(
                        id: TestHelpers.uniqueTestId(),
                        query: "SELECT \(i) FROM table\(i)",
                        createdDate: Date().ISO8601Format()
                    )
                    try await repo.saveQueryHistory(entry)
                }
                let history = try await repo.loadHistory(for: dbId)

                // ASSERT
                #expect(history.count == 3)
            }
        }
    }

    // MARK: - Save Tests

    @Suite("Save")
    struct SaveTests {

        @Test("Save query is persisted to SQLCipher", .tags(.repository, .database))
        func testSavePersistsToDisk() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-persist")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT * FROM orders",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await repo.saveQueryHistory(entry)

                // Verify via SQLCipher directly
                let service = SQLCipherContext.current
                let rows = try await service.getHistory(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].query == "SELECT * FROM orders")
            }
        }

        @Test("Saving same query replaces existing entry (no duplicate)", .tags(.repository, .database))
        func testSaveSameQueryNoDuplicate() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-dedup")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let query = "SELECT * FROM users"
                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())
                let entry2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())

                // ACT
                try await repo.saveQueryHistory(entry1)
                try await repo.saveQueryHistory(entry2)

                let history = try await repo.loadHistory(for: dbId)

                // ASSERT — only one entry (deduplication)
                #expect(history.count == 1)
            }
        }

        @Test("Save without prior load throws InvalidStateError", .tags(.repository, .database))
        func testSaveWithoutLoadThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                // Clear any cached state
                await repo.clearCache()

                let entry = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT 1",
                    createdDate: Date().ISO8601Format()
                )

                // ACT & ASSERT — should throw because no currentDatabaseId
                await #expect(throws: (any Error).self) {
                    try await repo.saveQueryHistory(entry)
                }
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes specific item", .tags(.repository, .database))
        func testDeleteRemovesItem() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-del")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT * FROM items",
                    createdDate: Date().ISO8601Format()
                )
                try await repo.saveQueryHistory(entry)

                // ACT
                let idToDelete = try await repo.loadHistory(for: dbId).first!.id
                try await repo.deleteQueryHistory(idToDelete)

                // ASSERT
                let history = try await repo.loadHistory(for: dbId)
                #expect(history.isEmpty)
            }
        }

        @Test("Delete non-existent ID is safe (no crash)", .tags(.repository, .database))
        func testDeleteNonExistentIsSafe() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-del-noexist")
                _ = try await repo.loadHistory(for: dbId)

                // ACT & ASSERT — deleting non-existent ID should not throw
                try await repo.deleteQueryHistory("non-existent-id-\(UUID().uuidString)")
            }
        }

        @Test("Delete one entry does not remove others", .tags(.repository, .database))
        func testDeleteOneDoesNotRemoveOthers() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-del-partial")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT 1", createdDate: Date().ISO8601Format())
                let entry2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT 2", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1)
                try await repo.saveQueryHistory(entry2)

                let loaded = try await repo.loadHistory(for: dbId)
                let idToDelete = loaded.last!.id // delete the older one

                // ACT
                try await repo.deleteQueryHistory(idToDelete)

                // ASSERT
                let remaining = try await repo.loadHistory(for: dbId)
                #expect(remaining.count == 1)
            }
        }
    }

    // MARK: - Clear Tests

    @Suite("Clear")
    struct ClearTests {

        @Test("clearQueryHistory removes all items for current database", .tags(.repository, .database))
        func testClearRemovesAll() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-clear")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                for i in 1 ... 3 {
                    let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT \(i)", createdDate: Date().ISO8601Format())
                    try await repo.saveQueryHistory(entry)
                }

                // ACT
                try await repo.clearQueryHistory()

                // ASSERT
                let history = try await repo.loadHistory(for: dbId)
                #expect(history.isEmpty)
            }
        }

        @Test("clearQueryHistory does not remove items for other databases", .tags(.repository, .database))
        func testClearScopedToCurrentDatabase() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "hist-clear-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "hist-clear-2")

                // Add to dbId1
                try await insertHistoryParentConfig(dbId: dbId1)
                _ = try await repo.loadHistory(for: dbId1)
                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q1", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1)

                // Add to dbId2
                try await insertHistoryParentConfig(dbId: dbId2)
                _ = try await repo.loadHistory(for: dbId2)
                let entry2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q2", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry2)

                // Clear while on dbId2
                try await repo.clearQueryHistory()

                // ASSERT — dbId1 items still exist
                let remaining1 = try await repo.loadHistory(for: dbId1)
                #expect(remaining1.count == 1)
                #expect(remaining1[0].query == "Q1")
            }
        }
    }

    // MARK: - Cache Tests

    @Suite("Cache")
    struct CacheTests {

        @Test("clearCache resets currentDatabaseId so save throws", .tags(.repository, .database))
        func testClearCacheResetsDatabaseId() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-cache")
                _ = try await repo.loadHistory(for: dbId)

                // ACT
                await repo.clearCache()

                // ASSERT — trying to save without loading should now throw
                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q", createdDate: Date().ISO8601Format())
                await #expect(throws: (any Error).self) {
                    try await repo.saveQueryHistory(entry)
                }
            }
        }

        @Test("After clearCache load re-fetches from disk", .tags(.repository, .database))
        func testLoadAfterClearCacheRefetchesFromDisk() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-cache-refetch")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)
                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "CACHED Q", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry)

                // ACT — clear cache then reload
                await repo.clearCache()
                let history = try await repo.loadHistory(for: dbId)

                // ASSERT — data is still present on disk
                #expect(history.count == 1)
                #expect(history[0].query == "CACHED Q")
            }
        }
    }

    // MARK: - Observer Tests

    @Suite("Observer Callback")
    struct ObserverCallbackTests {

        @Test("setOnHistoryUpdate callback fires when entry is saved", .tags(.repository, .database))
        func testCallbackFiresOnSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-obs-save")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                var callbackResult: [DittoQueryHistory] = []
                await repo.setOnHistoryUpdate { history in
                    callbackResult = history
                }

                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "OBS-Q", createdDate: Date().ISO8601Format())

                // ACT
                try await repo.saveQueryHistory(entry)

                // ASSERT — callback should have been called with the new item
                #expect(callbackResult.count == 1)
                #expect(callbackResult[0].query == "OBS-Q")
            }
        }

        @Test("setOnHistoryUpdate callback fires when entry is deleted", .tags(.repository, .database))
        func testCallbackFiresOnDelete() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-obs-del")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL-Q", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry)

                var callbackCount = 0
                await repo.setOnHistoryUpdate { _ in
                    callbackCount += 1
                }

                // ACT
                let loaded = try await repo.loadHistory(for: dbId)
                try await repo.deleteQueryHistory(loaded.first!.id)

                // ASSERT
                #expect(callbackCount >= 1)
            }
        }
    }
}
