import Testing
@testable import Ditto_Edge_Studio

/// Regression tests for the cross-database write race (release 1.0b5):
/// `saveQueryHistory` / `saveDittoSubscription` / `saveFavorite` /
/// `saveDittoObservable` used to persist under whatever `currentDatabaseId`
/// was set at COMPLETION time, so a slow query on database A that finished
/// after the user switched to database B landed in B's history — and a stale
/// subscription save registered on B's live Ditto instance.
///
/// The save APIs now take the database id captured by the caller at
/// user-action time and refuse the write when it no longer matches the active
/// session. These tests pin that refusal contract against the real repository
/// singletons with an isolated SQLCipher store per test.
///
/// Uses .serialized because the repositories are process-wide singletons whose
/// `currentDatabaseId` is shared mutable state.
@Suite("Cross-database write race — stale session refusal", .serialized)
struct CrossDatabaseWriteRaceTests {
    // MARK: - Helpers

    /// Runs `body` against an isolated SQLCipher store, mirroring the
    /// integration target's `TestHelpers.withFreshDatabase` (the unit-test
    /// target has no shared TestHelpers file).
    @discardableResult
    private func withFreshDatabase<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let uniqueDirName = "ditto_test_\(UUID().uuidString)"
        let testService = SQLCipherService(testPath: uniqueDirName)
        try await testService.initialize()

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testDirURL = appSupportURL.appendingPathComponent(uniqueDirName)
        defer {
            try? FileManager.default.removeItem(at: testDirURL)
        }

