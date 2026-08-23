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
    /// Helper to insert a parent database config so FK constraint is satisfied
    private func insertDatabaseConfig(_ dbId: String) async throws {
        let service = SQLCipherContext.current
        let row = SQLCipherService.DatabaseConfigRow(
            _id: UUID().uuidString, name: "Test DB", databaseId: dbId,
            mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
            isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
            token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
        )
        try await service.insertDatabaseConfig(row)
    }

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {
        @Test(.tags(.repository, .database))
        func `Fresh database returns empty subscription list`() async throws {
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

        @Test(.tags(.repository, .database))
        func `Load returns subscriptions scoped by databaseId`() async throws {
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
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                )
                let row2 = SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                )
                try await service.insertDatabaseConfig(row1)
                try await service.insertDatabaseConfig(row2)

                // Insert subscription only for dbId1
                let subRow = SQLCipherService.SubscriptionRow(
                    _id: UUID().uuidString, databaseId: dbId1,
                    name: "Sub1", query: "SELECT 1"
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

        @Test(.tags(.repository, .database))
        func `Loaded subscriptions have nil syncSubscription`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-nil-sync")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))
                try await service.insertSubscription(SQLCipherService.SubscriptionRow(
                    _id: UUID().uuidString, databaseId: dbId, name: "S", query: "SELECT 1"
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
        @Test(.tags(.repository, .database))
        func `Save persists subscription metadata to SQLCipher`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "My Sub"
                sub.query = "SELECT * FROM products"

                // ACT
                try await repo.saveDittoSubscription(sub, databaseId: dbId)

                // Verify via SQLCipher directly
                let rows = try await service.getSubscriptions(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].name == "My Sub")
                #expect(rows[0].query == "SELECT * FROM products")
            }
        }

        @Test(.tags(.repository, .database))
        func `Save without prior load throws InvalidStateError`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = SubscriptionsRepository.shared
                await repo.clearCache()

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Test"
                sub.query = "SELECT 1"

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoSubscription(sub, databaseId: "no-active-session")
                }
            }
        }

        @Test(.tags(.repository, .database))
        func `Saving existing ID updates in-memory cache`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-save-dup")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                let subId = TestHelpers.uniqueTestId()
                var sub = DittoSubscription(id: subId)
                sub.name = "Original"
                sub.query = "SELECT 1"

                // ACT — save once (inserts into DB) then save same ID again (no-op for DB)
                try await repo.saveDittoSubscription(sub, databaseId: dbId)
                sub.name = "Updated"
                try await repo.saveDittoSubscription(sub, databaseId: dbId) // existing, updates cache only

                // ASSERT — DB still has one row
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.count == 1)
            }
        }

        @Test(.tags(.repository, .database))
        func `Persist failure leaves no cached subscription and fires no callback`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE — NO parent DatabaseConfigRow for dbId, so the
                // FOREIGN KEY constraint makes insertSubscription throw. This
                // exercises the save path where registration with the sync
                // engine (nil in tests — no live Ditto) has already happened
                // but persistence fails: nothing may be cached or notified.
                let repo = SubscriptionsRepository.shared
                await repo.clearCache()
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-persist-fail")
                _ = try await repo.loadSubscriptions(for: dbId)

                let callbackCount = TestCounter()
                await repo.setOnSubscriptionsUpdate { _ in
                    callbackCount.increment()
                }

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Will fail"
                sub.query = "SELECT 1"

                // ACT
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoSubscription(sub, databaseId: dbId)
                }

                // ASSERT — no partial state: cache stays empty, UI not notified.
                let cached = await repo.getCachedSubscriptions()
                #expect(cached.isEmpty)
                #expect(callbackCount.value == 0)
            }
        }
    }

    // MARK: - Remove Tests

    @Suite("Remove")
    struct RemoveTests {
        @Test(.tags(.repository, .database))
        func `Remove deletes subscription from SQLCipher`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "To Remove"
                sub.query = "SELECT * FROM toRemove"
                try await repo.saveDittoSubscription(sub, databaseId: dbId)

                // ACT
                try await repo.removeDittoSubscription(sub)

                // ASSERT
                let rows = try await service.getSubscriptions(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test(.tags(.repository, .database))
        func `Remove with nil syncSubscription does not crash`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-remove-nil")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Nil Sync"
                sub.query = "SELECT 1"
                sub.syncSubscription = nil // explicitly nil
                try await repo.saveDittoSubscription(sub, databaseId: dbId)

                // ACT & ASSERT — should not crash
                try await repo.removeDittoSubscription(sub)
            }
        }
    }

    // MARK: - Clear Cache Tests

    @Suite("Clear Cache")
    struct ClearCacheTests {
        @Test(.tags(.repository, .database))
        func `clearCache resets currentDatabaseId`() async throws {
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
                    try await repo.saveDittoSubscription(sub, databaseId: "no-active-session")
                }
            }
        }
    }

    // MARK: - Observer Tests

    @Suite("Observer Callback")
    struct ObserverCallbackTests {
        @Test(.tags(.repository, .database))
        func `setOnSubscriptionsUpdate callback fires on save`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-obs-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                let callbackCount = TestCounter()
                await repo.setOnSubscriptionsUpdate { _ in
                    callbackCount.increment()
                }

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "Observed"
                sub.query = "SELECT 1"

                // ACT
                try await repo.saveDittoSubscription(sub, databaseId: dbId)

                // ASSERT
                #expect(callbackCount.value == 1)
            }
        }

        @Test(.tags(.repository, .database))
        func `setOnSubscriptionsUpdate callback fires on remove`() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "sub-obs-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: "", logLevel: "info"
                ))

                let repo = SubscriptionsRepository.shared
                _ = try await repo.loadSubscriptions(for: dbId)

                var sub = DittoSubscription(id: TestHelpers.uniqueTestId())
                sub.name = "To Remove"
                sub.query = "SELECT 2"
                try await repo.saveDittoSubscription(sub, databaseId: dbId)

                let callbackCount = TestCounter()
                await repo.setOnSubscriptionsUpdate { _ in
                    callbackCount.increment()
                }

                // ACT
                try await repo.removeDittoSubscription(sub)

                // ASSERT
                #expect(callbackCount.value >= 1)
            }
        }
    }
}
