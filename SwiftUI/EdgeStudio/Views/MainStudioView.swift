import DittoSwift
import SwiftUI

struct MainStudioView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isMainStudioViewPresented: Bool
    @State var viewModel: MainStudioView.ViewModel
    @State private var showingImportView = false
    @State private var showingImportSubscriptionsView = false
    @State var showingSubscriptionQRDisplay = false
    @State var showingSubscriptionQRScanner = false
    @State var selectedSyncTab = 0 // Persists tab selection
    @State var queryCurrentPage = 1
    @State var queryPageSize = 10
    @State var observerCurrentPage = 1
    @State var observerPageSize = 25
    @State var queryIsExporting = false
    @State var queryCopiedDQLNotification: String?
    @State var expandedCollectionIds: Set<String> = []
    @State var expandedSubscriptionIds: Set<String> = []
    @State var expandedObserverIds: Set<String> = []

    // Observe detail pane state
    @State var observeDetailViewMode: ResultViewTab = .raw
    @State var observeDetailCurrentPage = 1
    @State var observeDetailPageSize = 10
    @State var observeDetailFilteredData: [String] = []

    /// Mirrors the UserDefaults "metricsEnabled" key; drives sidebar visibility.
    /// Updated by the macOS Settings window or iOS Settings app via @AppStorage KVO.
    @AppStorage("metricsEnabled") var metricsEnabled = true

    /// Inspector state
    @State var showInspector = false

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    /// Column visibility control - keeps sidebar always visible
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var preferredCompactColumn: NavigationSplitViewColumn = .detail

    /// used for editing observers and subscriptions
    private var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.actionSheetMode != .none },
            set: { newValue in
                if !newValue {
                    viewModel.actionSheetMode = .none
                }
            }
        )
    }

    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoConfigForDatabase
    ) {
        _isMainStudioViewPresented = isMainStudioViewPresented
        _viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            VStack(alignment: .leading) {
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    HStack {
                        Spacer()
                        Button {
                            preferredCompactColumn = .detail
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss sidebar")
                        .accessibilityIdentifier("SidebarDismissButton")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                #endif
                unifiedSidebarView()

                // Bottom Toolbar in Sidebar
                HStack {
                    Menu {
                        Button(
                            "Add Subscription",
                            systemImage: "arrow.trianglehead.2.clockwise"
                        ) {
                            viewModel.editorSubscription =
                                DittoSubscription.new()
                            viewModel.actionSheetMode = .subscription
                        }
                        Button("Add Observer", systemImage: "eye") {
                            viewModel.editorObservable = DittoObservable.new()
                            viewModel.actionSheetMode = .observer
                        }
                        Button("Add Index", systemImage: "plus.magnifyingglass") {
                            viewModel.actionSheetMode = .addIndex
                        }

                        Divider()

                        Button("Import Subscriptions → QR Code", systemImage: "qrcode.viewfinder") {
                            showingSubscriptionQRScanner = true
                        }

                        // Only show Import from Server when HTTP API is configured
                        if !viewModel.selectedApp.httpApiUrl.isEmpty &&
                            !viewModel.selectedApp.httpApiKey.isEmpty
                        {
                            Button("Import Subscriptions → Server", systemImage: "arrow.down.circle") {
                                showingImportSubscriptionsView = true
                            }
                        }

                        Divider()

                        Button("Import JSON Data", systemImage: "arrow.up") {
                            showingImportView = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(Color.dittoYellow)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
                #if os(iOS)
                    .padding(.bottom, 28)
                #else
                    .padding(.bottom, 12)
                #endif
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 16) // Add padding for status bar height
            .navigationSplitViewColumnWidth(
                min: isIPadRegular ? 250 : 200,
                ideal: isIPadRegular ? 300 : 250,
                max: isIPadRegular ? 380 : 300
            )
        } detail: {
            Group {
                switch viewModel.selectedSidebarMenuItem.name {
                case "Collections", "Query":
                    queryDetailView()
                case "Observers":
                    observeDetailView()
                case "App Metrics":
                    AppMetricsDetailView()
                case "Query Metrics":
                    QueryMetricsDetailView()
                case "Logging":
                    LoggingDetailView()
                default:
                    syncTabsDetailView()
                }
            }
            .id(viewModel.selectedSidebarMenuItem)
            .transition(.blurReplace)
            .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarMenuItem)
        }
        .navigationTitle(viewModel.selectedApp.name)
        #if os(macOS)
            .navigationSplitViewStyle(.prominentDetail)
            .background(WindowFrameRestorer())
        #endif
            .inspector(isPresented: $showInspector) {
                inspectorView()
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
                    .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
            }
            .sheet(isPresented: isSheetPresented) {
                if let subscription = viewModel.editorSubscription {
                    SubscriptionObserverEditor(
                        title: subscription.name.isEmpty
                            ? "New Query Argument"
                            : subscription.name,
                        name: subscription.name,
                        query: subscription.query,
                        onSave: viewModel.formSaveSubscription,
                        onCancel: viewModel.formCancel
                    ).environmentObject(appState)
                } else if let observer = viewModel.editorObservable {
                    SubscriptionObserverEditor(
                        title: observer.name.isEmpty
                            ? "New Observer"
                            : observer.name,
                        name: observer.name,
                        query: observer.query,
                        onSave: viewModel.formSaveObserver,
                        onCancel: viewModel.formCancel
                    ).environmentObject(appState)
                } else if viewModel.actionSheetMode == .addIndex {
                    AddIndexView(
                        collections: viewModel.collections,
                        onCancel: { viewModel.actionSheetMode = .none },
                        onCreated: {
                            viewModel.actionSheetMode = .none
                            Task { await viewModel.refreshCollectionCounts() }
                        }
                    ).environmentObject(appState)
                }
            }
            .sheet(isPresented: $showingImportView) {
                ImportDataView(isPresented: $showingImportView)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingImportSubscriptionsView) {
                ImportSubscriptionsView(
                    isPresented: $showingImportSubscriptionsView,
                    existingSubscriptions: viewModel.subscriptions,
                    selectedAppId: viewModel.selectedApp._id
                )
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingSubscriptionQRDisplay) {
                SubscriptionQRDisplayView(subscriptions: viewModel.subscriptions.map {
                    SubscriptionQRItem(name: $0.name, query: $0.query, args: nil)
                })
            }
            .sheet(isPresented: $showingSubscriptionQRScanner) {
                SubscriptionQRScannerView { items, onProgress in
                    await viewModel.importSubscriptionsFromQR(items, appState: appState, onProgress: onProgress)
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 360)
                #endif
            }
        #if os(macOS)
            .toolbar {
                syncCloseToolbarGroup() // Sync + Close grouped
                inspectorToggleButton() // Inspector visually separate
            }
        #endif
            // Sync sidebar items on first render (picks up the UserDefaults value after registerDefaults)
            .task {
                viewModel.sidebarMenuItems = MainStudioView.ViewModel.buildSidebarItems(
                    metricsEnabled: metricsEnabled
                )
                // Sync inspector items with current metrics setting on first render
                viewModel.queryInspectorMenuItems = MainStudioView.ViewModel.buildQueryInspectorItems(
                    metricsEnabled: metricsEnabled
                )
            }
            // React to metrics setting changes (macOS Settings window or iOS Settings app)
            .onChange(of: metricsEnabled) { _, enabled in
                viewModel.sidebarMenuItems = MainStudioView.ViewModel.buildSidebarItems(metricsEnabled: enabled)
                viewModel.queryInspectorMenuItems = MainStudioView.ViewModel.buildQueryInspectorItems(metricsEnabled: enabled)
                if !enabled {
                    // Auto-navigate away from metrics sidebar items
                    if viewModel.selectedSidebarMenuItem.name == "App Metrics" ||
                        viewModel.selectedSidebarMenuItem.name == "Query Metrics"
                    {
                        viewModel.selectedSidebarMenuItem = viewModel.sidebarMenuItems[0]
                    }
                    // Auto-navigate away from Metrics inspector tab
                    if viewModel.selectedQueryInspectorMenuItem.name == "Metrics" {
                        viewModel.selectedQueryInspectorMenuItem = viewModel.queryInspectorMenuItems[0]
                    }
                }
            }
            // Refresh metrics record whenever query results change
            .onChange(of: viewModel.jsonResults) { _, _ in
                Task { await viewModel.refreshLastQueryMetrics() }
            }
        #if os(iOS)
            .onChange(of: viewModel.selectedSidebarMenuItem) { _, _ in
                preferredCompactColumn = .detail
            }
        #endif
    }

    func appNameToolbarLabel() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(viewModel.selectedApp.name).font(.headline).bold()
        }
    }

    private var syncButtonContent: some View {
        Button {
            Task {
                do { try await viewModel.toggleSync() } catch { appState.setError(error) }
            }
        } label: {
            Image(systemName: "arrow.2.circlepath")
                .foregroundStyle(viewModel.isSyncEnabled ? Color.green : Color.red)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .help(viewModel.isSyncEnabled ? "Disable Sync" : "Enable Sync")
        .accessibilityIdentifier("SyncButton")
    }

    private var closeButtonContent: some View {
        Button {
            Task { await viewModel.closeSelectedApp(); isMainStudioViewPresented = false }
        } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .help("Close App")
        .accessibilityIdentifier("CloseButton")
    }

    func syncToolbarButton() -> some ToolbarContent {
        ToolbarItem(id: "syncButton", placement: .primaryAction) { syncButtonContent }
    }

    func closeToolbarButton() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { closeButtonContent }
    }

    func syncCloseToolbarGroup() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            syncButtonContent
            closeButtonContent
        }
    }

    func inspectorToggleButton() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundColor(showInspector ? .primary : .secondary)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Toggle Inspector")
            .accessibilityIdentifier("Toggle Inspector")
        }
    }

    #if os(iOS)
    func sidebarToggleButton() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                preferredCompactColumn = .sidebar
            } label: {
                Image(systemName: "sidebar.left")
            }
            .accessibilityIdentifier("SidebarToggleButton")
        }
    }
    #endif

    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
    }

    func expandedBinding(for collection: DittoCollection) -> Binding<Bool> {
        Binding(
            get: { expandedCollectionIds.contains(collection._id) },
            set: { isExpanded in
                if isExpanded { expandedCollectionIds.insert(collection._id) } else { expandedCollectionIds.remove(collection._id) }
            }
        )
    }

    func expandedSubscriptionBinding(for sub: DittoSubscription) -> Binding<Bool> {
        Binding(
            get: { expandedSubscriptionIds.contains(sub.id) },
            set: { if $0 { expandedSubscriptionIds.insert(sub.id) } else { expandedSubscriptionIds.remove(sub.id) } }
        )
    }

    func expandedObserverBinding(for obs: DittoObservable) -> Binding<Bool> {
        Binding(
            get: { expandedObserverIds.contains(obs.id) },
            set: { if $0 { expandedObserverIds.insert(obs.id) } else { expandedObserverIds.remove(obs.id) } }
        )
    }
}

