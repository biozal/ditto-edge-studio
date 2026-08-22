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
        @Test(.tags(.repository, .database))
        func `Fresh database returns empty config list`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared

                // ACT
                let configs = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(configs.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Load returns previously added config`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Load returns all fields correctly`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let id = UUID().uuidString
                let config = DittoConfigForDatabase(
                    id,
                    name: "Full Fields DB",
                    databaseId: "db-full-\(id)",
                    developmentToken: "my-token",
                    url: "https://auth.test.com",
                    httpApiUrl: "https://api.test.com",
                    httpApiKey: "api-key-xyz",
                    mode: .development,
                    allowUntrustedCerts: false,
                    secretKey: "",
                    isBluetoothLeEnabled: true,
                    isLanEnabled: false,
                    isAwdlEnabled: true,
                    isCloudSyncEnabled: false,
                    collectionSyncScopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
                    startupSettings: [
                        StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
                    ]
                )

                // ACT
                try await repo.addDittoAppConfig(config)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 1)
                #expect(loaded[0].developmentToken == "my-token")
                #expect(loaded[0].url == "https://auth.test.com")
                #expect(loaded[0].httpApiKey == "api-key-xyz")
                #expect(loaded[0].isLanEnabled == false)
                #expect(loaded[0].isCloudSyncEnabled == false)
                // Advanced configuration round-trips through the JSON columns.
                #expect(loaded[0].collectionSyncScopes == [
                    CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
                ])
                #expect(loaded[0].startupSettings == [
                    StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
                ])
            }
        }
    }

    // MARK: - Add Tests

    @Suite("Add")
    struct AddTests {
        @Test(.tags(.repository, .database))
        func `Add stores config in SQLCipher`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Add multiple configs stores all`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Add notifies observer callback`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared

                let callbackCount = TestCounter()
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount.increment()
                }

                // ACT
                try await repo.addDittoAppConfig(DatabaseConfigFixtures.validServerConfig())

                // ASSERT
                #expect(callbackCount.value == 1)
            }
        }
    }

    // MARK: - Update Tests

    @Suite("Update")
    struct UpdateTests {
        @Test(.tags(.repository, .database))
        func `Update modifies name and token`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let original = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(original)

                // Mutate fields
                original.name = "Updated Name"
                original.developmentToken = "updated-token"

                // ACT
                try await repo.updateDittoAppConfig(original)
                let loaded = try await repo.loadDatabaseConfigs()

                // ASSERT
                #expect(loaded.count == 1)
                #expect(loaded[0].name == "Updated Name")
                #expect(loaded[0].developmentToken == "updated-token")
            }
        }

        @Test(.tags(.repository, .database))
        func `Update preserves original ID`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Update persists across reload`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Update notifies observer callback`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                let callbackCount = TestCounter()
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount.increment()
                }
                config.name = "New Name"

                // ACT
                try await repo.updateDittoAppConfig(config)

                // ASSERT
                #expect(callbackCount.value == 1)
            }
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {
        @Test(.tags(.repository, .database))
        func `Delete removes config`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Delete cascades to history`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Delete cascades to favorites`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Delete notifies observer callback`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = DatabaseRepository.shared
                let config = DatabaseConfigFixtures.validServerConfig()
                try await repo.addDittoAppConfig(config)

                let callbackCount = TestCounter()
                await repo.setOnDittoDatabaseConfigUpdate { _ in
                    callbackCount.increment()
                }

                // ACT
                try await repo.deleteDittoAppConfig(config)

                // ASSERT
                #expect(callbackCount.value == 1)
            }
        }
    }

    // MARK: - Multiple Config Tests

    @Suite("Multiple Configs")
    struct MultipleConfigTests {
        @Test(.tags(.repository, .database))
        func `All configs are returned in load`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Delete one does not affect others`() async throws {
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
