import DittoSwift
import Foundation

/// Owns query-editor state (selected query, execute mode, results) and the
/// inspector data the query workflow produces (history, favorites, last query
/// metrics, JSON-in-inspector). Sub-VM of `MainStudioView.ViewModel`.
///
/// Phase 10b extraction. See `plans/2026-05-07-pre-v1-shipping-fixes.md`.
@Observable
@MainActor
final class QueryViewModel {
    // MARK: - Injected Dependencies

    @ObservationIgnored
    private let queryService: any QueryServiceProtocol
    @ObservationIgnored
    private let historyRepository: any HistoryRepositoryProtocol
    @ObservationIgnored
    private let favoritesRepository: any FavoritesRepositoryProtocol

    /// Database this VM was constructed for. Captured at init (i.e. at
    /// session start) so history saves that complete after the user switched
    /// databases carry the ORIGINAL database id — the repository refuses the
    /// write when it no longer matches the active session.
    @ObservationIgnored
    private let databaseId: String

    // MARK: - Editor State

    var selectedQuery: String
    var executeModes: [String]
    var selectedExecuteMode: String

    /// Live results array for the editor's results pane. Re-assigned wholesale
    /// after every execute so SwiftUI sees a single invalidation per run.
    var jsonResults: [String] = []

    /// Execution-plan profile captured for the most recent Local-mode
    /// query when Collect Metrics is enabled and the statement is a
    /// `SELECT`. Nil whenever:
    ///   - Metrics is disabled in Settings
    ///   - Last query was a non-SELECT (INSERT / UPDATE / DELETE / EVICT)
    ///   - Last execution was through the HTTP transport (PROFILE is
    ///     local-only for v1, see plans/dql-profile-feature.md)
    ///   - No query has been run yet on this database session
    /// The Profile tab in `QueryResultsView` reads this and renders one
    /// of four states; the empty-state messaging there relies on knowing
    /// *which* condition made the profile nil, so the tab also reads
    /// `metricsEnabled` and `selectedQuery` to differentiate.
    var latestProfile: QueryProfile?

    /// Advice from the most recent `ADVISE` run (SDK 5.1), or nil when the
    /// current editor query hasn't been advised (or the result carried none).
    /// Cleared whenever a query executes or a new ADVISE starts.
    var queryAdvice: QueryAdvice?
    var isAdviseRunning = false

    var isQueryExecuting = false

    // MARK: - Inspector Data

    /// Last 200 history entries. Mirrored from `HistoryRepository` via the
    /// callback installed in `installCallbacks`.
    var history: [DittoQueryHistory] = []

    /// User-saved favorites. Mirrored from `FavoritesRepository`.
    var favorites: [DittoQueryHistory] = []

    /// JSON document currently shown in the inspector (Query or Observe). The
    /// `MainStudioView.ViewModel.showJsonInInspector(_:)` orchestrator writes
    /// this; the inspector's JSON tab and `AttachmentViewModel` read it.
    var selectedJsonForInspector: String?

    /// Last query's explain record, populated by `refreshLastQueryMetrics()`
    /// after every execute. Drives the Metrics inspector tab.
    var lastQueryMetricsRecord: QueryExplainRecord?

    // MARK: - Inspector Menu

    var selectedQueryInspectorMenuItem: MenuItem
    var queryInspectorMenuItems: [MenuItem] = []

    // MARK: - Init

    init(
        dittoAppConfig: DittoConfigForDatabase,
        // Overridden by MainStudioView's `.task` (the canonical @AppStorage sync
        // point) before first render — kept deterministic + testable here.
        metricsEnabled: Bool = false,
        queryService: any QueryServiceProtocol = QueryService.shared,
        historyRepository: any HistoryRepositoryProtocol = HistoryRepository.shared,
        favoritesRepository: any FavoritesRepositoryProtocol = FavoritesRepository.shared
    ) {
        self.queryService = queryService
        self.historyRepository = historyRepository
        self.favoritesRepository = favoritesRepository
        databaseId = dittoAppConfig.databaseId

        // Initial editor state mirrors what the prior god-VM init produced.
        selectedQuery = ""
        selectedExecuteMode = "Local"
        if dittoAppConfig.httpApiUrl == "" || dittoAppConfig.httpApiKey == "" {
            executeModes = ["Local"]
        } else {
            executeModes = ["Local", "HTTP"]
        }

        // Inspector toolbar (used only when Collections tab is active).
        let builtItems = Self.buildQueryInspectorItems(metricsEnabled: metricsEnabled)
        queryInspectorMenuItems = builtItems
        selectedQueryInspectorMenuItem = builtItems[0] // History
    }