// MARK: ViewModel

extension MainStudioView {
    @Observable
    @MainActor
    class ViewModel {
        var selectedApp: DittoConfigForDatabase

        // used for displaying action sheets
        var actionSheetMode = ActionSheetMode.none
        var editorSubscription: DittoSubscription?
        var editorObservable: DittoObservable?

        var selectedObservable: DittoObservable?
        var selectedEventId: String?

        // Sync status properties
        var syncStatusItems: [SyncStatusInfo] = []
        var isSyncEnabled = true // Track sync status here
        var connectionsByTransport: ConnectionsByTransport = .empty

        // Local peer info
        var localPeerDeviceName: String?
        var localPeerSDKLanguage: String?
        var localPeerSDKPlatform: String?
        var localPeerSDKVersion: String?

        // Note: PeerFilter enum removed in favor of presence-first architecture
        // syncStatusItems now always contains only connected peers (filtered at source)

        var isLoading = false
        var isQueryExecuting = false
        var isRefreshingCollections = false

        var eventMode = "items"
        var subscriptions: [DittoSubscription] = []
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [DittoCollection] = []
        var observerables: [DittoObservable] = []
        var observableEvents: [DittoObserveEvent] = []
        var selectedObservableEvents: [DittoObserveEvent] = []

        // query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        /// results view
        var jsonResults: [String]

