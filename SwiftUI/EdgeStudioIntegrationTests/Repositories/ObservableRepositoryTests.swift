import Testing
@testable import Edge_Debug_Helper

/// Comprehensive test suite for ObservableRepository
///
/// Tests cover the SQLCipher persistence layer. Live DittoStoreObserver instances
/// are not persisted — `storeObserver` is nil in unit tests, and `cancel()` on nil
/// is safe because the property is optional.
///
/// - Load: fresh DB empty, load scoped by databaseId
/// - Save: save persists observable metadata (insert and update paths)
/// - Remove: remove deletes item, nil observer cancel is safe
/// - Cache: clearCache resets state
/// - Observer: callback fires on save and remove
///
/// Uses .serialized because all tests share SQLCipherService.shared.
/// Target: 50% code coverage.
@Suite("ObservableRepository Tests", .serialized)
struct ObservableRepositoryTests {

    // Helper to insert a parent database config
    private func insertDatabaseConfig(_ dbId: String) async throws {
        let service = SQLCipherContext.current
        try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
            _id: UUID().uuidString, name: "DB", databaseId: dbId,
            mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
            isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
            token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
        ))
    }

    // MARK: - Load Tests

    @Suite("Load")
    struct LoadTests {

        @Test("Fresh database returns empty observable list", .tags(.repository, .database))
        func testFreshDatabaseEmpty() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = ObservableRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-repo-empty")

                // ACT
                let observables = try await repo.loadObservers(for: dbId)

                // ASSERT
                #expect(observables.isEmpty)
            }
        }

        @Test("Load returns observables scoped by databaseId", .tags(.repository, .database))
        func testLoadScopedByDatabase() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId1 = TestHelpers.uniqueTestId(prefix: "obs-scope-1")
                let dbId2 = TestHelpers.uniqueTestId(prefix: "obs-scope-2")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB1", databaseId: dbId1,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB2", databaseId: dbId2,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: UUID().uuidString, databaseId: dbId1, name: "Obs1",
                    query: "SELECT 1", args: nil, isActive: true, lastUpdated: nil
                ))

                let repo = ObservableRepository.shared

                // ACT
                let obs1 = try await repo.loadObservers(for: dbId1)
                let obs2 = try await repo.loadObservers(for: dbId2)

                // ASSERT
                #expect(obs1.count == 1)
                #expect(obs1[0].name == "Obs1")
                #expect(obs2.isEmpty)
            }
        }

        @Test("Loaded observables have nil storeObserver", .tags(.repository, .database))
        func testLoadedObservablesHaveNilStoreObserver() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-nil-store")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))
                try await service.insertObservable(SQLCipherService.ObservableRow(
                    _id: UUID().uuidString, databaseId: dbId, name: "Obs",
                    query: "SELECT 1", args: nil, isActive: true, lastUpdated: nil
                ))

                // ACT
                let repo = ObservableRepository.shared
                let observables = try await repo.loadObservers(for: dbId)

                // ASSERT — storeObserver is not persisted and remains nil
                #expect(observables[0].storeObserver == nil)
            }
        }
    }

    // MARK: - Save Tests

    @Suite("Save")
    struct SaveTests {

        @Test("Save inserts new observable into SQLCipher", .tags(.repository, .database))
        func testSaveInsertsObservable() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "Cars Observer"
                obs.query = "SELECT * FROM cars"
                obs.isActive = true

                // ACT
                try await repo.saveDittoObservable(obs)

                // Verify via SQLCipher directly
                let rows = try await service.getObservables(databaseId: dbId)

                // ASSERT
                #expect(rows.count == 1)
                #expect(rows[0].name == "Cars Observer")
                #expect(rows[0].query == "SELECT * FROM cars")
                #expect(rows[0].isActive == true)
            }
        }

        @Test("Save updates existing observable in SQLCipher", .tags(.repository, .database))
        func testSaveUpdatesExistingObservable() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-update")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                let obsId = TestHelpers.uniqueTestId()
                var obs = DittoObservable(id: obsId)
                obs.name = "Original"
                obs.query = "SELECT 1"
                obs.isActive = false
                try await repo.saveDittoObservable(obs)

                // Mutate and save again — should update, not insert duplicate
                obs.name = "Updated"
                obs.isActive = true

                // ACT
                try await repo.saveDittoObservable(obs)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.count == 1) // no duplicate
                #expect(rows[0].name == "Updated")
                #expect(rows[0].isActive == true)
            }
        }

        @Test("Save without prior load throws InvalidStateError", .tags(.repository, .database))
        func testSaveWithoutLoadThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = ObservableRepository.shared
                await repo.clearCache()

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "Test"
                obs.query = "SELECT 1"

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoObservable(obs)
                }
            }
        }
    }

    // MARK: - Remove Tests

    @Suite("Remove")
    struct RemoveTests {

        @Test("Remove deletes observable from SQLCipher", .tags(.repository, .database))
        func testRemoveDeletesFromSQLCipher() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "To Remove"
                obs.query = "SELECT * FROM toRemove"
                try await repo.saveDittoObservable(obs)

                // ACT
                try await repo.removeDittoObservable(obs)

                // ASSERT
                let rows = try await service.getObservables(databaseId: dbId)
                #expect(rows.isEmpty)
            }
        }

        @Test("Remove with nil storeObserver does not crash", .tags(.repository, .database))
        func testRemoveWithNilStoreObserverSafe() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-remove-nil")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "Nil Observer"
                obs.query = "SELECT 1"
                obs.storeObserver = nil // explicitly nil
                try await repo.saveDittoObservable(obs)

                // ACT & ASSERT — should not crash
                try await repo.removeDittoObservable(obs)
            }
        }

        @Test("Remove without prior load throws InvalidStateError", .tags(.repository, .database))
        func testRemoveWithoutLoadThrows() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = ObservableRepository.shared
                await repo.clearCache()

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "T"
                obs.query = "SELECT 1"

                // ACT & ASSERT
                await #expect(throws: (any Error).self) {
                    try await repo.removeDittoObservable(obs)
                }
            }
        }
    }

    // MARK: - Cache Tests

    @Suite("Cache")
    struct CacheTests {

        @Test("clearCache resets currentDatabaseId", .tags(.repository, .database))
        func testClearCacheResetsDatabaseId() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let repo = ObservableRepository.shared
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-clear")
                _ = try await repo.loadObservers(for: dbId)

                // ACT
                await repo.clearCache()

                // ASSERT — save should now throw
                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "After Clear"
                obs.query = "SELECT 1"
                await #expect(throws: (any Error).self) {
                    try await repo.saveDittoObservable(obs)
                }
            }
        }
    }

    // MARK: - Observer Tests

    @Suite("Observer Callback")
    struct ObserverCallbackTests {

        @Test("setOnObservablesUpdate callback fires on save", .tags(.repository, .database))
        func testCallbackFiresOnSave() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-obs-save")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                var callbackCount = 0
                await repo.setOnObservablesUpdate { _ in
                    callbackCount += 1
                }

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "Observed"
                obs.query = "SELECT 1"

                // ACT
                try await repo.saveDittoObservable(obs)

                // ASSERT
                #expect(callbackCount == 1)
            }
        }

        @Test("setOnObservablesUpdate callback fires on remove", .tags(.repository, .database))
        func testCallbackFiresOnRemove() async throws {
            try await TestHelpers.withFreshDatabase {
                // ARRANGE
                let service = SQLCipherContext.current
                let dbId = TestHelpers.uniqueTestId(prefix: "obs-obs-remove")
                try await service.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
                    _id: UUID().uuidString, name: "DB", databaseId: dbId,
                    mode: "server", allowUntrustedCerts: false, isBluetoothLeEnabled: true,
                    isLanEnabled: true, isAwdlEnabled: true, isCloudSyncEnabled: true,
                    token: "", authUrl: "", websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
                ))

                let repo = ObservableRepository.shared
                _ = try await repo.loadObservers(for: dbId)

                var obs = DittoObservable(id: TestHelpers.uniqueTestId())
                obs.name = "To Remove"
                obs.query = "SELECT 2"
                try await repo.saveDittoObservable(obs)

                var callbackCount = 0
                await repo.setOnObservablesUpdate { _ in
                    callbackCount += 1
                }

                // ACT
                try await repo.removeDittoObservable(obs)

                // ASSERT
                #expect(callbackCount >= 1)
            }
        }
    }
}