    // MARK: - Lifecycle hooks (called from parent's performLoad / closeSelectedApp)

    /// Wires the history and favorites repository update callbacks into this VM.
    /// Caller is responsible for ordering (callbacks installed before loads
    /// fire so user-triggered saves can resolve correctly).
    func installCallbacks() async {
        await historyRepository.setOnHistoryUpdate { [weak self] history in
            self?.history = history
        }
        await favoritesRepository.setOnFavoritesUpdate { [weak self] favorites in
            self?.favorites = favorites
        }
    }

    /// Loads history for the supplied database id. Returns the snapshot so the
    /// caller can sequence assignment with parallel sibling loads.
    func loadHistory(for databaseId: String) async -> [DittoQueryHistory] {
        do {
            return try await historyRepository.loadHistory(for: databaseId)
        } catch {
            Log.error("Failed to load history: \(error.localizedDescription)")
            return []
        }
    }

    /// Loads favorites for the supplied database id. Same contract as `loadHistory`.
    func loadFavorites(for databaseId: String) async -> [DittoQueryHistory] {
        do {
            return try await favoritesRepository.loadFavorites(for: databaseId)
        } catch {
            Log.error("Failed to load favorites: \(error.localizedDescription)")
            return []
        }
    }

    /// Clears the editor + inspector state. Called from the parent VM's
    /// `closeSelectedApp` so the next session starts blank.
    func reset() {
        selectedQuery = ""
        jsonResults = []
        latestProfile = nil
        isQueryExecuting = false
        history = []
        favorites = []
        selectedJsonForInspector = nil
        lastQueryMetricsRecord = nil
    }

    // MARK: - Inspector Menu

    /// Builds the query inspector tab items, conditionally including the
    /// Metrics tab when telemetry is enabled.
    static func buildQueryInspectorItems(metricsEnabled: Bool) -> [MenuItem] {
        var items = [
            MenuItem(id: 5, name: "History", systemIcon: "clock"),
            MenuItem(id: 6, name: "Favorites", systemIcon: "bookmark"),
            MenuItem(id: 7, name: "JSON", systemIcon: "text.document.fill")
        ]
        if metricsEnabled {
            items.append(MenuItem(id: 13, name: "Metrics", systemIcon: "text.magnifyingglass"))
        }
        items.append(MenuItem(id: 8, name: "Help", systemIcon: "questionmark"))
        return items
    }

    /// Selects an inspector tab by name. No-op if the named tab isn't in the
    /// menu (e.g. Metrics tab is filtered out when telemetry is disabled).
    func selectInspectorTab(named name: String) {
        if let tab = queryInspectorMenuItems.first(where: { $0.name == name }) {
            selectedQueryInspectorMenuItem = tab
        }
    }

    // MARK: - Inspector State

    /// Writes the JSON for the inspector and selects the JSON tab. Attachment
    /// detection is run by the parent VM's orchestrator so the AttachmentVM
    /// stays decoupled from this one.
    func showJsonInInspector(_ json: String) {
        selectedJsonForInspector = json
        selectInspectorTab(named: "JSON")
    }

    // MARK: - Metrics

    /// Re-reads the most recent metrics record. Driven from the View's
    /// `.onChange(of: jsonResults)` so the Metrics inspector always reflects
    /// the last query.
    func refreshLastQueryMetrics() async {
        lastQueryMetricsRecord = await QueryMetricsRepository.shared.allRecords().first
    }

    // MARK: - Execute

