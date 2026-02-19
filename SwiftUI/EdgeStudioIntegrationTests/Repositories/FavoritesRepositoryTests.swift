import Testing

@testable import Ditto_Edge_Studio

/// Helper: inserts a parent DatabaseConfigRow into SQLCipher to satisfy the
/// FOREIGN KEY constraint on the `favorites.databaseId` column.
private func insertFavoritesParentConfig(dbId: String) async throws {
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

/// Comprehensive test suite for FavoritesRepository
///
/// Tests cover:
/// - Load: fresh DB returns empty, load after save, scoped by databaseId
/// - Save: save persists entry, deduplication (saving same query twice throws)
/// - Delete: delete removes single item, delete non-existent is safe
/// - Cache: clearCache resets state, next loadFavorites re-fetches from disk
/// - Observer: setOnFavoritesUpdate callback fires on save and delete
///
/// Uses .serialized because all tests share SQLCipherService.shared.
/// Target: 80% code coverage for FavoritesRepository.
@Suite("FavoritesRepository Tests", .serialized)
struct FavoritesRepositoryTests {

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {

        @Test("Fresh database returns empty favorites", .tags(.repository, .database))
        func testFreshDatabaseEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-empty")

                // ACT
                let favorites = try await repo.loadFavorites(for: dbId)

                // ASSERT
                #expect(favorites.isEmpty)
            }
        }

        @Test("Load returns item saved before load", .tags(.repository, .database))
        func testLoadAfterSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-load")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT * FROM products",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await repo.saveFavorite(fav)
                let favorites = try await repo.loadFavorites(for: dbId)

                // ASSERT
                #expect(favorites.count == 1)
                #expect(favorites[0].query == "SELECT * FROM products")
            }
        }

        @Test("Favorites are scoped per databaseId", .tags(.repository, .database))
        func testFavoritesScopedByDatabase() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "fav-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "fav-scope-2")

                // Save to dbId1
                try await insertFavoritesParentConfig(dbId: dbId1)
                _ = try await repo.loadFavorites(for: dbId1)
                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "FAV-Q1", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav)

                // Switch to dbId2 — should see empty
                let favs2 = try await repo.loadFavorites(for: dbId2)

                // ASSERT
                #expect(favs2.isEmpty)
            }
        }

        @Test("Multiple favorites are all returned", .tags(.repository, .database))
        func testLoadMultipleFavorites() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-multi")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                // ACT — save 3 distinct queries
                for i in 1 ... 3 {
                    let fav = DittoQueryHistory(
                        id: TestHelpers.uniqueTestId(),
                        query: "FAVORITE QUERY \(i)",
                        createdDate: Date().ISO8601Format()
                    )
                    try await repo.saveFavorite(fav)
                }
                let favorites = try await repo.loadFavorites(for: dbId)

                // ASSERT
                #expect(favorites.count == 3)
            }
        }
    }

    // MARK: - Save Tests

    @Suite("Save")
    struct SaveTests {

        @Test("Saved favorite is persisted to SQLCipher", .tags(.repository, .database))
        func testSavePersistsToDisk() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-persist")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(
                    id: TestHelpers.uniqueTestId(),
                    query: "SELECT * FROM inventory",
                    createdDate: Date().ISO8601Format()
                )

                // ACT
                try await repo.saveFavorite(fav)

                // Verify via SQLCipher directly
                let service = SQLCipherContext.current
                let rows = try await service.getFavorites(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].query == "SELECT * FROM inventory")
            }
        }

        @Test("Saving duplicate query throws InvalidStateError", .tags(.repository, .database))
        func testSaveDuplicateThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-dup")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let query = "SELECT * FROM users"
                let fav1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())
                let fav2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav1)

                // ACT & ASSERT — saving same query should throw
                await #expect(throws: (any Error).self) {
                    try await repo.saveFavorite(fav2)
                }
            }
        }

        @Test("Save without prior load throws InvalidStateError", .tags(.repository, .database))
        func testSaveWithoutLoadThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                await repo.clearCache()

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q", createdDate: Date().ISO8601Format())

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.saveFavorite(fav)
                }
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes specific favorite", .tags(.repository, .database))
        func testDeleteRemovesFavorite() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL Q", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav)

                // ACT
                let loaded = try await repo.loadFavorites(for: dbId)
                try await repo.deleteFavorite(loaded.first!.id)

                // ASSERT
                let remaining = try await repo.loadFavorites(for: dbId)
                #expect(remaining.isEmpty)
            }
        }

        @Test("Delete non-existent ID is safe", .tags(.repository, .database))
        func testDeleteNonExistentIsSafe() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del-noexist")
                _ = try await repo.loadFavorites(for: dbId)

                // ACT & ASSERT — should not throw
                try await repo.deleteFavorite("non-existent-\(UUID().uuidString)")
            }
        }

        @Test("Delete one entry does not remove others", .tags(.repository, .database))
        func testDeleteOnePreservesOthers() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del-partial")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "KEEP THIS", createdDate: Date().ISO8601Format())
                let fav2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "REMOVE THIS", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav1)
                try await repo.saveFavorite(fav2)

                let all = try await repo.loadFavorites(for: dbId)
                let toDelete = all.first(where: { $0.query == "REMOVE THIS" })!.id

                // ACT
                try await repo.deleteFavorite(toDelete)

                // ASSERT
                let remaining = try await repo.loadFavorites(for: dbId)
                #expect(remaining.count == 1)
                #expect(remaining[0].query == "KEEP THIS")
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
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-cache-reset")
                _ = try await repo.loadFavorites(for: dbId)

                // ACT
                await repo.clearCache()

                // ASSERT — saving should now throw (no currentDatabaseId)
                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q", createdDate: Date().ISO8601Format())
                await #expect(throws: (any Error).self) {
                    try await repo.saveFavorite(fav)
                }
            }
        }

        @Test("After clearCache load re-fetches from disk", .tags(.repository, .database))
        func testLoadAfterClearCacheRefetchesFromDisk() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-cache-refetch")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "PERSISTED FAV", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav)

                // ACT — clear cache and reload
                await repo.clearCache()
                let favorites = try await repo.loadFavorites(for: dbId)

                // ASSERT
                #expect(favorites.count == 1)
                #expect(favorites[0].query == "PERSISTED FAV")
            }
        }
    }

    // MARK: - Observer Tests

    @Suite("Observer Callback")
    struct ObserverCallbackTests {

        @Test("setOnFavoritesUpdate callback fires when favorite is saved", .tags(.repository, .database))
        func testCallbackFiresOnSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-obs-save")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                var callbackResult: [DittoQueryHistory] = []
                await repo.setOnFavoritesUpdate { favorites in
                    callbackResult = favorites
                }

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "OBS-FAV", createdDate: Date().ISO8601Format())

                // ACT
                try await repo.saveFavorite(fav)

                // ASSERT
                #expect(callbackResult.count == 1)
                #expect(callbackResult[0].query == "OBS-FAV")
            }
        }

        @Test("setOnFavoritesUpdate callback fires when favorite is deleted", .tags(.repository, .database))
        func testCallbackFiresOnDelete() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-obs-del")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL-FAV", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav)

                var callbackCount = 0
                await repo.setOnFavoritesUpdate { _ in
                    callbackCount += 1
                }

                let loaded = try await repo.loadFavorites(for: dbId)

                // ACT
                try await repo.deleteFavorite(loaded.first!.id)

                // ASSERT
                #expect(callbackCount >= 1)
            }
        }
    }
}
