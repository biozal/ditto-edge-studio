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

    // MARK: - Execution-plan profile state machine
    //
    // These tests exercise the latestProfile property on QueryViewModel
    // by stubbing MockQueryService.stubbedLocalProfile. They cover the
    // four transitions wired by Slice 1 / Slice 2 of the PROFILE feature:
    //   - Local mode + profile returned → latestProfile populated
    //   - Local mode + no profile (metrics off / non-SELECT runtime) →
    //     latestProfile stays nil
    //   - HTTP mode → latestProfile force-nilled regardless of mock stub
    //     (PROFILE is local-only for v1)
    //   - reset() called → latestProfile cleared along with jsonResults
    //
    // Real PROFILE execution against a live Ditto instance would belong
    // in EdgeStudioIntegrationTests, but that target's setup is built
    // around SQLCipher repositories (not Ditto.store). A future
    // integration test would need a real database + auth — out of scope
    // for v1. See plans/dql-profile-feature.md → Slice 5.

    @Test(.tags(.fast))
    @MainActor
    func `Local executeQuery populates latestProfile from the service`() async throws {
        // ARRANGE — stub the service to return a parsed profile and
        // exercise the Local branch.
        let config = DittoConfigForDatabase.new()
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = QueryViewModel(
            dittoAppConfig: config,
            metricsEnabled: true,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )
        viewModel.selectedQuery = "SELECT * FROM tasks"
        viewModel.selectedExecuteMode = "Local"

        let profile = try #require(
            QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
        )
        await mocks.queryService.setStubbedLocalProfile(profile)
        await mocks.queryService.setStubbedLocalResults(["{\"_id\": \"task-1\"}"])

        // ACT
        await viewModel.executeQuery(appState: appState)

        // ASSERT — profile lands on the VM with the expected envelope ID
        #expect(viewModel.latestProfile != nil)
        #expect(viewModel.latestProfile?.id == "e526fe68-04e9-4881-bf76-d0a582827e9b")
        #expect(viewModel.latestProfile?.plan.name == "sequence")
    }

    @Test(.tags(.fast))
    @MainActor
    func `Local executeQuery with nil profile leaves latestProfile nil`() async {
        // ARRANGE — service returns no profile (the "metrics off" or
        // "non-SELECT" runtime case, modelled here as a nil stub).
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
        viewModel.selectedQuery = "INSERT INTO tasks SET name = 'x'"
        viewModel.selectedExecuteMode = "Local"
        // stubbedLocalProfile defaults to nil — leave it.

        // ACT
        await viewModel.executeQuery(appState: appState)

        // ASSERT
        #expect(viewModel.latestProfile == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `HTTP executeQuery nils any previous profile`() async {
        // ARRANGE — config with HTTP credentials so the HTTP mode is
        // available, and seed a profile from a prior Local run.
        let config = DittoConfigForDatabase.new()
        config.httpApiUrl = "https://example.invalid"
        config.httpApiKey = "key"
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = QueryViewModel(
            dittoAppConfig: config,
            metricsEnabled: true,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )

        // Pre-load a profile as if Local had run first.
        viewModel.latestProfile = QueryProfileParser.parseItem(
            QueryProfileFixtures.canonicalEnvelope
        )
        #expect(viewModel.latestProfile != nil)

        // Now switch to HTTP and execute.
        viewModel.selectedQuery = "SELECT * FROM tasks"
        viewModel.selectedExecuteMode = "HTTP"
        await mocks.queryService.setStubbedLocalProfile(
            QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
        )

        // ACT
        await viewModel.executeQuery(appState: appState)

        // ASSERT — HTTP run wipes the profile even if the mock had one
        // queued. PROFILE is local-only for v1.
        #expect(viewModel.latestProfile == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `reset clears latestProfile along with jsonResults`() async {
        // ARRANGE — populate via a Local run, then reset.
        let config = DittoConfigForDatabase.new()
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = QueryViewModel(
            dittoAppConfig: config,
            metricsEnabled: true,
            queryService: mocks.queryService,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository
        )
        viewModel.selectedQuery = "SELECT * FROM tasks"
        viewModel.selectedExecuteMode = "Local"
        await mocks.queryService.setStubbedLocalProfile(
            QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
        )
        await mocks.queryService.setStubbedLocalResults(["{\"_id\": \"task-1\"}"])
        await viewModel.executeQuery(appState: appState)
        #expect(viewModel.latestProfile != nil)
        #expect(viewModel.jsonResults.count == 1)

        // ACT
        viewModel.reset()

        // ASSERT
        #expect(viewModel.latestProfile == nil)
        #expect(viewModel.jsonResults.isEmpty)
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