    /// Runs the current query through the selected execution mode and saves it
    /// to history on success.
    func executeQuery(appState: AppState) async {
        isQueryExecuting = true
        // A fresh execution supersedes any prior advice for this draft.
        queryAdvice = nil
        do {
            if selectedExecuteMode == "Local" {
                // Local path captures the PROFILE envelope when
                // Collect Metrics is enabled + statement is SELECT.
                // See QueryService.executeSelectedAppQueryWithProfile.
                let result = try await queryService.executeSelectedAppQueryWithProfile(
                    query: selectedQuery
                )
                jsonResults = result.items
                latestProfile = result.profile
            } else {
                // HTTP path: PROFILE is local-only for v1. Clear any
                // stale profile from a prior Local run so the Profile
                // tab doesn't display data that's not for the visible
                // results.
                jsonResults = try await queryService.executeSelectedAppQueryHttp(query: selectedQuery)
                latestProfile = nil
            }
            await addQueryToHistory(appState: appState)
        } catch {
            appState.setError(error)
        }
        isQueryExecuting = false
    }

    // MARK: - ADVISE (SDK 5.1)

    /// True when the editor text is a SELECT statement (ADVISE only advises SELECTs).
    var canRunAdvise: Bool {
        QueryService.isSelectStatement(selectedQuery) && !isQueryExecuting && !isAdviseRunning
    }

    /// Runs `ADVISE <current query>` through the selected execution mode and stores
    /// the parsed advice. Parity with the VS Code extension: suggestions land in a
    /// card above the results; each is applied (executed verbatim) only after the
    /// user confirms.
    func runAdvise(appState: AppState) async {
        let query = selectedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryService.isSelectStatement(query) else {
            appState.setError(NSError(
                domain: "EdgeStudio.QueryViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ADVISE works on SELECT statements only."]
            ))
            return
        }
        isAdviseRunning = true
        queryAdvice = nil
        do {
            let adviseQuery = "ADVISE \(query)"
            let rows: [String] = if selectedExecuteMode == "Local" {
                try await queryService.executeSelectedAppQuery(query: adviseQuery)
            } else {
                try await queryService.executeSelectedAppQueryHttp(query: adviseQuery)
            }
            queryAdvice = QueryAdviceExtractor.extract(from: rows)
            // History parity with the extension + Android: record the ADVISE run.
            // Stale-session refusals are logged-not-alerted (same as addQueryToHistory).
            do {
                try await historyRepository.saveQueryHistory(
                    DittoQueryHistory(
                        id: UUID().uuidString,
                        query: adviseQuery,
                        createdDate: Date.now.ISO8601Format()
                    ),
                    databaseId: databaseId
                )
            } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                Log.info("History save skipped (ADVISE): \(error.message)")
            }
        } catch {
            appState.setError(error)
        }
        isAdviseRunning = false
    }

    /// Executes a suggestion's CREATE INDEX statement verbatim. Called only from
    /// the confirmation path in the UI. Surfaces errors via appState and rethrows
    /// so the card can flip the row to its failed state.
    func applyAdviceSuggestion(_ suggestion: QueryIndexSuggestion, appState: AppState) async throws {
        do {
            _ = try await queryService.executeSelectedAppQuery(query: suggestion.statement)
        } catch {
            appState.setError(error)
            throw error
        }
    }

    /// Saves the current query to history. Public so the parent VM (or a test)
    /// can call it independent of `executeQuery` for verification.
    func addQueryToHistory(appState: AppState) async {
        guard !selectedQuery.isEmpty else { return }
        let queryHistory = DittoQueryHistory(
            id: UUID().uuidString,
            query: selectedQuery,
            createdDate: Date.now.ISO8601Format()
        )
        do {
            try await historyRepository.saveQueryHistory(queryHistory, databaseId: databaseId)
        } catch let error as InvalidStateError where error.isStaleSessionRefusal {
            // Expected race: the user switched databases while the query was
            // running and the repository correctly refused the stale write.
            // Log it — don't show an error alert in the NEW session.
            Log.info("History save skipped: \(error.message)")
        } catch {
            appState.setError(error)
        }
    }
}