        // Sidebar Toolbar
        var selectedSidebarMenuItem: MenuItem
        var sidebarMenuItems: [MenuItem] = []

        // Inspector Toolbar (used only when Collections tab is active)
        var selectedQueryInspectorMenuItem: MenuItem
        var queryInspectorMenuItems: [MenuItem] = []

        /// Metrics Inspector – last executed query record
        var lastQueryMetricsRecord: QueryExplainRecord?

        // Observer Inspector toolbar
        var selectedObserveInspectorMenuItem: MenuItem
        var observeInspectorMenuItems: [MenuItem] = []

        // Metrics Inspector toolbar
        var metricsInspectorMenuItems: [MenuItem] = []
        var selectedMetricsInspectorMenuItem: MenuItem

        // Metrics Inspector – Prometheus export form state (ephemeral UI, owned by ViewModel)
        var metricsPrometheusURLText = ""
        var metricsPrometheusIntervalText = "60"
        var metricsPrometheusStatusMessage = ""
        var metricsPrometheusIsConfigured = false

        /// JSON Inspector State
        var selectedJsonForInspector: String?

        init(_ dittoAppConfig: DittoConfigForDatabase) {
            selectedApp = dittoAppConfig
            let subscriptionItem = MenuItem(
                id: 1,
                name: "Subscriptions",
                systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"
            )

            selectedSidebarMenuItem = subscriptionItem
            sidebarMenuItems = Self.buildSidebarItems(
                metricsEnabled: UserDefaults.standard.bool(forKey: "metricsEnabled")
            )

            // query section
            selectedQuery = ""
            selectedExecuteMode = "Local"
            if dittoAppConfig.httpApiUrl == ""
                || dittoAppConfig.httpApiKey == ""
            {
                executeModes = ["Local"]
            } else {
                executeModes = ["Local", "HTTP"]
            }

            // query results section
            jsonResults = []

            // Inspector toolbar (used only when Collections tab is active)
            let builtQueryInspectorItems = Self.buildQueryInspectorItems(
                metricsEnabled: UserDefaults.standard.bool(forKey: "metricsEnabled")
            )
            queryInspectorMenuItems = builtQueryInspectorItems
            selectedQueryInspectorMenuItem = builtQueryInspectorItems[0] // History

            // Observer Inspector toolbar
            let jsonObserveItem = MenuItem(id: 9, name: "JSON", systemIcon: "text.document.fill")
            observeInspectorMenuItems = [
                jsonObserveItem,
                MenuItem(id: 10, name: "Help", systemIcon: "questionmark")
            ]
            selectedObserveInspectorMenuItem = jsonObserveItem

            // Metrics Inspector toolbar
            let metricsDocsItem = MenuItem(id: 11, name: "Docs", systemIcon: "book.closed")
            metricsInspectorMenuItems = [
                metricsDocsItem,
                MenuItem(id: 12, name: "Export", systemIcon: "arrow.up.to.line")
            ]
            selectedMetricsInspectorMenuItem = metricsDocsItem

            // Setup SystemRepository callback
            Task {
                await SystemRepository.shared.setOnSyncStatusUpdate { [weak self] statusItems, completion in
                    Task { @MainActor in
                        self?.mergeStatusItems(statusItems)

                        // CRITICAL: Signal completion AFTER UI update dispatches
                        Task {
                            // 50ms delay allows SwiftUI LazyVGrid rendering to complete
                            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                            completion()
                        }
                    }
                }
            }

            // Setup connections callback
            Task {
                await SystemRepository.shared.setOnConnectionsUpdate { [weak self] connections in
                    Task { @MainActor in
                        self?.connectionsByTransport = connections
                    }
                }
            }

            // Setup ObservableRepository callback
            Task {
                await ObservableRepository.shared.setOnObservablesUpdate { [weak self] observables in
                    Task { @MainActor in
                        self?.observerables = observables
                    }
                }
            }

            Task {
                isLoading = true

                await SubscriptionsRepository.shared.setOnSubscriptionsUpdate { newSubscriptions in
                    self.subscriptions = newSubscriptions
                }
                // Wrap individually so a failure here does not prevent history/favorites from loading
                do {
                    subscriptions = try await SubscriptionsRepository.shared.loadSubscriptions(for: selectedApp.databaseId)
                } catch {
                    Log.error("Failed to load subscriptions: \(error.localizedDescription)")
                }

                await CollectionsRepository.shared.setOnCollectionsUpdate { newCollections in
                    self.collections = newCollections
                }
                do {
                    collections = try await CollectionsRepository.shared.hydrateCollections()
                } catch {
                    Log.error("Failed to load collections: \(error.localizedDescription)")
                }

                // Register the history callback BEFORE calling loadHistory so currentDatabaseId
                // is guaranteed to be set before any user-triggered saveQueryHistory can fire.
                // Use direct assignment — the closure is already @MainActor, no inner Task needed.
                await HistoryRepository.shared.setOnHistoryUpdate { [weak self] history in
                    self?.history = history
                }
                do {
                    history = try await HistoryRepository.shared.loadHistory(for: selectedApp.databaseId)
                } catch {
                    Log.error("Failed to load history: \(error.localizedDescription)")
                }

                // Same pattern for favorites: register callback before loading.
                await FavoritesRepository.shared.setOnFavoritesUpdate { [weak self] favorites in
                    self?.favorites = favorites
                }
                do {
                    favorites = try await FavoritesRepository.shared.loadFavorites(for: selectedApp.databaseId)
                } catch {
                    Log.error("Failed to load favorites: \(error.localizedDescription)")
                }

                // Load observer metadata (without live observers - those must be re-registered)
                do {
                    observerables = try await ObservableRepository.shared.loadObservers(for: selectedApp.databaseId)
                } catch {
                    assertionFailure("Failed to load observers: \(error)")
                }

                if collections.isEmpty {
                    selectedQuery = subscriptions.first?.query ?? ""
                } else {
                    selectedQuery = "SELECT * FROM \(collections.first?.name ?? "")"
                }

                // Start observing connections via presence graph (drives bottom status bar)
                do {
                    try await SystemRepository.shared.registerConnectionsPresenceObserver()
                } catch {
                    // Not a programming error — can happen if the database was closed before
                    // this async Task completed (e.g. user switched databases quickly).
                    Log.error("Failed to register connections presence observer: \(error.localizedDescription)")
                }

                // Note: sync-status observer is registered by syncTabsDetailView().onAppear
                // (which fires before this Task reaches here). No eager registration needed —
                // it caused double-registration and backpressure pipeline deadlocks.

                // Fetch local peer info directly (bypassing QueryService so this startup
                // query is invisible to Query Metrics).
                do {
                    let query = "SELECT ditto_sdk_language, ditto_sdk_platform, ditto_sdk_version FROM __small_peer_info"
                    if let ditto = await DittoManager.shared.dittoSelectedApp {
                        let results = try await ditto.store.execute(query: query)
                        if let firstItem = results.items.first {
                            let json = firstItem.value.compactMapValues { $0 }
                            firstItem.dematerialize()
                            localPeerDeviceName = "Edge Studio"
                            localPeerSDKLanguage = json["ditto_sdk_language"] as? String
                            localPeerSDKPlatform = json["ditto_sdk_platform"] as? String
                            localPeerSDKVersion = json["ditto_sdk_version"] as? String
                        }
                    }
                } catch {
                    // Fail silently - not critical to app functionality
                    Log.error("Failed to fetch local peer info: \(error.localizedDescription)")
                }

                isLoading = false
            }
        }

