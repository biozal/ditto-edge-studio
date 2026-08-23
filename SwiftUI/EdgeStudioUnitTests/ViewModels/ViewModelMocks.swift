import DittoSwift
import Foundation
@testable import Ditto_Edge_Studio

// MARK: - ViewModel Mocks (shared across sub-VM test suites)

// Lifted out of `MainStudioViewModelTests.swift` in Phase 10b so the four new
// sub-VM test suites (SyncStatus, Query, Attachment, SubscriptionObserver) can
// share one inert default each. Mocks record minimal call evidence
// (e.g. `MockHistoryRepository.savedQueries`) to give each sub-VM test a real
// proof-of-life assertion without spinning up a Ditto instance.

/// Bundles together one mock per repository / service protocol so tests don't
/// have to enumerate eight defaults each time.
@MainActor
struct MockSet {
    /// The runtime sync state the mock manager publishes to, mirroring what the real
    /// `DittoManager` funnels do. Tests read `SyncStatusViewModel.isSyncEnabled`, which is
    /// derived from this — so the assertion exercises the same property the toolbar reads
    /// rather than a parallel field.
    let syncRuntime = SyncRuntimeState()
    let dittoManager: MockDittoManager

    init() {
        dittoManager = MockDittoManager(syncRuntime: syncRuntime)
    }

    let queryService = MockQueryService()
    let databaseRepository = MockDatabaseRepository()
    let subscriptionsRepository = MockSubscriptionsRepository()
    let systemRepository = MockSystemRepository()
    let historyRepository = MockHistoryRepository()
    let favoritesRepository = MockFavoritesRepository()
    let observableRepository = MockObservableRepository()
    let collectionsRepository = MockCollectionsRepository()
}

actor MockDittoManager: DittoManagerProtocol {
    var dittoSelectedApp: Ditto? {
        nil
    }

    var dittoSelectedAppConfig: DittoConfigForDatabase? {
        nil
    }

    private(set) var startSyncCallCount = 0
    private(set) var stopSyncCallCount = 0

    /// Publishes sync transitions exactly as the real `DittoManager` funnels do, so
    /// `SyncStatusViewModel.isSyncEnabled` (a derived property) responds in tests.
    private let syncRuntime: SyncRuntimeState?

    /// When set, `selectedDatabaseStartSync` throws instead of starting — lets a test
    /// prove the state is published only on success.
    private var startError: Error?

    init(syncRuntime: SyncRuntimeState? = nil) {
        self.syncRuntime = syncRuntime
    }

    func setStartError(_ error: Error?) {
        startError = error
    }

    func setAppState(_: AppState) {}
    func hydrateDittoSelectedDatabase(_: DittoConfigForDatabase) async throws -> Bool {
        false
    }

    func closeDittoSelectedDatabase() async {}

    func selectedDatabaseStartSync() async throws {
        startSyncCallCount += 1
        if let startError {
            throw startError
        }
        // AFTER the "SDK call" succeeds, matching `DittoManager.startSyncNow`.
        if let syncRuntime {
            await MainActor.run { syncRuntime.setRunning(true) }
        }
    }

    func selectedDatabaseStopSync() async {
        stopSyncCallCount += 1
        if let syncRuntime {
            await MainActor.run { syncRuntime.setRunning(false) }
        }
    }
}

actor MockQueryService: QueryServiceProtocol {
    /// Last query passed through `executeSelectedAppQuery`. Lets tests assert
    /// that the VM forwarded the user's selectedQuery verbatim.
    private(set) var lastLocalQuery: String?
    private(set) var lastHttpQuery: String?

    /// Canned response. Tests can pre-load expected JSON results.
    var stubbedLocalResults: [String] = []
    var stubbedHttpResults: [String] = []

    /// Canned profile for the new profile-capturing variant. Tests
    /// that exercise the QueryViewModel's profile state can pre-load
    /// this; the default `nil` mirrors "metrics disabled" or
    /// "non-SELECT" runtime behaviour.
    var stubbedLocalProfile: QueryProfile?

    func executeSelectedAppQuery(query: String) async throws -> [String] {
        lastLocalQuery = query
        return stubbedLocalResults
    }

    func executeSelectedAppQueryHttp(query: String) async throws -> [String] {
        lastHttpQuery = query
        return stubbedHttpResults
    }

    func executeSelectedAppQueryWithProfile(query: String) async throws -> QueryExecutionResult {
        lastLocalQuery = query
        return QueryExecutionResult(items: stubbedLocalResults, profile: stubbedLocalProfile)
    }

    func setStubbedLocalResults(_ results: [String]) {
        stubbedLocalResults = results
    }

    func setStubbedLocalProfile(_ profile: QueryProfile?) {
        stubbedLocalProfile = profile
    }
}

