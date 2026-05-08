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

    // MARK: - Editor State

    var selectedQuery: String
    var executeModes: [String]
    var selectedExecuteMode: String

    /// Live results array for the editor's results pane. Re-assigned wholesale
    /// after every execute so SwiftUI sees a single invalidation per run.
    var jsonResults: [String] = []

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
        metricsEnabled: Bool = UserDefaults.standard.bool(forKey: "metricsEnabled"),
        queryService: any QueryServiceProtocol = QueryService.shared,
        historyRepository: any HistoryRepositoryProtocol = HistoryRepository.shared,
        favoritesRepository: any FavoritesRepositoryProtocol = FavoritesRepository.shared
    ) {
        self.queryService = queryService
        self.historyRepository = historyRepository
        self.favoritesRepository = favoritesRepository

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
        do {
            if selectedExecuteMode == "Local" {
                jsonResults = try await queryService.executeSelectedAppQuery(query: selectedQuery)
            } else {
                jsonResults = try await queryService.executeSelectedAppQueryHttp(query: selectedQuery)
            }
            await addQueryToHistory(appState: appState)
        } catch {
            appState.setError(error)
        }
        isQueryExecuting = false
    }

    /// Saves the current query to history. Public so the parent VM (or a test)
    /// can call it independent of `executeQuery` for verification.
    func addQueryToHistory(appState: AppState) async {
        guard !selectedQuery.isEmpty else { return }
        let queryHistory = DittoQueryHistory(
            id: UUID().uuidString,
            query: selectedQuery,
            createdDate: Date().ISO8601Format()
        )
        do {
            try await historyRepository.saveQueryHistory(queryHistory)
        } catch {
            appState.setError(error)
        }
    }
}