        /// Builds the query inspector tab items, conditionally including the Metrics tab.
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

        /// Builds the sidebar menu items based on whether metrics collection is enabled.
        static func buildSidebarItems(metricsEnabled: Bool) -> [MenuItem] {
            [
                MenuItem(id: 1, name: "Subscriptions", systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"),
                MenuItem(id: 2, name: "Query", systemIcon: "macpro.gen2"),
                MenuItem(id: 3, name: "Observers", systemIcon: "eye"),
                MenuItem(id: 6, name: "Logging", systemIcon: "doc.plaintext.fill")
            ]
        }

        func refreshLastQueryMetrics() async {
            lastQueryMetricsRecord = await QueryMetricsRepository.shared.allRecords().first
        }

        /// Shows JSON in the inspector panel
        func showJsonInInspector(_ json: String) {
            selectedJsonForInspector = json
            if let jsonTab = queryInspectorMenuItems.first(where: { $0.name == "JSON" }) {
                selectedQueryInspectorMenuItem = jsonTab
            }
        }

        /// Shows JSON in the observe inspector panel
        func showJsonInObserveInspector(_ json: String) {
            selectedJsonForInspector = json
            if let jsonTab = observeInspectorMenuItems.first(where: { $0.name == "JSON" }) {
                selectedObserveInspectorMenuItem = jsonTab
            }
        }

        var selectedEventObject: DittoObserveEvent? {
            guard let selectedId = selectedEventId else { return nil }
            return observableEvents.first(where: { $0.id == selectedId })
        }

        func addQueryToHistory(appState: AppState) async {
            if !selectedQuery.isEmpty && !selectedQuery.isEmpty {
                let queryHistory = DittoQueryHistory(
                    id: UUID().uuidString,
                    query: selectedQuery,
                    createdDate: Date().ISO8601Format()
                )
                do {
                    try await HistoryRepository.shared.saveQueryHistory(queryHistory)
                } catch {
                    appState.setError(error)
                }
            }
        }

        @MainActor
        func refreshCollectionCounts() async {
            guard !isRefreshingCollections else { return } // Prevent concurrent refreshes

            isRefreshingCollections = true
            defer { isRefreshingCollections = false }

            do {
                collections = try await CollectionsRepository.shared.refreshCollections()
            } catch {
                // Error will be set in repository via appState
                Log.error("Failed to refresh collection counts: \(error.localizedDescription)")
            }
        }

        func closeSelectedApp() async {
            let closeStart = CFAbsoluteTimeGetCurrent()
            Log.info("[Close] Starting database close")

            // 1. Invalidate observer sessions FIRST so in-flight callbacks bail early
            await SystemRepository.shared.invalidateSession()
            let invalidateElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] Session invalidated (\(String(format: "%.3f", invalidateElapsed))s)")

            // 2. Clean up UI state immediately on main actor
            editorObservable = nil
            editorSubscription = nil
            selectedEventId = nil
            selectedObservable = nil

            subscriptions = []
            collections = []
            history = []
            favorites = []
            observerables = []
            observableEvents = []
            syncStatusItems = []
            connectionsByTransport = .empty
            isSyncEnabled = false

            // Clear peer info
            localPeerDeviceName = nil
            localPeerSDKLanguage = nil
            localPeerSDKPlatform = nil
            localPeerSDKVersion = nil

            let uiClearElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] UI state cleared (\(String(format: "%.3f", uiClearElapsed))s)")

