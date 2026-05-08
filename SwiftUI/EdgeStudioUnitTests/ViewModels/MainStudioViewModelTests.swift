import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

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

        // ASSERT — initial state reflects the configuration. Sub-VMs own
        // the domain-specific state (subscriptions, observerables on
        // subObsVM; history, favorites on queryVM); the parent owns the
        // selected database, the cross-cutting `collections` array, and
        // `isLoading`.
        #expect(viewModel.selectedApp === config)
        #expect(viewModel.subObsVM.subscriptions.isEmpty)
        #expect(viewModel.collections.isEmpty)
        #expect(viewModel.queryVM.history.isEmpty)
        #expect(viewModel.queryVM.favorites.isEmpty)
        #expect(viewModel.subObsVM.observerables.isEmpty)
        #expect(viewModel.isLoading == false)
        // Both http* fields are populated, so HTTP execute mode is available.
        #expect(viewModel.queryVM.executeModes == ["Local", "HTTP"])
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
        viewModel.queryVM.selectedQuery = "SELECT * FROM cars"

        // ACT
        await viewModel.queryVM.addQueryToHistory(appState: appState)

        // ASSERT — the mock recorded the save, proving the protocol path
        // (not the production singleton) carried the call.
        let savedQueries = await mocks.historyRepository.savedQueries
        #expect(savedQueries.count == 1)
        #expect(savedQueries.first?.query == "SELECT * FROM cars")
    }
}
