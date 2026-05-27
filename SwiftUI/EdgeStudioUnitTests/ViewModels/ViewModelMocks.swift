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
    let dittoManager = MockDittoManager()
    let queryService = MockQueryService()
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

    func setAppState(_: AppState) {}
    func hydrateDittoSelectedDatabase(_: DittoConfigForDatabase) async throws -> Bool {
        false
    }

    func closeDittoSelectedDatabase() async {}
    func selectedDatabaseStartSync() async throws {
        startSyncCallCount += 1
    }

    func selectedDatabaseStopSync() async {
        stopSyncCallCount += 1
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

actor MockSubscriptionsRepository: SubscriptionsRepositoryProtocol {
    private(set) var savedSubscriptions: [DittoSubscription] = []

    func setAppState(_: AppState) {}
    func setOnSubscriptionsUpdate(_: @escaping @MainActor ([DittoSubscription]) -> Void) {}
    func loadSubscriptions(for _: String) async throws -> [DittoSubscription] {
        []
    }

    func saveDittoSubscription(_ subscription: DittoSubscription) async throws {
        savedSubscriptions.append(subscription)
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
        _: @escaping @MainActor ([SyncStatusInfo], @escaping @Sendable () -> Void) -> Void
    ) {}
    func setOnConnectionsUpdate(_: @escaping @MainActor (ConnectionsByTransport) -> Void) {}
    func registerConnectionsPresenceObserver() async throws {
        presenceObserverRegistered = true
    }

    func invalidateSession() {}
    func stopObserver() async {}
}

actor MockHistoryRepository: HistoryRepositoryProtocol {
    private(set) var savedQueries: [DittoQueryHistory] = []

    func setAppState(_: AppState) {}
    func setOnHistoryUpdate(_: @escaping @MainActor ([DittoQueryHistory]) -> Void) {}
    func loadHistory(for _: String) async throws -> [DittoQueryHistory] {
        []
    }

    func saveQueryHistory(_ history: DittoQueryHistory) async throws {
        savedQueries.append(history)
    }

    func clearCache() {}
}

actor MockFavoritesRepository: FavoritesRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnFavoritesUpdate(_: @escaping @MainActor ([DittoQueryHistory]) -> Void) {}
    func loadFavorites(for _: String) async throws -> [DittoQueryHistory] {
        []
    }

    func saveFavorite(_: DittoQueryHistory) async throws {}
    func clearCache() {}
}

actor MockObservableRepository: ObservableRepositoryProtocol {
    private(set) var savedObservables: [DittoObservable] = []

    func setAppState(_: AppState) {}
    func setOnObservablesUpdate(_: @escaping @MainActor ([DittoObservable]) -> Void) {}
    func loadObservers(for _: String) async throws -> [DittoObservable] {
        []
    }

    func saveDittoObservable(_ observable: DittoObservable) async throws {
        savedObservables.append(observable)
    }

    func removeDittoObservable(_: DittoObservable) async throws {}
    func clearCache() {}
}

actor MockCollectionsRepository: CollectionsRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnCollectionsUpdate(_: @escaping @MainActor ([DittoCollection]) -> Void) {}
    func hydrateCollections() async throws -> [DittoCollection] {
        []
    }

    func refreshCollections() async throws -> [DittoCollection] {
        []
    }

    func stopObserver() async {}
}
