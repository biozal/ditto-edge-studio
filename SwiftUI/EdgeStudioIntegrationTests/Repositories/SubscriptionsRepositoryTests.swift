import Testing
@testable import Ditto_Edge_Studio

/// Comprehensive test suite for SubscriptionsRepository
///
/// Tests cover the SQLCipher persistence layer. Live Ditto sync registration
/// uses `dittoSelectedApp?.sync.registerSubscription()` which is nil in unit
/// tests, so only metadata persistence is tested here.
///
/// - Load: fresh DB empty, load scoped by databaseId, load after save returns items
/// - Save: saves subscription metadata to SQLCipher (syncSubscription is nil)
/// - Remove: removes metadata from SQLCipher, nil syncSubscription cancel is safe
/// - ClearCache: resets in-memory state
/// - Observer: callback fires on save and remove
///
/// Uses .serialized because all tests share SQLCipherService.shared.
/// Target: 50% code coverage.
@Suite("SubscriptionsRepository Tests", .serialized)
struct SubscriptionsRepositoryTests {

    // Helper to insert a parent database config so FK constraint is satisfied
    private func insertDatabaseConfig(_ dbId: String) async throws {
        let service = SQLCipherContext.current
        let row = SQLCipherService.DatabaseConfigRow(
            _id: UUID().uuidString, name: "Test DB", databaseId: dbId,
            mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
            isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
            token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
        )
        try await service.insertDatabaseConfig(row)
    }

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {

        @Test("Fresh database returns empty subscription list", .tags(.repository, .database))
        func testFreshDatabaseEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = SubscriptionsRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-repo-empty")

                // ACT
                let subs = try await repo.loadSubscriptions(for: dbId)

                // ASSERT
                #expect(subs.isEmpty)
            }
        }

        @Test("Load returns subscriptions scoped by databaseId", .tags(.repository, .database))
        func testLoadScopedByDatabase() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId1 = TestHelpers.uniqueTestId(prefix: "sub-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "sub-scope-2")

                // Insert parent configs
                let row1 = SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                )
                let row2 = SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                )
                try await service.insertDatabaseConfig(row1)
                try await service.insertDatabaseConfig(row2)

                // Insert subscription only for dbId1
                let subRow = SQLCipherService.SubscriptionRow(
                    _id: UUID().uuidString, databaseId: dbId1,
                    name: "Sub1", query: "SELECT 1", args: nil
                )
                try await service.insertSubscription(subRow)

                let repo = SubscriptionsRepository.shared

                // ACT
                let subs1 = try await repo.loadSubscriptions(for: dbId1)
                let subs2 = try await repo.loadSubscriptions(for: dbId2)

                // ASSERT
                #expect(subs1.count == 1)
                #expect(subs1[0].name == "Sub1")
                #expect(subs2.isEmpty)
            }
        }

        @Test("Loaded subscriptions have nil syncSubscription", .tags(.repository, .database))
        func testLoadedSubscriptionsHaveNilSyncSubscription() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-nil-sync")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertSubscription(SQLCipherService.SubscriptionRow(
                    _id: UUID().uuidString, databaseId: dbId, name: "S", query: "SELECT 1", args: nil
                ))

                // ACT
                let repo = SubscriptionsRepository.shared
                let subs = try await repo.loadSubscriptions(for: dbId)

                // ASSERT — syncSubscription is not persisted and remains nil
                #expect(subs[0].syncSubscription == nil)
            }
        }
    }

    // MARK: - Save Tests

    @Suite("Save")
    struct SaveTests {

        @Test("Save persists subscription metadata to SQLCipher", .tags(.repository, .database))
        func testSavePersistsToSQLCipher() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "My Sub"
                sub.query = "SELECT * FROM products"

                // ACT
                try await repo.saveDittoSubscription(sub)

                // Verify via SQLCipher directly
                let rows = try await service.getSubscriptions(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].name == "My Sub")
                #expect(rows[0].query == "SELECT * FROM products")
            }
        }

        @Test("Save without prior load throws InvalidStateError", .tags(.repository, .database))
        func testSaveWithoutLoadThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = SubscriptionsRepository.shared
                await repo.clearCache()

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Test"
                sub.query = "SELECT 1"

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoSubscription(sub)
                }
            }
        }

        @Test("Saving existing ID updates in-memory cache", .tags(.repository, .database))
        func testSavingExistingIdUpdatesCacheNotDuplicate() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-save-dup")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                let subId = TestHelpers.uniqueTestId()
                var sub = DittoSubscription(id: subId)
                sub.name = "Original"
                sub.query = "SELECT 1"

                // ACT — save once (inserts into DB) then save same ID again (no-op for DB)
                try await repo.saveDittoSubscription(sub)
                sub.name = "Updated"
                try await repo.saveDittoSubscription(sub) // existing, updates cache only

                // ASSERT — DB still has one row
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.count == 1)
            }
        }
    }

    // MARK: - Remove Tests

    @Suite("Remove")
    struct RemoveTests {

        @Test("Remove deletes subscription from SQLCipher", .tags(.repository, .database))
        func testRemoveDeletesFromSQLCipher() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "To Remove"
                sub.query = "SELECT * FROM toRemove"
                try await repo.saveDittoSubscription(sub)

                // ACT
                try await repo.removeDittoSubscription(sub)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test("Remove with nil syncSubscription does not crash", .tags(.repository, .database))
        func testRemoveWithNilSyncSubscriptionSafe() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-remove-nil")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Nil Sync"
                sub.query = "SELECT 1"
                sub.syncSubscription = nil // explicitly nil
                try await repo.saveDittoSubscription(sub)

                // ACT & ASSERT — should not crash
                try await repo.removeDittoSubscription(sub)
            }
        }
    }

    // MARK: - Clear Cache Tests

    @Suite("Clear Cache")
    struct ClearCacheTests {

        @Test("clearCache resets currentDatabaseId", .tags(.repository, .database))
        func testClearCacheResetsDatabaseId() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = SubscriptionsRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-clear")
                _ = try await repo.loadSubscriptions(for: dbId)

                // ACT
                await repo.clearCache()

                // ASSERT — save should now throw because currentDatabaseId is nil
                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "After Clear"
                sub.query = "SELECT 1"
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoSubscription(sub)
                }
            }
        }
    }

    // MARK: - Observer Tests

    @Suite("Observer Callback")
    struct ObserverCallbackTests {

        @Test("setOnSubscriptionsUpdate callback fires on save", .tags(.repository, .database))
        func testCallbackFiresOnSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-obs-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var callbackCount = 0
                await repo.setOnSubscriptionsUpdate { _ in
                    callbackCount += 1
                }

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Observed"
                sub.query = "SELECT 1"

                // ACT
                try await repo.saveDittoSubscription(sub)

                // ASSERT
                #expect(callbackCount == 1)
            }
        }

        @Test("setOnSubscriptionsUpdate callback fires on remove", .tags(.repository, .database))
        func testCallbackFiresOnRemove() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-obs-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "To Remove"
                sub.query = "SELECT 2"
                try await repo.saveDittoSubscription(sub)

                var callbackCount = 0
                await repo.setOnSubscriptionsUpdate { _ in
                    callbackCount += 1
                }

                // ACT
                try await repo.removeDittoSubscription(sub)

                // ASSERT
                #expect(callbackCount >= 1)
            }
        }
    }
}