            // 3. Perform heavy cleanup operations on background queue
            await performCleanupOperations()

            let totalElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] Total close time: \(String(format: "%.3f", totalElapsed))s")
        }

        /// Merges an incoming snapshot of peers into `syncStatusItems` while
        /// preserving each card's current grid position.
        ///
        /// - Existing peers have their data updated in-place (no reorder).
        /// - Peers absent from `newItems` are removed.
        /// - Peers new to `newItems` are appended to the end.
        @MainActor
        private func mergeStatusItems(_ newItems: [SyncStatusInfo]) {
            let newById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

            // Keep existing peers in order, updating their data; drop peers that left.
            var merged = syncStatusItems.compactMap { existing in
                newById[existing.id]
            }

            // Append peers that weren't in the previous list.
            let existingIds = Set(syncStatusItems.map(\.id))
            let brandNewPeers = newItems.filter { !existingIds.contains($0.id) }
            merged.append(contentsOf: brandNewPeers)

            syncStatusItems = merged
        }

        private func performCleanupOperations() async {
            let cleanupStart = CFAbsoluteTimeGetCurrent()

            // Capture observables on main actor before moving to background queues
            let observablesToCleanup = observerables

            // Use TaskGroup to run cleanup operations concurrently on background queues
            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: .utility) {
                    // Cancel observable store observers
                    for observable in observablesToCleanup {
                        observable.storeObserver?.cancel()
                    }
                    let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
                    Log.info("[Close:Observers] Store observers cancelled (\(String(format: "%.3f", elapsed))s)")
                }

                group.addTask(priority: .utility) {
                    // Clear repository caches
                    await HistoryRepository.shared.clearCache()
                    await FavoritesRepository.shared.clearCache()
                    await ObservableRepository.shared.clearCache()
                    await SubscriptionsRepository.shared.clearCache()

                    // Stop other repository observers
                    await SystemRepository.shared.stopObserver()
                    await CollectionsRepository.shared.stopObserver()

                    let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
                    Log.info("[Close:Repos] Caches cleared, observers stopped (\(String(format: "%.3f", elapsed))s)")
                }

                group.addTask(priority: .utility) {
                    // Close DittoManager selected app
                    await DittoManager.shared.closeDittoSelectedDatabase()
                    let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
                    Log.info("[Close:DittoManager] closeDittoSelectedDatabase complete (\(String(format: "%.3f", elapsed))s)")
                }
            }

            let totalElapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
            Log.info("[Close] All cleanup operations complete (\(String(format: "%.3f", totalElapsed))s)")
        }

        func toggleSync() async throws {
            if isSyncEnabled {
                // Disable sync
                await DittoManager.shared.selectedDatabaseStopSync()

                // Reset connection counts
                connectionsByTransport = .empty
                syncStatusItems = []

                isSyncEnabled = false
            } else {
                // Enable sync
                try await DittoManager.shared.selectedDatabaseStartSync()
                isSyncEnabled = true
            }
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            if let storeObserver = observable.storeObserver {
                storeObserver.cancel()
            }

            try await ObservableRepository.shared.removeDittoObservable(observable)

            // remove events for the observable
            observableEvents.removeAll(where: { $0.observeId == observable.id })

            if selectedObservable?.id == observable.id {
                selectedObservable = nil
            }
            if selectedEventObject?.observeId == observable.id {
                selectedEventId = nil
            }
        }

        func deleteSubscription(_ subscription: DittoSubscription) async throws {
            try await SubscriptionsRepository.shared.removeDittoSubscription(subscription)
        }

        func executeQuery(appState: AppState) async {
            isQueryExecuting = true
            do {
                if selectedExecuteMode == "Local" {
                    jsonResults = try await QueryService.shared
                        .executeSelectedAppQuery(query: selectedQuery)
                } else {
                    jsonResults = try await QueryService.shared
                        .executeSelectedAppQueryHttp(query: selectedQuery)
                }
                // Add query to history
                await addQueryToHistory(appState: appState)
            } catch {
                appState.setError(error)
            }
            isQueryExecuting = false
        }

        func formCancel() {
            editorSubscription = nil
            actionSheetMode = .none
        }

        func formSaveSubscription(
            name: String,
            query: String,
            appState: AppState
        ) {
            if var subscription = editorSubscription {
                subscription.name = name
                subscription.query = query
                Task {
                    do {
                        try await SubscriptionsRepository.shared.saveDittoSubscription(subscription)
                    } catch {
                        appState.setError(error)
                    }
                    editorSubscription = nil
                }
            }
            actionSheetMode = .none
        }

        func formSaveObserver(
            name: String,
            query: String,
            appState: AppState
        ) {
            if var observer = editorObservable {
                observer.name = name
                observer.query = query
                Task {
                    do {
                        try await ObservableRepository.shared.saveDittoObservable(observer)
                    } catch {
                        appState.setError(error)
                    }
                    editorObservable = nil
                }
            }
            actionSheetMode = .none
        }

        func importSubscriptionsFromQR(
            _ items: [SubscriptionQRItem],
            appState: AppState,
            onProgress: @escaping @MainActor (Int, Int) -> Void
        ) async {
            let total = items.count
            for (index, item) in items.enumerated() {
                var sub = DittoSubscription(id: UUID().uuidString)
                sub.name = item.name
                sub.query = item.query
                do {
                    try await SubscriptionsRepository.shared.saveDittoSubscription(sub)
                } catch {
                    appState.setError(error)
                }
                onProgress(index + 1, total)
            }
            // Explicitly refresh subscriptions on @MainActor so SwiftUI sees the update
            // before the sheet dismissal re-render fires. The cross-actor callback
            // (onSubscriptionsUpdate) races with the dismiss re-render; reading the
            // cache here on @MainActor eliminates that race.
            subscriptions = await SubscriptionsRepository.shared.getCachedSubscriptions()
        }

        func loadObservedEvents() async {
            if let selectedId = selectedObservable?.id {
                selectedObservableEvents = observableEvents.filter { $0.observeId == selectedId }
            } else {
                selectedObservableEvents = []
            }
        }

        func registerStoreObserver(_ observable: DittoObservable) async throws {
            guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
                throw InvalidStoreState(message: "Could not find observable")
            }
            guard let ditto = await DittoManager.shared.dittoSelectedApp else {
                throw InvalidStateError(message: "Could not get ditto reference from manager")
            }
            if observerables[index].storeObserver != nil {
                throw InvalidStoreState(message: "Observer already registered")
            }

            // if you activate an observable it's instantly selected
            selectedObservable = observable

            // used for calculating the diffs
            let dittoDiffer = DittoDiffer()

            // Deserialize arguments from JSON string
            let observer = try ditto.store.registerObserver(
                query: observable.query
            ) { [weak self] results in
                // required to show the end user when the event fired
                var event = DittoObserveEvent.new(observeId: observable.id)

                let diff = dittoDiffer.diff(results.items)

                event.eventTime = Date().ISO8601Format()

                // set diff information
                event.insertIndexes = Array(diff.insertions)
                event.deletedIndexes = Array(diff.deletions)
                event.updatedIndexes = Array(diff.updates)
                event.movedIndexes = Array(diff.moves)

                event.data = results.items.compactMap {
                    let data = $0.jsonData()
                    return String(data: data, encoding: .utf8)
                }

                self?.observableEvents.append(event)

                // if this is the selected observable, add it to the selectedEvents array too
                if let selectedObservableId = self?.selectedObservable?.id {
                    if event.observeId == selectedObservableId {
                        self?.selectedObservableEvents.append(event)
                    }
                }
            }
            observerables[index].storeObserver = observer
        }

        func removeStoreObserver(_ observable: DittoObservable) async throws {
            guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
                throw InvalidStoreState(message: "Could not find observable")
            }
            observerables[index].storeObserver?.cancel()
            observerables[index].storeObserver = nil
            selectedEventId = nil
            observableEvents.removeAll()
            observableEvents = []
        }

        func showObservableEditor(_ observable: DittoObservable) {
            editorObservable = observable
            actionSheetMode = .observer
        }

        func showSubscriptionEditor(_ subscription: DittoSubscription) {
            editorSubscription = subscription
            actionSheetMode = .subscription
        }
    }
}

// MARK: Helpers

enum ActionSheetMode: String {
    case none
    case subscription
    case observer
    case addIndex
}

struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var systemIcon: String // SF Symbol name (e.g., "clock", "bookmark")

    /// Computed property for rendering in pickers
    var image: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 48))
    }
}
