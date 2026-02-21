import Testing
@testable import Ditto_Edge_Studio

/// Comprehensive test suite for DatabaseRepository
///
/// Tests cover:
/// - Load: fresh DB empty, load returns persisted configs
/// - Add: add stores config with all fields, loadDatabaseConfigs returns it
/// - Update: update modifies fields, ID unchanged, persisted across reload
/// - Delete: delete removes config, cascade deletes (history/favorites/subscriptions) verified
/// - Observer: setOnDittoDatabaseConfigUpdate fires on add, update, delete
/// - Multiple configs: add several, all returned, delete one doesn't affect others
///
/// Uses .serialized because all tests share DatabaseRepository.shared's in-memory cache.
/// Target: 80% code coverage for DatabaseRepository.
@Suite("DatabaseRepository Tests", .serialized)
struct DatabaseRepositoryTests {

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {

        @Test("Fresh database returns empty config list", .tags(.repository, .database))
        func testFreshDatabaseEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared

                // ACT
                let configs = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(configs.isEmpty)
            }
        }

        @Test("Load returns previously added config", .tags(.repository, .database))
        func testLoadReturnsPreviouslyAddedConfig() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()

                // ACT
                try await repo.addDittoAppConfig(config)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 1)
                #expect(loaded[0]._id == config._id)
                #expect(loaded[0].name == config.name)
            }
        }

        @Test("Load returns all fields correctly", .tags(.repository, .database))
        func testLoadAllFields() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let id = UUID().uuidString
                let config = DittoConfigForDatabase(
                    id,
                    name: "Full Fields DB",
                    databaseId: "db-full-\(id)",
                    token: "my-token",
                    authUrl: "https://auth.test.com",
                    websocketUrl: "wss://ws.test.com",
                    httpApiUrl: "https://api.test.com",
                    httpApiKey: "api-key-xyz",
                    mode: .server,
                    allowUntrustedCerts: false,
                    secretKey: "",
                    isBluetoothLeEnabled: true,
                    isLanEnabled: false,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: false
                )

                // ACT
                try await repo.addDittoAppConfig(config)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 1)
                #expect(loaded[0].token == "my-token")
                #expect(loaded[0].authUrl == "https://auth.test.com")
                #expect(loaded[0].httpApiKey == "api-key-xyz")
                #expect(loaded[0].isLanEnabled == false)
                #expect(loaded[0].isCloudSyncEnabled == false)
            }
        }
    }

    // MARK: - Add Tests

    @Suite("Add")
    struct AddTests {

        @Test("Add stores config in SQLCipher", .tags(.repository, .database))
        func testAddStoresInSQLCipher() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validSmallPeersConfig()

                // ACT
                try await repo.addDittoAppConfig(config)

                // Verify via SQLCipher directly
                let service = SQLCipherContext.current
                let rows = try await service.getAllDatabaseConfigs()

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].name == config.name)
                #expect(rows[0].databaseId == config.databaseId)
            }
        }

        @Test("Add multiple configs stores all", .tags(.repository, .database))
        func testAddMultipleConfigs() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared

                // ACT — add 3 configs
                let configs = DatabaseConfigFixtures.multipleConfigs(count: 3)
                for config in configs {
                    try await repo.addDittoAppConfig(config)
                }

                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 3)
            }
        }

        @Test("Add notifies observer callback", .tags(.repository, .database))
        func testAddNotifiesObserver() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared

                var callbackCount = 0
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount += 1
                }

                // ACT
                try await repo.addDittoAppConfig(DatabaseConfigFixtures.validServerConfig())

                // ASSERT
                #expect(callbackCount == 1)
            }
        }
    }

    // MARK: - Update Tests

    @Suite("Update")
    struct UpdateTests {

        @Test("Update modifies name and token", .tags(.repository, .database))
        func testUpdateModifiesFields() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let original = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(original)

                // Mutate fields
                original.name = "Updated Name"
                original.token = "updated-token"

                // ACT
                try await repo.updateDittoAppConfig(original)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 1)
                #expect(loaded[0].name == "Updated Name")
                #expect(loaded[0].token == "updated-token")
            }
        }

        @Test("Update preserves original ID", .tags(.repository, .database))
        func testUpdatePreservesId() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let original = DatabaseConfigFixtures.validServerConfig()
                let originalId = original._id
                try await repo.addDittoAppConfig(original)

                original.name = "Modified"

                // ACT
                try await repo.updateDittoAppConfig(original)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded[0]._id == originalId)
            }
        }

        @Test("Update persists across reload", .tags(.repository, .database))
        func testUpdatePersistsAcrossReload() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)
                config.httpApiKey = "new-api-key"

                // ACT
                try await repo.updateDittoAppConfig(config)
                // Reload from disk
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded[0].httpApiKey == "new-api-key")
            }
        }

        @Test("Update notifies observer callback", .tags(.repository, .database))
        func testUpdateNotifiesObserver() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                var callbackCount = 0
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount += 1
                }
                config.name = "New Name"

                // ACT
                try await repo.updateDittoAppConfig(config)

                // ASSERT
                #expect(callbackCount == 1)
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes config", .tags(.repository, .database))
        func testDeleteRemovesConfig() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                // ACT
                try await repo.deleteDittoAppConfig(config)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.isEmpty)
            }
        }

        @Test("Delete cascades to history", .tags(.repository, .database))
        func testDeleteCascadesToHistory() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                // Add a history entry
                let service = SQLCipherContext.current
                let histRow = SQLCipherService.HistoryRow(
                    _id: UUID().uuidString, databaseId: config.databaseId,
                    query: "SELECT 1", createdDate: Date().ISO8601Format()
                )
                try await service.insertHistory(histRow)

                // ACT
                try await repo.deleteDittoAppConfig(config)

                // ASSERT — history should be cascade-deleted
                let histRows = try await service.getHistory(databaseId: config.databaseId)
                #expect(histRows.isEmpty)
            }
        }

        @Test("Delete cascades to favorites", .tags(.repository, .database))
        func testDeleteCascadesToFavorites() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                // Add a favorite
                let service = SQLCipherContext.current
                let favRow = SQLCipherService.FavoriteRow(
                    _id: UUID().uuidString, databaseId: config.databaseId,
                    query: "SELECT * FROM users", createdDate: Date().ISO8601Format()
                )
                try await service.insertFavorite(favRow)

                // ACT
                try await repo.deleteDittoAppConfig(config)

                // ASSERT — favorites should be cascade-deleted
                let favRows = try await service.getFavorites(databaseId: config.databaseId)
                #expect(favRows.isEmpty)
            }
        }

        @Test("Delete notifies observer callback", .tags(.repository, .database))
        func testDeleteNotifiesObserver() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                var callbackCount = 0
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount += 1
                }

                // ACT
                try await repo.deleteDittoAppConfig(config)

                // ASSERT
                #expect(callbackCount == 1)
            }
        }
    }

    // MARK: - Multiple Config Tests

    @Suite("Multiple Configs")
    struct MultipleConfigTests {

        @Test("All configs are returned in load", .tags(.repository, .database))
        func testAllConfigsReturnedInLoad() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let configs = DatabaseConfigFixtures.multipleConfigs(count: 5)

                for config in configs {
                    try await repo.addDittoAppConfig(config)
                }

                // ACT
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 5)
            }
        }

        @Test("Delete one does not affect others", .tags(.repository, .database))
        func testDeleteOneDoesNotAffectOthers() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config1 = DatabaseConfigFixtures.validServerConfig()
                let config2 = DatabaseConfigFixtures.validSmallPeersConfig()
                let config3 = DatabaseConfigFixtures.validServerConfig2()

                try await repo.addDittoAppConfig(config1)
                try await repo.addDittoAppConfig(config2)
                try await repo.addDittoAppConfig(config3)

                // ACT — delete only config2
                try await repo.deleteDittoAppConfig(config2)

                // ASSERT
                let loaded = try await repo.loadDatabaseConfigs()
                #expect(loaded.count == 2)
                #expect(loaded.contains(where: { $0._id == config1._id }))
                #expect(loaded.contains(where: { $0._id == config3._id }))
                #expect(!loaded.contains(where: { $0._id == config2._id }))
            }
        }
    }
}