actor MockDatabaseRepository: DatabaseRepositoryProtocol {
    /// Configs passed to `deleteDittoAppConfig`, in call order. Lets tests
    /// prove a deletion reached the repository — or (for the confirmation
    /// gate) that it did NOT.
    private(set) var deletedConfigs: [DittoConfigForDatabase] = []

    /// Canned configs returned by `loadDatabaseConfigs`.
    var stubbedConfigs: [DittoConfigForDatabase] = []

    func setAppState(_: AppState) {}
    func loadDatabaseConfigs() async throws -> [DittoConfigForDatabase] {
        stubbedConfigs
    }

    func addDittoAppConfig(_: DittoConfigForDatabase) async throws {}
    func updateDittoAppConfig(_: DittoConfigForDatabase) async throws {}

    func deleteDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws {
        deletedConfigs.append(appConfig)
    }

    func setOnDittoDatabaseConfigUpdate(
        _: @escaping @MainActor @Sendable ([DittoConfigForDatabase]) -> Void
    ) {}
}

actor MockSubscriptionsRepository: SubscriptionsRepositoryProtocol {
    private(set) var savedSubscriptions: [DittoSubscription] = []
    /// Database ids passed alongside each save — lets tests prove the VM
    /// forwarded the action-time database id (stale-session guard).
    private(set) var savedDatabaseIds: [String] = []

    func setAppState(_: AppState) {}
    func setOnSubscriptionsUpdate(_: @escaping @MainActor @Sendable ([DittoSubscription]) -> Void) {}
    func loadSubscriptions(for _: String) async throws -> [DittoSubscription] {
        []
    }

    func saveDittoSubscription(_ subscription: DittoSubscription, databaseId: String) async throws {
        savedSubscriptions.append(subscription)
        savedDatabaseIds.append(databaseId)
    }

    func removeDittoSubscription(_: DittoSubscription) async throws {}
    func clearCache() {}
    func getCachedSubscriptions() -> [DittoSubscription] {
        savedSubscriptions
    }
}

actor MockSystemRepository: SystemRepositoryProtocol {
    private(set) var presenceObserverRegistered = false

    func setAppState(_: AppState) {}
    func setOnSyncStatusUpdate(
        _: @escaping @MainActor @Sendable ([SyncStatusInfo], @escaping @Sendable () -> Void) -> Void
    ) {}
    func setOnConnectionsUpdate(_: @escaping @MainActor @Sendable (ConnectionsByTransport) -> Void) {}
    func registerConnectionsPresenceObserver() async throws {
        presenceObserverRegistered = true
    }

    func invalidateSession() {}
    func stopObserver() async {}
}

actor MockHistoryRepository: HistoryRepositoryProtocol {
    private(set) var savedQueries: [DittoQueryHistory] = []
    /// Database ids passed alongside each save — lets tests prove the VM
    /// forwarded the action-time database id (stale-session guard).
    private(set) var savedDatabaseIds: [String] = []

    func setAppState(_: AppState) {}
    func setOnHistoryUpdate(_: @escaping @MainActor @Sendable ([DittoQueryHistory]) -> Void) {}
    func loadHistory(for _: String) async throws -> [DittoQueryHistory] {
        []
    }

    func saveQueryHistory(_ history: DittoQueryHistory, databaseId: String) async throws {
        savedQueries.append(history)
        savedDatabaseIds.append(databaseId)
    }

    func clearCache() {}
}

actor MockFavoritesRepository: FavoritesRepositoryProtocol {
    private(set) var savedFavorites: [DittoQueryHistory] = []
    /// Database ids passed alongside each save — lets tests prove the VM
    /// forwarded the action-time database id (stale-session guard).
    private(set) var savedDatabaseIds: [String] = []

    func setAppState(_: AppState) {}
    func setOnFavoritesUpdate(_: @escaping @MainActor @Sendable ([DittoQueryHistory]) -> Void) {}
    func loadFavorites(for _: String) async throws -> [DittoQueryHistory] {
        []
    }

    func saveFavorite(_ favorite: DittoQueryHistory, databaseId: String) async throws {
        savedFavorites.append(favorite)
        savedDatabaseIds.append(databaseId)
    }

    func clearCache() {}
}

actor MockObservableRepository: ObservableRepositoryProtocol {
    private(set) var savedObservables: [DittoObservable] = []
    /// Database ids passed alongside each save — lets tests prove the VM
    /// forwarded the action-time database id (stale-session guard).
    private(set) var savedDatabaseIds: [String] = []

    func setAppState(_: AppState) {}
    func setOnObservablesUpdate(_: @escaping @MainActor @Sendable ([DittoObservable]) -> Void) {}
    func loadObservers(for _: String) async throws -> [DittoObservable] {
        []
    }

    func saveDittoObservable(_ observable: DittoObservable, databaseId: String) async throws {
        savedObservables.append(observable)
        savedDatabaseIds.append(databaseId)
    }

    func removeDittoObservable(_: DittoObservable) async throws {}
    func clearCache() {}
}

actor MockCollectionsRepository: CollectionsRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnCollectionsUpdate(_: @escaping @MainActor @Sendable ([DittoCollection]) -> Void) {}
    func hydrateCollections() async throws -> [DittoCollection] {
        []
    }

    func refreshCollections() async throws -> [DittoCollection] {
        []
    }

    func stopObserver() async {}
}
