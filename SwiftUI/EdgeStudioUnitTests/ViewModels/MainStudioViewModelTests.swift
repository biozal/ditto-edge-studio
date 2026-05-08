@testable import Ditto_Edge_Studio
import DittoSwift
import Foundation
import Testing

/// Unit tests that prove `MainStudioView.ViewModel` is constructible with mock
/// repositories, validating the protocol-based DI wiring introduced in Phase
/// 10a. Before this refactor, the ViewModel's hard `.shared` singleton access
/// made every code path SDK-dependent and untestable in a unit-test
/// environment. The mocks below conform to the new repository protocols and
/// let us cover ViewModel logic without spinning up a live Ditto instance.
@Suite("MainStudioView.ViewModel — Protocol DI", .serialized)
struct MainStudioViewModelTests {
    // MARK: - Construction

    @Test(.tags(.fast))
    @MainActor
    func `ViewModel constructs with mock repositories`() {
        // ARRANGE — build a config and a fully-mocked dependency set
        let config = DittoConfigForDatabase.new()
        config.name = "Test DB"
        config.databaseId = "test-db-id"
        config.httpApiUrl = "https://example.invalid"
        config.httpApiKey = "key"
        let mocks = MockSet()

        // ACT — construct the ViewModel with mock dependencies
        let viewModel = MainStudioView.ViewModel(
            config,
            dittoManager: mocks.dittoManager,
            queryService: mocks.queryService,
            subscriptionsRepository: mocks.subscriptionsRepository,
            systemRepository: mocks.systemRepository,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository,
            observableRepository: mocks.observableRepository,
            collectionsRepository: mocks.collectionsRepository
        )

        // ASSERT — initial state reflects the configuration
        #expect(viewModel.selectedApp === config)
        #expect(viewModel.subscriptions.isEmpty)
        #expect(viewModel.collections.isEmpty)
        #expect(viewModel.history.isEmpty)
        #expect(viewModel.favorites.isEmpty)
        #expect(viewModel.observerables.isEmpty)
        #expect(viewModel.isLoading == false)
        // Both http* fields are populated, so HTTP execute mode is available.
        #expect(viewModel.executeModes == ["Local", "HTTP"])
    }

    // MARK: - Wiring

    @Test(.tags(.fast))
    @MainActor
    func `addQueryToHistory routes through the injected HistoryRepository`() async {
        // ARRANGE
        let config = DittoConfigForDatabase.new()
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = MainStudioView.ViewModel(
            config,
            dittoManager: mocks.dittoManager,
            queryService: mocks.queryService,
            subscriptionsRepository: mocks.subscriptionsRepository,
            systemRepository: mocks.systemRepository,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository,
            observableRepository: mocks.observableRepository,
            collectionsRepository: mocks.collectionsRepository
        )
        viewModel.selectedQuery = "SELECT * FROM cars"

        // ACT
        await viewModel.addQueryToHistory(appState: appState)

        // ASSERT — the mock recorded the save, proving the protocol path
        // (not the production singleton) carried the call.
        let savedQueries = await mocks.historyRepository.savedQueries
        #expect(savedQueries.count == 1)
        #expect(savedQueries.first?.query == "SELECT * FROM cars")
    }
}

// MARK: - Mocks

/// Bundles together one mock per repository / service protocol so tests don't
/// have to enumerate eight defaults each time. The mocks are inert by default
/// — they record calls but make no SDK calls and surface no errors.
@MainActor
private struct MockSet {
    let dittoManager = MockDittoManager()
    let queryService = MockQueryService()
    let subscriptionsRepository = MockSubscriptionsRepository()
    let systemRepository = MockSystemRepository()
    let historyRepository = MockHistoryRepository()
    let favoritesRepository = MockFavoritesRepository()
    let observableRepository = MockObservableRepository()
    let collectionsRepository = MockCollectionsRepository()
}

private actor MockDittoManager: DittoManagerProtocol {
    var dittoSelectedApp: Ditto? {
        nil
    }

    var dittoSelectedAppConfig: DittoConfigForDatabase? {
        nil
    }

    func setAppState(_: AppState) {}
    func hydrateDittoSelectedDatabase(_: DittoConfigForDatabase) async throws -> Bool {
        false
    }

    func closeDittoSelectedDatabase() async {}
    func selectedDatabaseStartSync() async throws {}
    func selectedDatabaseStopSync() async {}
}

private actor MockQueryService: QueryServiceProtocol {
    func executeSelectedAppQuery(query _: String) async throws -> [String] {
        []
    }

    func executeSelectedAppQueryHttp(query _: String) async throws -> [String] {
        []
    }
}

private actor MockSubscriptionsRepository: SubscriptionsRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnSubscriptionsUpdate(_: @escaping @MainActor ([DittoSubscription]) -> Void) {}
    func loadSubscriptions(for _: String) async throws -> [DittoSubscription] {
        []
    }

    func saveDittoSubscription(_: DittoSubscription) async throws {}
    func removeDittoSubscription(_: DittoSubscription) async throws {}
    func clearCache() {}
    func getCachedSubscriptions() -> [DittoSubscription] {
        []
    }
}

private actor MockSystemRepository: SystemRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnSyncStatusUpdate(
        _: @escaping @MainActor ([SyncStatusInfo], @escaping @Sendable () -> Void) -> Void
    ) {}
    func setOnConnectionsUpdate(_: @escaping @MainActor (ConnectionsByTransport) -> Void) {}
    func registerConnectionsPresenceObserver() async throws {}
    func invalidateSession() {}
    func stopObserver() async {}
}

private actor MockHistoryRepository: HistoryRepositoryProtocol {
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

private actor MockFavoritesRepository: FavoritesRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnFavoritesUpdate(_: @escaping @MainActor ([DittoQueryHistory]) -> Void) {}
    func loadFavorites(for _: String) async throws -> [DittoQueryHistory] {
        []
    }

    func saveFavorite(_: DittoQueryHistory) async throws {}
    func clearCache() {}
}

private actor MockObservableRepository: ObservableRepositoryProtocol {
    func setAppState(_: AppState) {}
    func setOnObservablesUpdate(_: @escaping @MainActor ([DittoObservable]) -> Void) {}
    func loadObservers(for _: String) async throws -> [DittoObservable] {
        []
    }

    func saveDittoObservable(_: DittoObservable) async throws {}
    func removeDittoObservable(_: DittoObservable) async throws {}
    func clearCache() {}
}

private actor MockCollectionsRepository: CollectionsRepositoryProtocol {
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
