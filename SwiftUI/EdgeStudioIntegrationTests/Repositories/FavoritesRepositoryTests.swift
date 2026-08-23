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
        httpApiUrl: "",
        httpApiKey: "",
        secretKey: "",
        logLevel: "info"
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
        @Test(.tags(.repository, .database))
        func `Fresh database returns empty favorites`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Load returns item saved before load`() async throws {
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
                try await repo.saveFavorite(fav, databaseId: dbId)
                let favorites = try await repo.loadFavorites(for: dbId)

                // ASSERT
                #expect(favorites.count == 1)
                #expect(favorites[0].query == "SELECT * FROM products")
            }
        }

        @Test(.tags(.repository, .database))
        func `Favorites are scoped per databaseId`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId1 = TestHelpers.uniqueTestId(prefix: "fav-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "fav-scope-2")

                // Save to dbId1
                try await insertFavoritesParentConfig(dbId: dbId1)
                _ = try await repo.loadFavorites(for: dbId1)
                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "FAV-Q1", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav, databaseId: dbId1)

                // Switch to dbId2 — should see empty
                let favs2 = try await repo.loadFavorites(for: dbId2)

                // ASSERT
                #expect(favs2.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Multiple favorites are all returned`() async throws {
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
                    try await repo.saveFavorite(fav, databaseId: dbId)
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
        @Test(.tags(.repository, .database))
        func `Saved favorite is persisted to SQLCipher`() async throws {
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
                try await repo.saveFavorite(fav, databaseId: dbId)

                // Verify via SQLCipher directly
                let service = SQLCipherContext.current
                let rows = try await service.getFavorites(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].query == "SELECT * FROM inventory")
            }
        }

        @Test(.tags(.repository, .database))
        func `Saving duplicate query throws InvalidStateError`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-dup")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let query = "SELECT * FROM users"
                let fav1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())
                let fav2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: query, createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav1, databaseId: dbId)

                // ACT & ASSERT — saving same query should throw
                await #expect(throws: (any Error).self) {
                    try await repo.saveFavorite(fav2, databaseId: dbId)
                }
            }
        }

        @Test(.tags(.repository, .database))
        func `Save without prior load throws InvalidStateError`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                await repo.clearCache()

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "Q", createdDate: Date().ISO8601Format())

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.saveFavorite(fav, databaseId: "no-active-session")
                }
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {
        @Test(.tags(.repository, .database))
        func `Delete removes specific favorite`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL Q", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav, databaseId: dbId)

                // ACT
                let loaded = try await repo.loadFavorites(for: dbId)
                try await repo.deleteFavorite(loaded.first!.id)

                // ASSERT
                let remaining = try await repo.loadFavorites(for: dbId)
                #expect(remaining.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Delete non-existent ID is safe`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del-noexist")
                _ = try await repo.loadFavorites(for: dbId)

                // ACT & ASSERT — should not throw
                try await repo.deleteFavorite("non-existent-\(UUID().uuidString)")
            }
        }

        @Test(.tags(.repository, .database))
        func `Delete one entry does not remove others`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-del-partial")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav1 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "KEEP THIS", createdDate: Date().ISO8601Format())
                let fav2 = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "REMOVE THIS", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav1, databaseId: dbId)
                try await repo.saveFavorite(fav2, databaseId: dbId)

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
        @Test(.tags(.repository, .database))
        func `clearCache resets currentDatabaseId so save throws`() async throws {
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
                    try await repo.saveFavorite(fav, databaseId: dbId)
                }
            }
        }

        @Test(.tags(.repository, .database))
        func `After clearCache load re-fetches from disk`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-cache-refetch")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "PERSISTED FAV", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav, databaseId: dbId)

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
        @Test(.tags(.repository, .database))
        func `setOnFavoritesUpdate callback fires when favorite is saved`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-obs-save")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let callbackResult = TestBox<[DittoQueryHistory]>([])
                await repo.setOnFavoritesUpdate { favorites in
                    callbackResult.value = favorites
                }

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "OBS-FAV", createdDate: Date().ISO8601Format())

                // ACT
                try await repo.saveFavorite(fav, databaseId: dbId)

                // ASSERT
                #expect(callbackResult.value.count == 1)
                #expect(callbackResult.value[0].query == "OBS-FAV")
            }
        }

        @Test(.tags(.repository, .database))
        func `setOnFavoritesUpdate callback fires when favorite is deleted`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = FavoritesRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "fav-obs-del")
                try await insertFavoritesParentConfig(dbId: dbId)
                _ = try await repo.loadFavorites(for: dbId)

                let fav = DittoQueryHistory(id: TestHelpers.uniqueTestId(), query: "DEL-FAV", createdDate: Date().ISO8601Format())
                try await repo.saveFavorite(fav, databaseId: dbId)

                let callbackCount = TestCounter()
                await repo.setOnFavoritesUpdate { _ in
                    callbackCount.increment()
                }

                let loaded = try await repo.loadFavorites(for: dbId)

                // ACT
                try await repo.deleteFavorite(loaded.first!.id)

                // ASSERT
                #expect(callbackCount.value >= 1)
            }
        }
    }
}
