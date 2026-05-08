import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests covering `QueryViewModel` — query execution, history routing,
/// and inspector tab selection. Phase 10b extraction.
@Suite("QueryViewModel — sub-VM", .serialized)
struct QueryViewModelTests {
    @Test(.tags(.fast))
    @MainActor
    func `ViewModel reflects HTTP availability based on app config`() {
        // ARRANGE — config with HTTP credentials populated
        let httpConfig = DittoConfigForDatabase.new()
        httpConfig.httpApiUrl = "https://example.invalid"
        httpConfig.httpApiKey = "key"
        let mocks = MockSet()

        // ACT
        let httpVM = QueryViewModel(
            dittoAppConfig: httpConfig,
            metricsEnabled: false,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )

        // ASSERT — HTTP mode appears alongside Local
        #expect(httpVM.executeModes == ["Local", "HTTP"])

        // ARRANGE — config without HTTP
        let localConfig = DittoConfigForDatabase.new()
        // httpApiUrl + httpApiKey default to empty strings

        // ACT
        let localVM = QueryViewModel(
            dittoAppConfig: localConfig,
            metricsEnabled: false,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )

        // ASSERT — Local-only
        #expect(localVM.executeModes == ["Local"])
    }

    @Test(.tags(.fast))
    @MainActor
    func `executeQuery in Local mode forwards selectedQuery and records history`() async {
        // ARRANGE
        let config = DittoConfigForDatabase.new()
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = QueryViewModel(
            dittoAppConfig: config,
            metricsEnabled: false,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )
        viewModel.selectedQuery = "SELECT * FROM cars"
        viewModel.selectedExecuteMode = "Local"
        await mocks.queryService.setStubbedLocalResults(["{\"_id\": \"abc\"}"])

        // ACT
        await viewModel.executeQuery(appState: appState)

        // ASSERT — query routed to Local (not HTTP), results captured,
        // and history recorded via the mock repository.
        #expect(await mocks.queryService.lastLocalQuery == "SELECT * FROM cars")
        #expect(await mocks.queryService.lastHttpQuery == nil)
        #expect(viewModel.jsonResults.count == 1)
        #expect(viewModel.isQueryExecuting == false)

        let history = await mocks.historyRepository.savedQueries
        #expect(history.count == 1)
        #expect(history.first?.query == "SELECT * FROM cars")
    }

    @Test(.tags(.fast))
    @MainActor
    func `selectInspectorTab finds the named tab when present`() {
        // ARRANGE
        let config = DittoConfigForDatabase.new()
        let mocks = MockSet()
        let viewModel = QueryViewModel(
            dittoAppConfig: config,
            metricsEnabled: true, // Metrics tab present
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )

        // ACT
        viewModel.selectInspectorTab(named: "Metrics")

        // ASSERT
        #expect(viewModel.selectedQueryInspectorMenuItem.name == "Metrics")

        // ACT — unknown tab is a no-op
        let prev = viewModel.selectedQueryInspectorMenuItem
        viewModel.selectInspectorTab(named: "DoesNotExist")
        #expect(viewModel.selectedQueryInspectorMenuItem == prev)
    }
}
