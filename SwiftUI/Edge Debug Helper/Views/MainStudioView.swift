import DittoSwift
import SwiftUI

struct MainStudioView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isMainStudioViewPresented: Bool
    @State var viewModel: MainStudioView.ViewModel
    @State private var showingImportView = false
    @State private var showingImportSubscriptionsView = false
    @State var selectedSyncTab = 0 // Persists tab selection
    @State var queryCurrentPage = 1
    @State var queryPageSize = 10
    @State var observerCurrentPage = 1
    @State var observerPageSize = 25
    @State var queryIsExporting = false
    @State var queryCopiedDQLNotification: String?

    /// Inspector state
    @State var showInspector = false

    /// Column visibility control - keeps sidebar always visible
    @State var columnVisibility: NavigationSplitViewVisibility = .all

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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Picker("", selection: $viewModel.selectedSidebarMenuItem) {
                        ForEach(viewModel.sidebarMenuItems) { item in
                            item.image
                                .tag(item)
                                .font(.system(size: 20))
                                .accessibilityIdentifier("NavigationItem_\(item.name)")
                                .accessibilityLabel(item.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(ControlSize.extraLarge)
                    .labelsHidden()
                    .accessibilityIdentifier("NavigationSegmentedPicker")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                switch viewModel.selectedSidebarMenuItem.name {
                case "Collections":
                    collectionsSidebarView()
                case "Observer":
                    observeSidebarView()
                default:
                    subscriptionSidebarView()
                }
                Spacer()

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

                        // Only show Import from Server when HTTP API is configured
                        if viewModel.selectedSidebarMenuItem.name == "Subscriptions" &&
                            !viewModel.selectedApp.httpApiUrl.isEmpty &&
                            !viewModel.selectedApp.httpApiKey.isEmpty
                        {
                            Button("Import from Server", systemImage: "arrow.down.circle") {
                                showingImportSubscriptionsView = true
                            }
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
                    Spacer()
                    if viewModel.selectedSidebarMenuItem.name == "Collections" {
                        Button {
                            showingImportView = true
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(Color.dittoYellow)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .help("Import JSON data")
                    }
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            Group {
                switch viewModel.selectedSidebarMenuItem.name {
                case "Collections":
                    queryDetailView()
                case "Observer":
                    observeDetailView()
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
            .background(WindowFrameRestorer())
        #endif
            .inspector(isPresented: $showInspector) {
                inspectorView()
                    .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
            }
            .sheet(isPresented: isSheetPresented) {
                if let subscription = viewModel.editorSubscription {
                    QueryArgumentEditor(
                        title: subscription.name.isEmpty
                            ? "New Query Argument"
                            : subscription.name,
                        name: subscription.name,
                        query: subscription.query,
                        arguments: subscription.args ?? "",
                        onSave: viewModel.formSaveSubscription,
                        onCancel: viewModel.formCancel
                    ).environmentObject(appState)
                } else if let observer = viewModel.editorObservable {
                    QueryArgumentEditor(
                        title: observer.name.isEmpty
                            ? "New Observer"
                            : observer.name,
                        name: observer.name,
                        query: observer.query,
                        arguments: observer.args ?? "",
                        onSave: viewModel.formSaveObserver,
                        onCancel: viewModel.formCancel
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
        #if os(macOS)
            .toolbar {
                syncToolbarButton()
                closeToolbarButton()
                inspectorToggleButton() // Rightmost, after close button
            }
        #endif
    }

    func appNameToolbarLabel() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(viewModel.selectedApp.name).font(.headline).bold()
        }
    }

    func syncToolbarButton() -> some ToolbarContent {
        ToolbarItem(id: "syncButton", placement: .primaryAction) {
            Button {
                Task {
                    do {
                        try await viewModel.toggleSync()
                    } catch {
                        appState.setError(error)
                    }
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
    }

    func closeToolbarButton() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task {
                    await viewModel.closeSelectedApp()
                    isMainStudioViewPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Close App")
            .accessibilityIdentifier("CloseButton")
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

    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
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
            sidebarMenuItems = [
                subscriptionItem,
                MenuItem(id: 2, name: "Collections", systemIcon: "macpro.gen2"),
                MenuItem(id: 3, name: "Observer", systemIcon: "eye")
            ]

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
            let helpItem = MenuItem(id: 4, name: "Help", systemIcon: "questionmark")
            queryInspectorMenuItems = [
                helpItem,
                MenuItem(id: 5, name: "History", systemIcon: "clock"),
                MenuItem(id: 6, name: "Favorites", systemIcon: "bookmark"),
                MenuItem(id: 7, name: "JSON", systemIcon: "text.document.fill")
            ]
            selectedQueryInspectorMenuItem = helpItem

            // Setup SystemRepository callback
            Task {
                await SystemRepository.shared.setOnSyncStatusUpdate { [weak self] statusItems, completion in
                    Task { @MainActor in
                        self?.syncStatusItems = statusItems

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

            // Setup FavoritesRepository callback
            Task {
                await FavoritesRepository.shared.setOnFavoritesUpdate { [weak self] favorites in
                    Task { @MainActor in
                        self?.favorites = favorites
                    }
                }
            }

            // Setup HistoryRepository callback
            Task {
                await HistoryRepository.shared.setOnHistoryUpdate { [weak self] history in
                    Task { @MainActor in
                        self?.history = history
                    }
                }
            }

            Task {
                isLoading = true

                await SubscriptionsRepository.shared.setOnSubscriptionsUpdate { newSubscriptions in
                    self.subscriptions = newSubscriptions
                }
                // Load subscription metadata from secure storage (sync subscriptions will be re-registered as needed)
                subscriptions = try await SubscriptionsRepository.shared.loadSubscriptions(for: selectedApp.databaseId)

                await CollectionsRepository.shared.setOnCollectionsUpdate { newCollections in
                    self.collections = newCollections
                }
                collections = try await CollectionsRepository.shared.hydrateCollections()

                // Load per-database history, favorites, and observers from secure storage
                history = try await HistoryRepository.shared.loadHistory(for: selectedApp.databaseId)

                favorites = try await FavoritesRepository.shared.loadFavorites(for: selectedApp.databaseId)

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

                // Fetch local peer info via local query
                do {
                    let query = "SELECT ditto_sdk_language, ditto_sdk_platform, ditto_sdk_version FROM __small_peer_info"
                    let jsonResults = try await QueryService.shared.executeSelectedAppQuery(query: query)

                    // Parse first result (should only be one - local peer)
                    if let firstResult = jsonResults.first,
                       let data = firstResult.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        localPeerDeviceName = "Edge Studio"
                        localPeerSDKLanguage = json["ditto_sdk_language"] as? String
                        localPeerSDKPlatform = json["ditto_sdk_platform"] as? String
                        localPeerSDKVersion = json["ditto_sdk_version"] as? String
                    }
                } catch {
                    // Fail silently - not critical to app functionality
                    Log.error("Failed to fetch local peer info: \(error.localizedDescription)")
                }

                isLoading = false
            }
        }

        /// Shows JSON in the inspector panel
        func showJsonInInspector(_ json: String) {
            selectedJsonForInspector = json
            if let jsonTab = queryInspectorMenuItems.first(where: { $0.name == "JSON" }) {
                selectedQueryInspectorMenuItem = jsonTab
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
                collections = try await CollectionsRepository.shared.refreshDocumentCounts()
            } catch {
                // Error will be set in repository via appState
                Log.error("Failed to refresh collection counts: \(error.localizedDescription)")
            }
        }

        func closeSelectedApp() async {
            // First, clean up UI state immediately on main actor
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

            // Perform heavy cleanup operations on background queue to avoid priority inversion
            await performCleanupOperations()
        }

        private func performCleanupOperations() async {
            // Capture observables on main actor before moving to background queues
            let observablesToCleanup = observerables

            // Use TaskGroup to run cleanup operations concurrently on background queues
            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: .utility) {
                    // Cancel observable store observers
                    for observable in observablesToCleanup {
                        observable.storeObserver?.cancel()
                    }
                }

                group.addTask(priority: .utility) {
                    // Clear repository caches (secure storage migration)
                    await HistoryRepository.shared.clearCache()
                    await FavoritesRepository.shared.clearCache()
                    await ObservableRepository.shared.clearCache()
                    await SubscriptionsRepository.shared.clearCache()

                    // Stop other repository observers
                    await SystemRepository.shared.stopObserver()
                    await CollectionsRepository.shared.stopObserver()
                }

                group.addTask(priority: .utility) {
                    // Close DittoManager selected app
                    await DittoManager.shared.closeDittoSelectedDatabase()
                }
            }
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
            args: String?,
            appState: AppState
        ) {
            if var subscription = editorSubscription {
                subscription.name = name
                subscription.query = query
                if let argsString = args {
                    subscription.args = argsString
                } else {
                    subscription.args = nil
                }
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
            args: String?,
            appState: AppState
        ) {
            if var observer = editorObservable {
                observer.name = name
                observer.query = query
                if let argsString = args {
                    observer.args = argsString
                } else {
                    observer.args = nil
                }
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
            var arguments: [String: Any?] = [:]
            if let argsString = observable.args, !argsString.isEmpty,
               let argsData = argsString.data(using: .utf8),
               let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
            {
                arguments = argsDict
            }

            let observer = try ditto.store.registerObserver(
                query: observable.query,
                arguments: arguments
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