        return try await SQLCipherContext.$current.withValue(testService) {
            try await body()
        }
    }

    /// Inserts a parent DatabaseConfigRow to satisfy the FOREIGN KEY
    /// constraint on the history/subscriptions `databaseId` columns.
    private func insertParentConfig(dbId: String) async throws {
        try await SQLCipherContext.current.insertDatabaseConfig(SQLCipherService.DatabaseConfigRow(
            _id: UUID().uuidString,
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

    // MARK: - HistoryRepository

    @Test(.tags(.repository, .database))
    func `History save with the action-time database id succeeds`() async throws {
        try await withFreshDatabase {
            // ARRANGE
            let repo = HistoryRepository.shared
            await repo.clearCache()
            let dbId = "hist-match-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbId)
            _ = try await repo.loadHistory(for: dbId)

            let entry = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM cars",
                createdDate: Date().ISO8601Format()
            )

            // ACT
            try await repo.saveQueryHistory(entry, databaseId: dbId)

            // ASSERT
            let rows = try await SQLCipherContext.current.getHistory(databaseId: dbId)
            #expect(rows.count == 1)
            #expect(rows[0].query == "SELECT * FROM cars")
        }
    }

    @Test(.tags(.repository, .database))
    func `History save with a stale database id is refused and persists nothing`() async throws {
        try await withFreshDatabase {
            // ARRANGE — session starts on database A, then switches to B
            // (exactly what loadHistory does when the user opens another
            // database while a slow query from A is still in flight).
            let repo = HistoryRepository.shared
            await repo.clearCache()
            let dbA = "hist-stale-a-\(UUID().uuidString)"
            let dbB = "hist-stale-b-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbA)
            try await insertParentConfig(dbId: dbB)
            _ = try await repo.loadHistory(for: dbA)
            _ = try await repo.loadHistory(for: dbB)

            let staleEntry = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM slow_query_on_a",
                createdDate: Date().ISO8601Format()
            )

            // ACT — the A query completes after the switch to B.
            await #expect(throws: InvalidStateError.self) {
                try await repo.saveQueryHistory(staleEntry, databaseId: dbA)
            }

            // ASSERT — nothing landed in either database's history, and B's
            // in-memory cache was not polluted by A's query.
            let rowsA = try await SQLCipherContext.current.getHistory(databaseId: dbA)
            let rowsB = try await SQLCipherContext.current.getHistory(databaseId: dbB)
            #expect(rowsA.isEmpty)
            #expect(rowsB.isEmpty)
            let cachedB = try await repo.loadHistory(for: dbB)
            #expect(cachedB.isEmpty)
        }
    }

    // MARK: - SubscriptionsRepository

    @Test(.tags(.repository, .database))
    func `Subscription save with the action-time database id succeeds`() async throws {
        try await withFreshDatabase {
            // ARRANGE
            let repo = SubscriptionsRepository.shared
            await repo.clearCache()
            let dbId = "sub-match-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbId)
            _ = try await repo.loadSubscriptions(for: dbId)

            var sub = DittoSubscription(id: UUID().uuidString)
            sub.name = "Active orders"
            sub.query = "SELECT * FROM orders"

            // ACT
            try await repo.saveDittoSubscription(sub, databaseId: dbId)

            // ASSERT
            let rows = try await SQLCipherContext.current.getSubscriptions(databaseId: dbId)
            #expect(rows.count == 1)
            #expect(rows[0].name == "Active orders")
        }
    }

    @Test(.tags(.repository, .database))
    func `Subscription save with a stale database id is refused before touching sync`() async throws {
        try await withFreshDatabase {
            // ARRANGE — session starts on database A, then switches to B.
            let repo = SubscriptionsRepository.shared
            await repo.clearCache()
            let dbA = "sub-stale-a-\(UUID().uuidString)"
            let dbB = "sub-stale-b-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbA)
            try await insertParentConfig(dbId: dbB)
            _ = try await repo.loadSubscriptions(for: dbA)
            _ = try await repo.loadSubscriptions(for: dbB)

            var staleSub = DittoSubscription(id: UUID().uuidString)
            staleSub.name = "Stale sub"
            staleSub.query = "SELECT * FROM a_collection"

            // ACT — the save initiated on A completes after the switch to B.
            // The guard must fire BEFORE any sync-engine registration.
            await #expect(throws: InvalidStateError.self) {
                try await repo.saveDittoSubscription(staleSub, databaseId: dbA)
            }

            // ASSERT — nothing persisted under either database id.
            let rowsA = try await SQLCipherContext.current.getSubscriptions(databaseId: dbA)
            let rowsB = try await SQLCipherContext.current.getSubscriptions(databaseId: dbB)
            #expect(rowsA.isEmpty)
            #expect(rowsB.isEmpty)
        }
    }

    // MARK: - FavoritesRepository

    @Test(.tags(.repository, .database))
    func `Favorite save with the action-time database id succeeds`() async throws {
        try await withFreshDatabase {
            // ARRANGE
            let repo = FavoritesRepository.shared
            await repo.clearCache()
            let dbId = "fav-match-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbId)
            _ = try await repo.loadFavorites(for: dbId)

            let entry = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM favorite_cars",
                createdDate: Date().ISO8601Format()
            )

            // ACT
            try await repo.saveFavorite(entry, databaseId: dbId)

            // ASSERT
            let rows = try await SQLCipherContext.current.getFavorites(databaseId: dbId)
            #expect(rows.count == 1)
            #expect(rows[0].query == "SELECT * FROM favorite_cars")
        }
    }

    @Test(.tags(.repository, .database))
    func `Favorite save with a stale database id is refused and persists nothing`() async throws {
        try await withFreshDatabase {
            // ARRANGE — session starts on database A, then switches to B.
            let repo = FavoritesRepository.shared
            await repo.clearCache()
            let dbA = "fav-stale-a-\(UUID().uuidString)"
            let dbB = "fav-stale-b-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbA)
            try await insertParentConfig(dbId: dbB)
            _ = try await repo.loadFavorites(for: dbA)
            _ = try await repo.loadFavorites(for: dbB)

            let staleEntry = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM stale_favorite_on_a",
                createdDate: Date().ISO8601Format()
            )

            // ACT — the save initiated on A completes after the switch to B.
            await #expect(throws: InvalidStateError.self) {
                try await repo.saveFavorite(staleEntry, databaseId: dbA)
            }

            // ASSERT — nothing landed in either database's favorites, and B's
            // in-memory cache was not polluted by A's save.
            let rowsA = try await SQLCipherContext.current.getFavorites(databaseId: dbA)
            let rowsB = try await SQLCipherContext.current.getFavorites(databaseId: dbB)
            #expect(rowsA.isEmpty)
            #expect(rowsB.isEmpty)
            let cachedB = try await repo.loadFavorites(for: dbB)
            #expect(cachedB.isEmpty)
        }
    }

    // MARK: - ObservableRepository

    @Test(.tags(.repository, .database))
    func `Observable save with the action-time database id succeeds`() async throws {
        try await withFreshDatabase {
            // ARRANGE
            let repo = ObservableRepository.shared
            await repo.clearCache()
            let dbId = "obs-match-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbId)
            _ = try await repo.loadObservers(for: dbId)

            var observable = DittoObservable(id: UUID().uuidString)
            observable.name = "Active orders observer"
            observable.query = "SELECT * FROM orders"
            observable.isActive = false

            // ACT
            try await repo.saveDittoObservable(observable, databaseId: dbId)

            // ASSERT
            let rows = try await SQLCipherContext.current.getObservables(databaseId: dbId)
            #expect(rows.count == 1)
            #expect(rows[0].name == "Active orders observer")
        }
    }

    @Test(.tags(.repository, .database))
    func `Observable save with a stale database id is refused and persists nothing`() async throws {
        try await withFreshDatabase {
            // ARRANGE — session starts on database A, then switches to B.
            let repo = ObservableRepository.shared
            await repo.clearCache()
            let dbA = "obs-stale-a-\(UUID().uuidString)"
            let dbB = "obs-stale-b-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbA)
            try await insertParentConfig(dbId: dbB)
            _ = try await repo.loadObservers(for: dbA)
            _ = try await repo.loadObservers(for: dbB)

            var staleObservable = DittoObservable(id: UUID().uuidString)
            staleObservable.name = "Stale observer"
            staleObservable.query = "SELECT * FROM a_collection"
            staleObservable.isActive = false

            // ACT — the save initiated on A completes after the switch to B.
            await #expect(throws: InvalidStateError.self) {
                try await repo.saveDittoObservable(staleObservable, databaseId: dbA)
            }

            // ASSERT — nothing persisted under either database id, and B's
            // in-memory cache was not polluted by A's save.
            let rowsA = try await SQLCipherContext.current.getObservables(databaseId: dbA)
            let rowsB = try await SQLCipherContext.current.getObservables(databaseId: dbB)
            #expect(rowsA.isEmpty)
            #expect(rowsB.isEmpty)
            let cachedB = try await repo.loadObservers(for: dbB)
            #expect(cachedB.isEmpty)
        }
    }

    // MARK: - Post-await re-guard (session switches DURING the save)

    // The tests above switch the session BEFORE the save starts, exercising
    // the pre-await guard. The saves also re-check `currentDatabaseId` AFTER
    // their internal awaits (actor reentrancy: a concurrent load*(for:) can
    // switch the session while the save is suspended). Both guards throw the
    // same stale-session error, so these tests distinguish them by
    // persistence: the post-await re-guard fires only AFTER the row was
    // persisted under the original (correctly keyed) database id. The
    // interleaving is retried until the switch lands inside the save's
    // suspension window — a wrong-guard or too-late attempt is detected and
    // retried, never silently accepted.

    @Test(.tags(.repository, .database))
    func `Subscription save suspended through a session switch is refused by the post-await re-guard`() async throws {
        try await withFreshDatabase {
            let repo = SubscriptionsRepository.shared
            await repo.clearCache()
            let recorder = await UpdateRecorder<[DittoSubscription]>()
            await repo.setOnSubscriptionsUpdate { snapshot in
                recorder.record(snapshot)
            }

            var exercisedPostGuard = false
            for _ in 0 ..< 25 {
                // ARRANGE — fresh databases per attempt; session starts on A.
                let dbA = "sub-mid-a-\(UUID().uuidString)"
                let dbB = "sub-mid-b-\(UUID().uuidString)"
                try await insertParentConfig(dbId: dbA)
                try await insertParentConfig(dbId: dbB)
                _ = try await repo.loadSubscriptions(for: dbA)

                var newSub = DittoSubscription(id: UUID().uuidString)
                newSub.name = "Mid-flight sub"
                newSub.query = "SELECT * FROM mid_flight"
                // Immutable snapshot: capturing a `var` in the Task's sending
                // closure while reading it below is a data-race error.
                let sub = newSub

                // ACT — start the save on A, then switch the session to B
                // while the save is suspended at its first await (the
                // sync-engine registration hop).
                let saveTask = Task {
                    try await repo.saveDittoSubscription(sub, databaseId: dbA)
                }
                await Task.yield()
                _ = try await repo.loadSubscriptions(for: dbB)

                do {
                    try await saveTask.value
                    continue // switch landed after the save finished — retry
                } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                    let rowsA = try await SQLCipherContext.current.getSubscriptions(databaseId: dbA)
                    guard rowsA.contains(where: { $0._id == sub.id }) else {
                        continue // pre-await guard fired (nothing persisted) — retry
                    }

                    // ASSERT — the post-await re-guard fired: the row stayed
                    // in A (correctly keyed) and B's store, cache and UI were
                    // not touched by A's save.
                    exercisedPostGuard = true
                    let rowsB = try await SQLCipherContext.current.getSubscriptions(databaseId: dbB)
                    #expect(rowsB.isEmpty)
                    let cached = await repo.getCachedSubscriptions()
                    #expect(!cached.contains(where: { $0.id == sub.id }))
                    let snapshots = await recorder.snapshots
                    #expect(!snapshots.contains(where: { $0.contains(where: { $0.id == sub.id }) }))
                    break
                }
            }
            #expect(exercisedPostGuard, "Post-await re-guard was never exercised within the attempt budget")
        }
    }

    @Test(.tags(.repository, .database))
    func `History save suspended through a session switch is refused by the post-await re-guard`() async throws {
        try await withFreshDatabase {
            let repo = HistoryRepository.shared
            await repo.clearCache()
            let recorder = await UpdateRecorder<[DittoQueryHistory]>()
            await repo.setOnHistoryUpdate { snapshot in
                recorder.record(snapshot)
            }

            var exercisedPostGuard = false
            for _ in 0 ..< 25 {
                // ARRANGE
                let dbA = "hist-mid-a-\(UUID().uuidString)"
                let dbB = "hist-mid-b-\(UUID().uuidString)"
                try await insertParentConfig(dbId: dbA)
                try await insertParentConfig(dbId: dbB)
                _ = try await repo.loadHistory(for: dbA)

                let entry = DittoQueryHistory(
                    id: UUID().uuidString,
                    query: "SELECT * FROM mid_flight_history",
                    createdDate: Date().ISO8601Format()
                )

                // ACT — start the save on A, then switch the session to B
                // while the save is suspended at its persist await.
                let saveTask = Task {
                    try await repo.saveQueryHistory(entry, databaseId: dbA)
                }
                await Task.yield()
                _ = try await repo.loadHistory(for: dbB)

                do {
                    try await saveTask.value
                    continue // switch landed after the save finished — retry
                } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                    let rowsA = try await SQLCipherContext.current.getHistory(databaseId: dbA)
                    guard rowsA.contains(where: { $0._id == entry.id }) else {
                        continue // pre-await guard fired (nothing persisted) — retry
                    }

                    // ASSERT — the post-await re-guard fired: the row stayed
                    // in A (correctly keyed) and B's store, cache and UI were
                    // not polluted by A's query.
                    exercisedPostGuard = true
                    let rowsB = try await SQLCipherContext.current.getHistory(databaseId: dbB)
                    #expect(rowsB.isEmpty)
                    let snapshots = await recorder.snapshots
                    #expect(!snapshots.contains(where: { $0.contains(where: { $0.id == entry.id }) }))
                    break
                }
            }
            #expect(exercisedPostGuard, "Post-await re-guard was never exercised within the attempt budget")
        }
    }

    @Test(.tags(.repository, .database))
    func `Observable save suspended through a session switch is refused by the post-await re-guard`() async throws {
        try await withFreshDatabase {
            let repo = ObservableRepository.shared
            await repo.clearCache()
            let recorder = await UpdateRecorder<[DittoObservable]>()
            await repo.setOnObservablesUpdate { snapshot in
                recorder.record(snapshot)
            }

            var exercisedPostGuard = false
            for _ in 0 ..< 25 {
                // ARRANGE
                let dbA = "obs-mid-a-\(UUID().uuidString)"
                let dbB = "obs-mid-b-\(UUID().uuidString)"
                try await insertParentConfig(dbId: dbA)
                try await insertParentConfig(dbId: dbB)
                _ = try await repo.loadObservers(for: dbA)

                var newObservable = DittoObservable(id: UUID().uuidString)
                newObservable.name = "Mid-flight observer"
                newObservable.query = "SELECT * FROM mid_flight"
                newObservable.isActive = false
                // Immutable snapshot: capturing a `var` in the Task's sending
                // closure while reading it below is a data-race error.
                let observable = newObservable

                // ACT — start the save on A, then switch the session to B
                // while the save is suspended at its persist await.
                let saveTask = Task {
                    try await repo.saveDittoObservable(observable, databaseId: dbA)
                }
                await Task.yield()
                _ = try await repo.loadObservers(for: dbB)

                do {
                    try await saveTask.value
                    continue // switch landed after the save finished — retry
                } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                    let rowsA = try await SQLCipherContext.current.getObservables(databaseId: dbA)
                    guard rowsA.contains(where: { $0._id == observable.id }) else {
                        continue // pre-await guard fired (nothing persisted) — retry
                    }

                    // ASSERT — the post-await re-guard fired: the row stayed
                    // in A (correctly keyed) and B's store, cache and UI were
                    // not polluted by A's save. (loadObservers notifies with
                    // B's own — empty — list, so the recorder assertion is
                    // specifically that no snapshot contains A's observable.)
                    exercisedPostGuard = true
                    let rowsB = try await SQLCipherContext.current.getObservables(databaseId: dbB)
                    #expect(rowsB.isEmpty)
                    let snapshots = await recorder.snapshots
                    #expect(!snapshots.contains(where: { $0.contains(where: { $0.id == observable.id }) }))
                    break
                }
            }
            #expect(exercisedPostGuard, "Post-await re-guard was never exercised within the attempt budget")
        }
    }

    // MARK: - Non-stamping QR paths (FavoritesRepository)

    @Test(.tags(.repository, .database))
    func `QR-path favorites read/import do not re-stamp the shared session`() async throws {
        try await withFreshDatabase {
            // ARRANGE — active session on A; B is a background database whose
            // favorites are shown/imported via the QR-code paths.
            let repo = FavoritesRepository.shared
            await repo.clearCache()
            let dbA = "fav-qr-a-\(UUID().uuidString)"
            let dbB = "fav-qr-b-\(UUID().uuidString)"
            try await insertParentConfig(dbId: dbA)
            try await insertParentConfig(dbId: dbB)
            _ = try await repo.loadFavorites(for: dbA)

            // ACT — the QR paths write and read B through the non-stamping
            // API (importFavorite / favorites(for:)).
            let imported = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM imported_via_qr",
                createdDate: Date().ISO8601Format()
            )
            try await repo.importFavorite(imported, for: dbB)
            let favsB = try await repo.favorites(for: dbB)

            // ASSERT — the import landed in B…
            #expect(favsB.count == 1)
            #expect(favsB[0].query == "SELECT * FROM imported_via_qr")
            // …the duplicate policy matches saveFavorite…
            await #expect(throws: InvalidStateError.self) {
                try await repo.importFavorite(imported, for: dbB)
            }
            // …and the shared session is still A: a save for A is NOT refused
            // (it would throw stale-session had the QR paths re-stamped).
            let entryA = DittoQueryHistory(
                id: UUID().uuidString,
                query: "SELECT * FROM active_window_save",
                createdDate: Date().ISO8601Format()
            )
            try await repo.saveFavorite(entryA, databaseId: dbA)
            let rowsA = try await SQLCipherContext.current.getFavorites(databaseId: dbA)
            #expect(rowsA.count == 1)
            #expect(rowsA[0].query == "SELECT * FROM active_window_save")
        }
    }
}

/// Records repository update callbacks (invoked on `@MainActor`) so tests
/// can assert a refused save never notified the UI.
@MainActor
private final class UpdateRecorder<T> {
    private(set) var snapshots: [T] = []

    func record(_ value: T) {
        snapshots.append(value)
    }
}
