import DittoSwift
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MainStudioView: View {
    @Environment(AppState.self) var appState
    @Binding var isMainStudioViewPresented: Bool
    @Binding var isClosingDatabase: Bool
    @State var viewModel: MainStudioView.ViewModel
    /// Currently presented modal sheet (or `nil` when none). Drives the single
    /// `.sheet(item:)` modifier on the body — replaces the previous tower of
    /// `.sheet(isPresented:)` modifiers driven by independent `Bool` flags.
    @State var activeSheet: ActiveSheet?
    /// Persists the sync detail's sub-tab (Peers List / Presence Viewer) across app launches.
    @AppStorage("selectedSyncTab") var selectedSyncTab = 0
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

    /// Sidebar destinations to display, filtering out metrics destinations when
    /// telemetry is disabled (matches the previous `buildSidebarItems` behavior).
    var availableDestinations: [SidebarDestination] {
        SidebarDestination.allCases.filter { destination in
            !destination.isMetricsDestination || metricsEnabled
        }
    }

    /// Renders the body of whichever sheet is currently presented. Routed by the
    /// single `.sheet(item: $activeSheet)` modifier on the body so only one sheet
    /// can be active at a time.
    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .editSubscription:
            if let subscription = viewModel.editorSubscription {
                SubscriptionObserverEditor(
                    title: subscription.name.isEmpty
                        ? "New Query Argument"
                        : subscription.name,
                    name: subscription.name,
                    query: subscription.query,
                    onSave: { name, query, appState in
                        viewModel.formSaveSubscription(name: name, query: query, appState: appState)
                        activeSheet = nil
                    },
                    onCancel: {
                        viewModel.formCancel()
                        activeSheet = nil
                    }
                ).environment(appState)
            }
        case .editObserver:
            if let observer = viewModel.editorObservable {
                SubscriptionObserverEditor(
                    title: observer.name.isEmpty
                        ? "New Observer"
                        : observer.name,
                    name: observer.name,
                    query: observer.query,
                    onSave: { name, query, appState in
                        viewModel.formSaveObserver(name: name, query: query, appState: appState)
                        activeSheet = nil
                    },
                    onCancel: {
                        viewModel.formCancel()
                        activeSheet = nil
                    }
                ).environment(appState)
            }
        case .addIndex:
            AddIndexView(
                collections: viewModel.collections,
                onCancel: { activeSheet = nil },
                onCreated: {
                    activeSheet = nil
                    Task { await viewModel.refreshCollectionCounts() }
                }
            ).environment(appState)
        case .importJSON:
            ImportDataView(isPresented: importJSONBinding)
                .environment(appState)
        case .importSubscriptions:
            ImportSubscriptionsView(
                isPresented: importSubscriptionsBinding,
                existingSubscriptions: viewModel.subscriptions,
                selectedAppId: viewModel.selectedApp._id
            )
            .environment(appState)
        case .subscriptionQRDisplay:
            SubscriptionQRDisplayView(subscriptions: viewModel.subscriptions.map {
                SubscriptionQRItem(name: $0.name, query: $0.query, args: nil)
            })
        case .subscriptionQRScanner:
            SubscriptionQRScannerView { items, onProgress in
                await viewModel.importSubscriptionsFromQR(items, appState: appState, onProgress: onProgress)
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 360)
            #endif
        case .attachmentPicker:
            if let json = viewModel.attachmentTargetJson,
               let docId = viewModel.parseDocumentId(from: json)
            {
                AttachmentPickerSheet(
                    documentId: String(describing: docId),
                    collection: viewModel.attachmentTargetCollection ?? "unknown",
                    executeMode: viewModel.selectedExecuteMode
                ) { fileURL, fieldName, metadata in
                    Task {
                        await viewModel.executeAddAttachment(
                            fileURL: fileURL,
                            fieldName: fieldName,
                            metadata: metadata,
                            appState: appState
                        )
                    }
                }
            }
        case .deleteAttachmentPicker:
            if let json = viewModel.deleteAttachmentTargetJson,
               let docId = viewModel.parseDocumentId(from: json)
            {
                let attachments = AttachmentInfo.detectTokens(in: json)
                DeleteAttachmentSheet(
                    documentId: String(describing: docId),
                    collection: viewModel.deleteAttachmentTargetCollection ?? "unknown",
                    attachments: attachments
                ) { selected in
                    Task {
                        await viewModel.executeDeleteAttachment(
                            selectedAttachments: selected,
                            appState: appState
                        )
                    }
                }
            }
        }
    }

    /// Bridges legacy `Binding<Bool>` APIs (e.g. `ImportDataView.isPresented`) to
    /// the unified `activeSheet` state. Setting `false` clears the sheet.
    private var importJSONBinding: Binding<Bool> {
        Binding(
            get: { activeSheet == .importJSON },
            set: { if !$0 { activeSheet = nil } }
        )
    }

    private var importSubscriptionsBinding: Binding<Bool> {
        Binding(
            get: { activeSheet == .importSubscriptions },
            set: { if !$0 { activeSheet = nil } }
        )
    }

    init(
        isMainStudioViewPresented: Binding<Bool>,
        isClosingDatabase: Binding<Bool>,
        dittoAppConfig: DittoConfigForDatabase
    ) {
        _isMainStudioViewPresented = isMainStudioViewPresented
        _isClosingDatabase = isClosingDatabase
        _viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            VStack(alignment: .leading) {
                #if os(iOS)
                if horizontalSizeClass == .compact {
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
                            viewModel.editorSubscription = DittoSubscription.new()
                            activeSheet = .editSubscription
                        }
                        Button("Add Observer", systemImage: "eye") {
                            viewModel.editorObservable = DittoObservable.new()
                            activeSheet = .editObserver
                        }
                        Button("Add Index", systemImage: "plus.magnifyingglass") {
                            activeSheet = .addIndex
                        }

                        Divider()

                        Button("Import Subscriptions → QR Code", systemImage: "qrcode.viewfinder") {
                            activeSheet = .subscriptionQRScanner
                        }

                        // Only show Import from Server when HTTP API is configured
                        if !viewModel.selectedApp.httpApiUrl.isEmpty &&
                            !viewModel.selectedApp.httpApiKey.isEmpty
                        {
                            Button("Import Subscriptions → Server", systemImage: "arrow.down.circle") {
                                activeSheet = .importSubscriptions
                            }
                        }

                        Divider()

                        Button("Import JSON Data", systemImage: "arrow.up") {
                            activeSheet = .importJSON
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
                min: 200,
                ideal: 260,
                max: 320
            )
        } detail: {
            Group {
                switch viewModel.selectedSidebarDestination {
                case .subscriptions:
                    syncTabsDetailView()
                case .query:
                    queryDetailView()
                case .observers:
                    observeDetailView()
                case .appMetrics:
                    AppMetricsDetailView()
                    #if os(iOS)
                        .toolbar { passiveDetailToolbar() }
                    #endif
                case .queryMetrics:
                    QueryMetricsDetailView()
                    #if os(iOS)
                        .toolbar { passiveDetailToolbar() }
                    #endif
                case .logging:
                    LoggingDetailView()
                    #if os(iOS)
                        .toolbar { passiveDetailToolbar() }
                    #endif
                }
            }
            .id(viewModel.selectedSidebarDestination)
            .transition(.blurReplace)
            .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarDestination)
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
                    .inspectorColumnWidth(min: 220, ideal: 320, max: 500)
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
        #if os(macOS)
            .toolbar {
                syncCloseToolbarGroup() // Sync + Close grouped
                inspectorToggleButton() // Inspector visually separate
            }
        #else
            .toolbar {
                // Compact-only: NavigationSplitView in regular size class already
                // exposes a system column toggle; avoid duplicating it.
                if horizontalSizeClass == .compact {
                    sidebarToggleButton() // Leading: open sidebar on iPhone / iPad Slide Over
                }
                syncToolbarButton() // Trailing: sync on/off
                closeToolbarButton() // Trailing: back to database picker
            }
        #endif
            // Sync inspector items on first render (picks up the UserDefaults value after registerDefaults)
            // and kick off the initial repository load. The load runs as a tracked
            // `loadTask` on the ViewModel so `closeSelectedApp` / `deinit` can cancel it.
            .task {
                viewModel.queryInspectorMenuItems = MainStudioView.ViewModel.buildQueryInspectorItems(
                    metricsEnabled: metricsEnabled
                )
                viewModel.startLoad()
            }
            // React to metrics setting changes (macOS Settings window or iOS Settings app)
            .onChange(of: metricsEnabled) { _, enabled in
                viewModel.queryInspectorMenuItems = MainStudioView.ViewModel.buildQueryInspectorItems(metricsEnabled: enabled)
                if !enabled {
                    // Auto-navigate away from metrics sidebar destinations
                    if viewModel.selectedSidebarDestination.isMetricsDestination {
                        viewModel.selectedSidebarDestination = .subscriptions
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
            .onChange(of: viewModel.selectedSidebarDestination) { _, _ in
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
            isClosingDatabase = true
            Task {
                await viewModel.closeSelectedApp()
                isClosingDatabase = false
                isMainStudioViewPresented = false
            }
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
    /// iOS-only toolbar bundle used by passive detail views (App Metrics,
    /// Query Metrics, Logging) that have no domain-specific toolbar of their
    /// own. NavigationSplitView's parent toolbar items don't surface in the
    /// detail column on iPad regular size class, so each passive detail view
    /// declares its own.
    @ToolbarContentBuilder
    func passiveDetailToolbar() -> some ToolbarContent {
        if horizontalSizeClass == .compact {
            sidebarToggleButton()
        }
        syncToolbarButton()
        closeToolbarButton()
        inspectorToggleButton()
    }

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

        // Editor staging state — populated by the View before presenting the
        // edit-subscription / edit-observer sheet via `activeSheet`. The sheet's
        // routing enum (`ActiveSheet`) replaces the old `ActionSheetMode`.
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
        var eventStore = ObservableEventStore()

        // Coalesces high-frequency observer callbacks into a single batched
        // SwiftUI update every ~100ms to prevent invalidation storms.
        private var pendingObservedEvents: [DittoObserveEvent] = []
        private var observedEventFlushTask: Task<Void, Never>?
        private static let observedEventFlushInterval: Duration = .milliseconds(100)

        /// Tracks the structured-concurrency task that loads initial data. Stored so
        /// `closeSelectedApp` and `deinit` can cancel it if the user closes the database
        /// before load completes (e.g. tap-and-immediately-back).
        private var loadTask: Task<Void, Never>?

        // query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        /// results view
        var jsonResults: [String]

        /// UserDefaults key for the persisted sidebar destination. Mirrors the
        /// `@AppStorage` key the View uses for `selectedSyncTab`.
        @ObservationIgnored
        private static let sidebarDestinationKey = "selectedSidebarDestination"

        /// Currently selected sidebar destination. Persisted to UserDefaults so the
        /// last-viewed sidebar tab restores on relaunch (matches `@AppStorage`
        /// semantics without requiring a View-level property wrapper).
        var selectedSidebarDestination: SidebarDestination = .subscriptions {
            didSet {
                UserDefaults.standard.set(
                    selectedSidebarDestination.rawValue,
                    forKey: Self.sidebarDestinationKey
                )
            }
        }

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

        // MARK: - Attachment State

        var attachmentProgress = AttachmentProgress()
        // Attachment staging state — populated by the View before presenting the
        // attachment / delete-attachment sheet via `activeSheet`.
        var attachmentTargetJson: String?
        var attachmentTargetCollection: String?
        var deleteAttachmentTargetJson: String?
        var deleteAttachmentTargetCollection: String?

        // Attachment viewer state (inspector)
        var detectedAttachments: [AttachmentInfo] = []
        var attachmentLoadedImages: [String: Data] = [:]
        var attachmentLoadingIds: Set<String> = []
        var attachmentErrors: [String: String] = [:]

        init(_ dittoAppConfig: DittoConfigForDatabase) {
            selectedApp = dittoAppConfig

            // Restore the last-viewed sidebar destination from UserDefaults. If the
            // stored value is unrecognized (e.g. an obsolete enum case after an
            // upgrade) we fall back to `.subscriptions`. The View also gates metrics
            // destinations on `metricsEnabled` so a stale persisted metrics tab can't
            // strand the user on a hidden destination.
            let storedDestination = UserDefaults.standard
                .string(forKey: Self.sidebarDestinationKey)
                .flatMap(SidebarDestination.init(rawValue:))
            selectedSidebarDestination = storedDestination ?? .subscriptions

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
        }

        isolated deinit {
            // Cancel the load task if the ViewModel is being deallocated mid-load
            // (e.g. user closed the database before initial hydration completed and
            // closeSelectedApp didn't run for some reason). `isolated deinit` keeps
            // this on the MainActor so we can read the actor-isolated `loadTask`.
            loadTask?.cancel()
            Log.debug("MainStudioView.ViewModel deinit")
        }

        /// Starts the initial data load. Idempotent — calling repeatedly cancels any
        /// in-flight load and starts a fresh one. Called from the view's `.task` modifier.
        func startLoad() {
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                await self?.performLoad()
            }
        }

        /// Loads all repository state for the selected database in parallel and finishes
        /// post-load setup (presence observer registration, local peer info fetch).
        ///
        /// Called once per ViewModel lifetime via `startLoad()`. Honors cooperative
        /// cancellation at every awaited boundary so a fast close-during-load tears
        /// down cleanly without racing the cleanup path.
        private func performLoad() async {
            isLoading = true
            defer { isLoading = false }

            let databaseId = selectedApp.databaseId

            // 1. Register all repository update callbacks. These are quick, in-memory
            //    callback installations on the various actors — sequential `await`
            //    is fine and keeps the call-order obvious. Each closure uses
            //    `[weak self]` so a stale ViewModel doesn't keep itself alive.
            await SystemRepository.shared.setOnSyncStatusUpdate { [weak self] statusItems, completion in
                Task { @MainActor [weak self] in
                    self?.mergeStatusItems(statusItems)

                    // CRITICAL: signal completion AFTER UI update dispatches.
                    // 50ms delay allows SwiftUI LazyVGrid rendering to complete.
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        completion()
                    }
                }
            }
            await SystemRepository.shared.setOnConnectionsUpdate { [weak self] connections in
                Task { @MainActor [weak self] in
                    self?.connectionsByTransport = connections
                }
            }
            await ObservableRepository.shared.setOnObservablesUpdate { [weak self] observables in
                Task { @MainActor [weak self] in
                    self?.observerables = observables
                }
            }
            // Per-domain ordering: register callback BEFORE the corresponding load so
            // currentDatabaseId is set before any user-triggered save can fire.
            await SubscriptionsRepository.shared.setOnSubscriptionsUpdate { [weak self] newSubscriptions in
                self?.subscriptions = newSubscriptions
            }
            await CollectionsRepository.shared.setOnCollectionsUpdate { [weak self] newCollections in
                self?.collections = newCollections
            }
            await HistoryRepository.shared.setOnHistoryUpdate { [weak self] history in
                self?.history = history
            }
            await FavoritesRepository.shared.setOnFavoritesUpdate { [weak self] favorites in
                self?.favorites = favorites
            }

            guard !Task.isCancelled else { return }

            // 2. Run the five independent repository loads concurrently. Each safely
            //    swallows its own error so one failure can't starve the others —
            //    matches the original sequential behavior, just in parallel.
            async let loadedSubscriptions: [DittoSubscription] = {
                do {
                    return try await SubscriptionsRepository.shared.loadSubscriptions(for: databaseId)
                } catch {
                    Log.error("Failed to load subscriptions: \(error.localizedDescription)")
                    return []
                }
            }()
            async let loadedCollections: [DittoCollection] = {
                do {
                    return try await CollectionsRepository.shared.hydrateCollections()
                } catch {
                    Log.error("Failed to load collections: \(error.localizedDescription)")
                    return []
                }
            }()
            async let loadedHistory: [DittoQueryHistory] = {
                do {
                    return try await HistoryRepository.shared.loadHistory(for: databaseId)
                } catch {
                    Log.error("Failed to load history: \(error.localizedDescription)")
                    return []
                }
            }()
            async let loadedFavorites: [DittoQueryHistory] = {
                do {
                    return try await FavoritesRepository.shared.loadFavorites(for: databaseId)
                } catch {
                    Log.error("Failed to load favorites: \(error.localizedDescription)")
                    return []
                }
            }()
            async let loadedObservers: [DittoObservable] = {
                do {
                    return try await ObservableRepository.shared.loadObservers(for: databaseId)
                } catch {
                    Log.error("Failed to load observers: \(error.localizedDescription)")
                    return []
                }
            }()

            let (subs, cols, hist, favs, obsv) = await (
                loadedSubscriptions,
                loadedCollections,
                loadedHistory,
                loadedFavorites,
                loadedObservers
            )

            guard !Task.isCancelled else { return }

            subscriptions = subs
            collections = cols
            history = hist
            favorites = favs
            observerables = obsv

            if collections.isEmpty {
                selectedQuery = subscriptions.first?.query ?? ""
            } else {
                selectedQuery = "SELECT * FROM \(collections.first?.name ?? "")"
            }

            // 3. Start observing connections via presence graph (drives bottom status bar)
            do {
                try await SystemRepository.shared.registerConnectionsPresenceObserver()
            } catch {
                // Not a programming error — can happen if the database was closed before
                // this async Task completed (e.g. user switched databases quickly).
                Log.error("Failed to register connections presence observer: \(error.localizedDescription)")
            }

            // Note: sync-status observer is registered by syncTabsDetailView().onAppear
            // (which fires before this point). No eager registration needed here —
            // it caused double-registration and backpressure pipeline deadlocks.

            guard !Task.isCancelled else { return }

            // 4. Fetch local peer info directly (bypassing QueryService so this startup
            //    query is invisible to Query Metrics).
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

        func refreshLastQueryMetrics() async {
            lastQueryMetricsRecord = await QueryMetricsRepository.shared.allRecords().first
        }

        /// Shows JSON in the inspector panel
        func showJsonInInspector(_ json: String) {
            selectedJsonForInspector = json
            detectAttachmentsInSelectedJson()
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
            return eventStore.event(id: selectedId)
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

            // 0. Cancel any in-flight initial load so its callback registrations
            //    don't race with the cleanup pass below.
            loadTask?.cancel()
            loadTask = nil

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
            cancelObservedEventFlush()
            eventStore.removeAll()
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
            eventStore.remove(observerId: observable.id)
            pendingObservedEvents.removeAll { $0.observeId == observable.id }

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
            editorObservable = nil
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

        /// Enqueues a freshly emitted observer event onto the pending buffer
        /// and (re)schedules a flush. Coalescing across a 100ms window keeps
        /// SwiftUI from re-rendering on every individual SDK callback during
        /// high-frequency sync.
        private func enqueueObservedEvent(_ event: DittoObserveEvent) {
            pendingObservedEvents.append(event)
            guard observedEventFlushTask == nil else { return }
            observedEventFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.observedEventFlushInterval)
                guard let self else { return }
                flushPendingObservedEvents()
            }
        }

        private func flushPendingObservedEvents() {
            observedEventFlushTask = nil
            guard !pendingObservedEvents.isEmpty else { return }
            let batch = pendingObservedEvents
            pendingObservedEvents.removeAll(keepingCapacity: true)
            eventStore.append(contentsOf: batch)
        }

        private func cancelObservedEventFlush() {
            observedEventFlushTask?.cancel()
            observedEventFlushTask = nil
            pendingObservedEvents.removeAll(keepingCapacity: false)
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

            // Deserialize arguments from JSON string. The observer callback runs
            // on an SDK-determined thread (non-MainActor). Build the event from
            // the results synchronously, then hop to the MainActor to mutate
            // @Observable view-model state.
            let observableId = observable.id
            let observer = try ditto.store.registerObserver(
                query: observable.query
            ) { [weak self] results in
                // required to show the end user when the event fired
                var event = DittoObserveEvent.new(observeId: observableId)

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

                let capturedEvent = event
                Task { @MainActor [weak self] in
                    self?.enqueueObservedEvent(capturedEvent)
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
            cancelObservedEventFlush()
            eventStore.removeAll()
        }

        // MARK: - Editor Staging

        /// The View calls `presentSubscriptionEditor`/`presentObservableEditor`
        /// (in `MainStudioView` extensions) to set the editor target and toggle
        /// `activeSheet`. These VM helpers stage the data only; they don't
        /// touch sheet state, keeping the VM independent of `ActiveSheet`.
        func stageSubscriptionEditor(_ subscription: DittoSubscription) {
            editorSubscription = subscription
        }

        func stageObservableEditor(_ observable: DittoObservable) {
            editorObservable = observable
        }

        // MARK: - Attachment Parsers

        func parseCollectionName(from query: String) -> String? {
            let pattern = #"(?i)\bFROM\s+(\w+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  let range = Range(match.range(at: 1), in: query) else
            {
                return nil
            }
            return String(query[range])
        }

        func parseDocumentId(from jsonString: String) -> Any? {
            guard let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
            {
                return nil
            }
            return dict["_id"]
        }

        // MARK: - Attachment Staging

        /// Sheet presentation is handled by the View — these helpers only stage
        /// the data the sheet will read.
        func stageAddAttachment(documentJson: String) {
            attachmentTargetJson = documentJson
            attachmentTargetCollection = parseCollectionName(from: selectedQuery)
        }

        func stageDeleteAttachment(documentJson: String) {
            deleteAttachmentTargetJson = documentJson
            deleteAttachmentTargetCollection = parseCollectionName(from: selectedQuery)
        }

        func executeDeleteAttachment(
            selectedAttachments: [AttachmentInfo],
            appState: AppState
        ) async {
            guard let json = deleteAttachmentTargetJson,
                  let docId = parseDocumentId(from: json) else
            {
                appState.setError(AttachmentError.noDocumentId)
                return
            }
            guard let collection = deleteAttachmentTargetCollection else {
                appState.setError(AttachmentError.collectionNotFound)
                return
            }

            let docIdString: String = if let str = docId as? String {
                str
            } else {
                "\(docId)"
            }

            let identifierPattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/

            attachmentProgress.isActive = true
            attachmentProgress.message = "Deleting attachment field(s)..."
            attachmentProgress.fractionCompleted = 0.0

            do {
                for (index, att) in selectedAttachments.enumerated() {
                    guard att.fieldName.wholeMatch(of: identifierPattern) != nil,
                          collection.wholeMatch(of: identifierPattern) != nil else
                    {
                        throw AttachmentError.invalidFieldName
                    }
                    let query = "UPDATE \(collection) SET \(att.fieldName) = null WHERE _id = '\(docIdString)'"
                    _ = try await QueryService.shared.executeSelectedAppQuery(query: query)
                    attachmentProgress.fractionCompleted = Double(index + 1) / Double(selectedAttachments.count)
                }
                attachmentProgress.message = "Deleted \(selectedAttachments.count) field(s) — re-run query to see changes"
                try? await Task.sleep(for: .seconds(2.5))
                attachmentProgress.isActive = false
                Log.info("Deleted \(selectedAttachments.count) attachment field(s) from document \(docIdString)")
            } catch {
                attachmentProgress.isActive = false
                appState.setError(error)
            }
        }

        func executeAddAttachment(
            fileURL: URL,
            fieldName: String,
            metadata: [String: String],
            appState: AppState
        ) async {
            guard let json = attachmentTargetJson,
                  let docId = parseDocumentId(from: json) else
            {
                appState.setError(AttachmentError.noDocumentId)
                return
            }
            guard let collection = attachmentTargetCollection else {
                appState.setError(AttachmentError.collectionNotFound)
                return
            }

            // Convert document ID to String for the AttachmentService API
            let docIdString: String = if let str = docId as? String {
                str
            } else {
                "\(docId)"
            }

            attachmentProgress.isActive = true
            attachmentProgress.message = "Uploading attachment..."
            attachmentProgress.fractionCompleted = 0.0

            do {
                if selectedExecuteMode == "Local" {
                    try await AttachmentService.shared.createAndLink(
                        fileURL: fileURL,
                        metadata: metadata,
                        collection: collection,
                        documentId: docIdString,
                        fieldName: fieldName
                    )
                } else {
                    try await AttachmentService.shared.createAndLinkViaHttp(
                        fileURL: fileURL,
                        metadata: metadata,
                        collection: collection,
                        documentId: docIdString,
                        fieldName: fieldName
                    )
                }
                attachmentProgress.fractionCompleted = 1.0
                attachmentProgress.message = "Attachment linked successfully"
                try? await Task.sleep(for: .seconds(1.5))
                attachmentProgress.isActive = false
            } catch {
                attachmentProgress.isActive = false
                appState.setError(error)
            }
        }

        // MARK: - Attachment Detection & Viewing

        func detectAttachmentsInSelectedJson() {
            guard let json = selectedJsonForInspector else {
                detectedAttachments = []
                return
            }
            detectedAttachments = AttachmentInfo.detectTokens(in: json)
            attachmentLoadedImages.removeAll()
            attachmentLoadingIds.removeAll()
            attachmentErrors.removeAll()
        }

        func fetchAttachmentForViewing(_ attachment: AttachmentInfo, appState: AppState) async {
            guard let json = selectedJsonForInspector,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = dict[attachment.fieldName] as? [String: Any] else
            {
                return
            }

            attachmentLoadingIds.insert(attachment.id)
            attachmentProgress.isActive = true
            attachmentProgress.message = "Downloading attachment..."

            do {
                let fileData: Data = if selectedExecuteMode == "Local" {
                    try await AttachmentService.shared.fetch(token: token, id: attachment.id)
                } else {
                    try await AttachmentService.shared.fetchViaHttp(attachmentId: attachment.id)
                }
                attachmentProgress.isActive = false

                if attachment.isImage {
                    attachmentLoadedImages[attachment.id] = fileData
                } else {
                    // Save to temp and open in OS default app
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = attachment.fileName ?? "attachment"
                    let tempURL = tempDir.appendingPathComponent(fileName)
                    try fileData.write(to: tempURL)
                    #if os(macOS)
                    NSWorkspace.shared.open(tempURL)
                    #else
                    // UIApplication.shared.open() doesn't work with local file URLs on iOS.
                    // Use UIActivityViewController as a share sheet to let the user open/save the file.
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController
                    {
                        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                        activityVC.popoverPresentationController?.sourceView = rootVC.view
                        rootVC.present(activityVC, animated: true)
                    }
                    #endif
                }
                attachmentLoadingIds.remove(attachment.id)
            } catch {
                attachmentProgress.isActive = false
                attachmentLoadingIds.remove(attachment.id)
                attachmentErrors[attachment.id] = error.localizedDescription
                appState.setError(error)
            }
        }
    }
}

// MARK: Helpers

// MARK: - Sheet Presentation Helpers

extension MainStudioView {
    /// Stages the editor for an existing subscription and presents the editor
    /// sheet. Called from the sidebar's context menu.
    func presentSubscriptionEditor(_ subscription: DittoSubscription) {
        viewModel.stageSubscriptionEditor(subscription)
        activeSheet = .editSubscription
    }

    /// Stages the editor for an existing observable and presents the editor sheet.
    func presentObservableEditor(_ observable: DittoObservable) {
        viewModel.stageObservableEditor(observable)
        activeSheet = .editObserver
    }

    /// Stages the document JSON for the add-attachment sheet and presents it.
    func presentAddAttachment(documentJson: String) {
        viewModel.stageAddAttachment(documentJson: documentJson)
        activeSheet = .attachmentPicker
    }

    /// Stages the document JSON for the delete-attachment sheet and presents it.
    func presentDeleteAttachment(documentJson: String) {
        viewModel.stageDeleteAttachment(documentJson: documentJson)
        activeSheet = .deleteAttachmentPicker
    }
}

/// Single source of truth for which modal sheet is currently presented over the
/// studio. Replaces the previous handful of independent `Bool` flags + the
/// `ActionSheetMode` enum, ensuring only one sheet is ever active at a time
/// (SwiftUI's `.sheet(item:)` semantics) and that double-presents become
/// impossible by construction.
enum ActiveSheet: String, Identifiable {
    case editSubscription
    case editObserver
    case addIndex
    case importJSON
    case importSubscriptions
    case subscriptionQRDisplay
    case subscriptionQRScanner
    case attachmentPicker
    case deleteAttachmentPicker

    var id: String {
        rawValue
    }
}

/// Type-safe identifier for the studio sidebar's primary navigation destinations.
/// Replaces the previous string-keyed `MenuItem.name` switches so the compiler can
/// enforce exhaustive handling and `@AppStorage` can persist the selection across launches.
enum SidebarDestination: String, CaseIterable, Identifiable, Codable {
    case subscriptions
    case query
    case observers
    case appMetrics
    case queryMetrics
    case logging

    var id: String {
        rawValue
    }

    /// Human-readable label used in the sidebar list.
    var displayName: String {
        switch self {
        case .subscriptions: "Subscriptions"
        case .query: "Query"
        case .observers: "Observers"
        case .appMetrics: "App Metrics"
        case .queryMetrics: "Query Metrics"
        case .logging: "Logging"
        }
    }

    /// SF Symbol name rendered alongside the label.
    var systemIcon: String {
        switch self {
        case .subscriptions: "arrow.trianglehead.2.clockwise.rotate.90"
        case .query: "macpro.gen2"
        case .observers: "eye"
        case .appMetrics: "cpu"
        case .queryMetrics: "text.magnifyingglass"
        case .logging: "doc.plaintext.fill"
        }
    }

    /// True when this destination should only appear when telemetry is enabled.
    var isMetricsDestination: Bool {
        self == .appMetrics || self == .queryMetrics
    }
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
