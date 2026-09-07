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
        httpApiUrl: "",
        httpApiKey: "",
        secretKey: "",
        logLevel: "info"
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
        @Test(.tags(.repository, .database))
        func `Fresh database returns empty history`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Load returns item saved before load`() async throws {
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
                try await repo.saveQueryHistory(entry, databaseId: dbId)
                let history = try await repo.loadHistory(for: dbId)

                // ASSERT
                #expect(history.count == 1)
                #expect(history[0].query == "SELECT * FROM cars")
            }
        }

        @Test(.tags(.repository, .database))
        func `History is scoped per databaseId`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "hist-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "hist-scope-2")

                // Save to dbId1
                try await insertHistoryParentConfig(dbId: dbId1)
                _ = try await repo.loadHistory(for: dbId1)
                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q-DB1", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1, databaseId: dbId1)

                // Switch to dbId2 — should see empty
                let history2 = try await repo.loadHistory(for: dbId2)

                // ASSERT
                #expect(history2.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Multiple entries are returned in load`() async throws {
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
                    try await repo.saveQueryHistory(entry, databaseId: dbId)
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
        @Test(.tags(.repository, .database))
        func `Save query is persisted to SQLCipher`() async throws {
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
                try await repo.saveQueryHistory(entry, databaseId: dbId)

                // Verify via SQLCipher directly
                let service = SQLCipherContext.current
                let rows = try await service.getHistory(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].query == "SELECT * FROM orders")
            }
        }

        @Test(.tags(.repository, .database))
        func `Saving same query replaces existing entry (no duplicate)`() async throws {
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
                try await repo.saveQueryHistory(entry1, databaseId: dbId)
                try await repo.saveQueryHistory(entry2, databaseId: dbId)

                let history = try await repo.loadHistory(for: dbId)

                // ASSERT — only one entry (deduplication)
                #expect(history.count == 1)
            }
        }

        @Test(.tags(.repository, .database))
        func `Save without prior load throws InvalidStateError`() async throws {
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
                    try await repo.saveQueryHistory(entry, databaseId: "no-active-session")
                }
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {
        @Test(.tags(.repository, .database))
        func `Delete removes specific item`() async throws {
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
                try await repo.saveQueryHistory(entry, databaseId: dbId)

                // ACT
                let idToDelete = try #require(try await repo.loadHistory(for: dbId).first).id
                try await repo.deleteQueryHistory(idToDelete)

                // ASSERT
                let history = try await repo.loadHistory(for: dbId)
                #expect(history.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Delete non-existent ID is safe (no crash)`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-del-noexist")
                _ = try await repo.loadHistory(for: dbId)

                // ACT & ASSERT — deleting non-existent ID should not throw
                try await repo.deleteQueryHistory("non-existent-id-\(UUID().uuidString)")
            }
        }

        @Test(.tags(.repository, .database))
        func `Delete one entry does not remove others`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-del-partial")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT 1", createdDate: Date().ISO8601Format())
                let entry2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT 2", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1, databaseId: dbId)
                try await repo.saveQueryHistory(entry2, databaseId: dbId)

                let loaded = try await repo.loadHistory(for: dbId)
                let idToDelete = try #require(loaded.last).id // delete the older one

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
        @Test(.tags(.repository, .database))
        func `clearQueryHistory removes all items for current database`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-clear")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                for i in 1 ... 3 {
                    let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "SELECT \(i)", createdDate: Date().ISO8601Format())
                    try await repo.saveQueryHistory(entry, databaseId: dbId)
                }

                // ACT
                try await repo.clearQueryHistory()

                // ASSERT
                let history = try await repo.loadHistory(for: dbId)
                #expect(history.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `clearQueryHistory does not remove items for other databases`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "hist-clear-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "hist-clear-2")

                // Add to dbId1
                try await insertHistoryParentConfig(dbId: dbId1)
                _ = try await repo.loadHistory(for: dbId1)
                let entry1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q1", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry1, databaseId: dbId1)

                // Add to dbId2
                try await insertHistoryParentConfig(dbId: dbId2)
                _ = try await repo.loadHistory(for: dbId2)
                let entry2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q2", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry2, databaseId: dbId2)

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
        @Test(.tags(.repository, .database))
        func `clearCache resets currentDatabaseId so save throws`() async throws {
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
                    try await repo.saveQueryHistory(entry, databaseId: "no-active-session")
                }
            }
        }

        @Test(.tags(.repository, .database))
        func `After clearCache load re-fetches from disk`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-cache-refetch")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)
                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "CACHED Q", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry, databaseId: dbId)

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
        @Test(.tags(.repository, .database))
        func `setOnHistoryUpdate callback fires when entry is saved`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-obs-save")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let callbackResult = TestBox<[DittoQueryHistory]>([])
                await repo.setOnHistoryUpdate { history in
                    callbackResult.value = history
                }

                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "OBS-Q", createdDate: Date().ISO8601Format())

                // ACT
                try await repo.saveQueryHistory(entry, databaseId: dbId)

                // ASSERT — callback should have been called with the new item
                #expect(callbackResult.value.count == 1)
                #expect(callbackResult.value[0].query == "OBS-Q")
            }
        }

        @Test(.tags(.repository, .database))
        func `setOnHistoryUpdate callback fires when entry is deleted`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = HistoryRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "hist-obs-del")
                try await insertHistoryParentConfig(dbId: dbId)
                _ = try await repo.loadHistory(for: dbId)

                let entry = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL-Q", createdDate: Date().ISO8601Format())
                try await repo.saveQueryHistory(entry, databaseId: dbId)

                let callbackCount = TestCounter()
                await repo.setOnHistoryUpdate { _ in
                    callbackCount.increment()
                }

                // ACT
                let loaded = try await repo.loadHistory(for: dbId)
                try await repo.deleteQueryHistory(try #require(loaded.first).id)

                // ASSERT
                #expect(callbackCount.value >= 1)
            }
        }
    }
}
