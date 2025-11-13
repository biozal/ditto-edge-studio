//
//  MainStudioView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
import SwiftUI
import Combine
import DittoSwift

struct MainStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel
    @State private var showingImportView = false



    //used for editing observers and subscriptions
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
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Picker("", selection: $viewModel.selectedMenuItem) {
                        ForEach(viewModel.mainMenuItems, id: \.id) { item in
                            Label(item.name, systemImage: item.icon)
                                .labelStyle(.iconOnly)
                                .tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    .animation(.default, value: viewModel.selectedMenuItem)
                    .onChange(of: viewModel.selectedMenuItem) { _, newValue in
                        // Auto-create blank query tab when Store Explorer is selected with no tabs
                        if newValue.name == "Store Explorer" && viewModel.openTabs.isEmpty {
                            viewModel.openQueryTab("", uniqueID: nil, reuseExisting: false)
                        }
                    }
                    Spacer()
                }
                switch viewModel.selectedMenuItem.name {
                case "Sync":
                    syncSidebarView()
                case "Store Explorer":
                    storeExplorerSidebarView()
                case "Observers":
                    observersSidebarView()
                case "Ditto Tools":
                    dittoToolsSidebarView()
                default:
                    storeExplorerSidebarView()
                }
                Spacer()

                //Bottom Toolbar in Sidebar
                    HStack {
                        // Sync pane: +subscription menu
                        if viewModel.selectedMenuItem.name == "Sync" {
                            Menu {
                                Button(
                                    "Add Subscription",
                                    systemImage: "arrow.trianglehead.2.clockwise"
                                ) {
                                    viewModel.editorSubscription =
                                        DittoSubscription.new()
                                    viewModel.actionSheetMode = .subscription
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .padding(4)
                            }
                        }

                        // Store Explorer pane: +import data menu
                        if viewModel.selectedMenuItem.name == "Store Explorer" {
                            Menu {
                                Button("Import Data", systemImage: "square.and.arrow.down") {
                                    showingImportView = true
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .padding(4)
                            }
                        }

                        // Observers pane: +observer menu
                        if viewModel.selectedMenuItem.name == "Observers" {
                            Menu {
                                Button("Add Observer", systemImage: "eye") {
                                    viewModel.editorObservable = DittoObservable.new()
                                    viewModel.actionSheetMode = .observer
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .padding(4)
                            }
                        }

                        Spacer()
                    }
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.top, 4)

        } detail: {
            switch viewModel.selectedMenuItem.name {
            case "Sync":
                syncDetailView()
            case "Store Explorer":
                storeExplorerTabView()
            case "Observers":
                observersDetailView()
            case "Ditto Tools":
                dittoToolsDetailView()
            case "MongoDb":
                mongoDBDetailView()
            default:
                storeExplorerTabView()
            }
        }
        .navigationTitle(viewModel.selectedApp.name)
        .sheet(
            isPresented: isSheetPresented
        ) {
            if let subscription = viewModel.editorSubscription {
                QueryArgumentEditor(
                    title: subscription.name.isEmpty
                        ? "New Query Argument" : subscription.name,
                    name: subscription.name,
                    query: subscription.query,
                    arguments: subscription.args ?? "",
                    onSave: viewModel.formSaveSubscription,
                    onCancel: viewModel.formCancel
                ).environmentObject(appState)
            } else if let observer = viewModel.editorObservable {
                QueryArgumentEditor(
                    title: observer.name.isEmpty
                        ? "New Observer" : observer.name,
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
        .onAppear {
            // No longer needed - using DittoManager state directly
        }
        #if os(macOS)
            .toolbar {
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
        .onKeyPress(.init("n"), phases: .down) { keyPress in
            // Create new query tab when Cmd+N is pressed from any view
            if keyPress.modifiers.contains(.command) {
                viewModel.openQueryTab("", uniqueID: nil, reuseExisting: false)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("w"), phases: .down) { keyPress in
            // Close active tab if Cmd+W is pressed and we're in a tabbed view
            if keyPress.modifiers.contains(.command) &&
               viewModel.selectedMenuItem.name == "Store Explorer" {
                if let activeTabId = viewModel.activeTabId,
                   let activeTab = viewModel.openTabs.first(where: { $0.id == activeTabId }) {
                    viewModel.closeTab(activeTab)
                }
                return .handled
            }
            return .ignored
        }
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
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                    .foregroundColor(viewModel.isSyncEnabled ? .green : .red)
            }
            .help(viewModel.isSyncEnabled ? "Disable Sync" : "Enable Sync")
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
                    .foregroundColor(.red)
            }
            .help("Close App")
        }
    }

    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
    }

}

//MARK: Sidebar Views
extension MainStudioView {
    
    func subscriptionSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Subscriptions")
            SubscriptionsSidebarView(
                subscriptions: $viewModel.subscriptions,
                isLoading: $viewModel.isLoading,
                onEdit: viewModel.showSubscriptionEditor,
                onDelete: viewModel.deleteSubscription
            )
            .environmentObject(appState)
        }
    }

    func collectionsSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Ditto Collections")
            if viewModel.isLoading {
                Spacer()
                AnyView(
                    ProgressView("Loading Collections...")
                        .progressViewStyle(.circular)
                )
                Spacer()
            } else if viewModel.collections.isEmpty {
                Spacer()
                AnyView(
                    ContentUnavailableView(
                        "No Collections",
                        systemImage:
                            "exclamationmark.triangle.fill",
                        description: Text(
                            "No Collections found. Add some data or use the Import button to load data into the database."
                        )
                    )
                )
                Spacer()
            } else {
                List(viewModel.collections, id: \.self) { collection in
                    Text(collection.name)
                        .onTapGesture {
                            viewModel.selectedQuery =
                                "SELECT * FROM \(collection.name)"
                        }
                    Divider()
                }
                Spacer()
            }
        }
    }

    func syncSidebarView() -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            headerView(title: "Sync")

            // Subscriptions Section
            VStack(alignment: .leading, spacing: 0) {
                CollapsibleSection(
                    title: "Subscriptions",
                    count: viewModel.subscriptions.count,
                    isExpanded: $viewModel.isSubscriptionsExpanded
                ) {
                    subscriptionsContent
                } contextMenu: {
                    Button("Add Subscription", systemImage: "arrow.trianglehead.2.clockwise") {
                        viewModel.editorSubscription = DittoSubscription.new()
                        viewModel.actionSheetMode = .subscription
                    }
                }
                .padding(.bottom, viewModel.isSubscriptionsExpanded ? 8 : 2)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)

            Spacer()
        }
    }

    func observersSidebarView() -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            headerView(title: "Observers")

            // Observers Section
            VStack(alignment: .leading, spacing: 0) {
                CollapsibleSection(
                    title: "Observers",
                    count: viewModel.observerables.count,
                    isExpanded: $viewModel.isObserversExpanded
                ) {
                    observersContent
                } contextMenu: {
                    Button("Add Observer", systemImage: "eye") {
                        viewModel.editorObservable = DittoObservable.new()
                        viewModel.actionSheetMode = .observer
                    }
                }
                .padding(.bottom, viewModel.isObserversExpanded ? 8 : 2)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)

            Spacer()
        }
    }

    @ViewBuilder
    private var subscriptionsContent: some View {
        if viewModel.subscriptions.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Subscriptions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add subscriptions to sync data between peers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.subscriptions, id: \.id) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        isSelected: viewModel.selectedItem == .subscription(subscription.id)
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Open subscription query in a query editor tab
                            viewModel.openQueryTab(subscription.query)
                            Task {
                                await executeQuery()
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                Task {
                                    await viewModel.showSubscriptionEditor(subscription)
                                }
                            }
                            Button("Delete", role: .destructive) {
                                Task {
                                    do {
                                        try await viewModel.deleteSubscription(subscription)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var observersContent: some View {
        if viewModel.observerables.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Observers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add observers to watch real-time data changes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.observerables, id: \.id) { observer in
                    ObserverCard(
                        observer: observer,
                        isSelected: viewModel.selectedObservable?.id == observer.id
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedObservable = observer
                            Task {
                                await viewModel.loadObservedEvents()
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                Task {
                                    await viewModel.showObservableEditor(observer)
                                }
                            }

                            if observer.storeObserver == nil {
                                Button("Start Observing") {
                                    Task {
                                        do {
                                            try await viewModel.registerStoreObserver(observer)
                                            // Auto-select the observer after activating
                                            viewModel.selectedObservable = observer
                                            await viewModel.loadObservedEvents()
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            } else {
                                Button("Stop Observing") {
                                    Task {
                                        do {
                                            try await viewModel.removeStoreObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                Task {
                                    do {
                                        try await viewModel.deleteObservable(observer)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    func storeExplorerSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Store Explorer")
            StoreExplorerContextMenuView(
                collections: $viewModel.collections,
                favorites: $viewModel.favorites,
                history: $viewModel.history,
                isHistoryExpanded: $viewModel.isHistoryExpanded,
                isFavoritesExpanded: $viewModel.isFavoritesExpanded,
                selectedItem: $viewModel.selectedItem,
                isLoading: $viewModel.isLoading,
                onSelectCollection: { collection in
                    // Open collection query in a query editor tab with unique ID based on collection name
                    let query = "SELECT * FROM \(collection.name)"
                    let uniqueID = "collection-\(collection.name)"
                    viewModel.openQueryTab(query, uniqueID: uniqueID, reuseExisting: true)
                    Task {
                        await executeQuery()
                    }
                },
                onSelectQuery: { query, uniqueID in
                    viewModel.openQueryTab(query, uniqueID: uniqueID, reuseExisting: true)
                },
                appState: appState
            )
        }
    }

    func dittoToolsSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Ditto Tools")
            List(viewModel.dittoToolsFeatures, id: \.self) { tool in
                Text(tool)
                    .onTapGesture {
                        viewModel.selectedDataTool = tool
                    }
                Divider()
            }
            Spacer()
        }
    }

    func headerView(title: String) -> some View {
        return HStack {
            Spacer()
            Text(title)
                .padding(.top, 4)
            Spacer()
        }
    }
}
//MARK: Detail Views
extension MainStudioView {
    func storeExplorerTabView() -> some View {
        TabContainer(
            openTabs: $viewModel.openTabs,
            activeTabId: $viewModel.activeTabId,
            onCloseTab: { tab in
                viewModel.closeTab(tab)
            },
            onSelectTab: { tab in
                viewModel.selectTab(tab)
            },
            contentForTab: { tab in
                AnyView(
                    ViewContainer(
                        context: viewModel.viewContext(for: tab.content),
                        viewModel: viewModel,
                        appState: appState
                    )
                )
            },
            defaultContent: {
                AnyView(
                    ViewContainer(
                        context: .empty,
                        viewModel: viewModel,
                        appState: appState
                    )
                )
            },
            titleForTab: { tab in
                viewModel.getTabTitle(for: tab)
            },
            onNewQuery: {
                viewModel.openQueryTab("")  // Open empty query
            }
        )
    }

    func queryTabView() -> some View {
        TabContainer(
            openTabs: $viewModel.openTabs,
            activeTabId: $viewModel.activeTabId,
            onCloseTab: { tab in
                viewModel.closeTab(tab)
            },
            onSelectTab: { tab in
                viewModel.selectTab(tab)
            },
            contentForTab: { tab in
                AnyView(
                    ViewContainer(
                        context: viewModel.viewContext(for: tab.content),
                        viewModel: viewModel,
                        appState: appState
                    )
                )
            },
            defaultContent: {
                AnyView(
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("Query Editor")
                                .font(.title2)
                                .bold()

                            Text("Select a query from history or create a new query tab")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                )
            },
            titleForTab: { tab in
                viewModel.getTabTitle(for: tab)
            },
            onNewQuery: {
                viewModel.openQueryTab("")  // Open empty query
            }
        )
    }


    func queryDetailView() -> some View {
        return VStack(alignment: .leading) {
            #if os(macOS)
                VSplitView {
                    //top half
                    QueryEditorView(
                        queryText: $viewModel.selectedQuery,
                        executeModes: $viewModel.executeModes,
                        selectedExecuteMode: $viewModel.selectedExecuteMode,
                        isLoading: $viewModel.isQueryExecuting,
                        onExecuteQuery: executeQuery,
                        onAddToFavorites: {
                            await viewModel.addCurrentQueryToFavorites(appState: appState)
                        }
                    )

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        queryText: viewModel.selectedQuery,
                        hasExecutedQuery: viewModel.hasExecutedQuery,
                        appId: viewModel.selectedApp.appId,
                        onRefreshQuery: {
                            await viewModel.executeQuery(appState: appState)
                        }
                    )
                }
            #else
                VStack {
                    //top half
                    QueryEditorView(
                        queryText: $viewModel.selectedQuery,
                        executeModes: $viewModel.executeModes,
                        selectedExecuteMode: $viewModel.selectedExecuteMode,
                        isLoading: $viewModel.isQueryExecuting,
                        onExecuteQuery: executeQuery,
                        onAddToFavorites: {
                            await viewModel.addCurrentQueryToFavorites(appState: appState)
                        }
                    )
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        queryText: viewModel.selectedQuery,
                        hasExecutedQuery: viewModel.hasExecutedQuery,
                        appId: viewModel.selectedApp.appId,
                        onRefreshQuery: {
                            await viewModel.executeQuery(appState: appState)
                        }
                    )
                }
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }

    func observeDetailView() -> some View {
        return ObservablesView(
            observables: $viewModel.observerables,
            selectedObservable: $viewModel.selectedObservable,
            observableEvents: $viewModel.observableEvents,
            selectedEventId: $viewModel.selectedEventId,
            eventMode: $viewModel.eventMode,
            onLoadEvents: viewModel.loadObservedEvents,
            onRegisterObserver: viewModel.registerStoreObserver,
            onRemoveObserver: viewModel.removeStoreObserver,
            onDeleteObservable: viewModel.deleteObservable
        )
        .environmentObject(appState)
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }

    func syncDetailView() -> some View {
        return SyncView(
            syncStatusItems: $viewModel.syncStatusItems,
            isSyncEnabled: $viewModel.isSyncEnabled
        )
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }

    func observersDetailView() -> some View {
        return ObservablesView(
            observables: $viewModel.observerables,
            selectedObservable: $viewModel.selectedObservable,
            observableEvents: $viewModel.selectedObservableEvents,
            selectedEventId: $viewModel.selectedEventId,
            eventMode: $viewModel.eventMode,
            onLoadEvents: viewModel.loadObservedEvents,
            onRegisterObserver: viewModel.registerStoreObserver,
            onRemoveObserver: viewModel.removeStoreObserver,
            onDeleteObservable: viewModel.deleteObservable
        )
        .environmentObject(appState)
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }

    func dittoToolsDetailView() -> some View {
        return ToolsViewer(selectedDataTool: $viewModel.selectedDataTool)
            #if os(iOS)
                .toolbar {
                    appNameToolbarLabel()
                    syncToolbarButton()
                    closeToolbarButton()
                }
            #endif
    }

    func mongoDBDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("MongoDb Details View")
        }
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }

}

//MARK: ViewModel
extension MainStudioView {
    @Observable
    @MainActor
    class ViewModel {
        var selectedApp: DittoAppConfig

        //used for displaying action sheets
        var actionSheetMode: ActionSheetMode = ActionSheetMode.none
        var editorSubscription: DittoSubscription?
        var editorObservable: DittoObservable?
       
        var selectedObservable: DittoObservable?
        var selectedEventId: String?
        var selectedDataTool: String?
        var selectedItem: SelectedItem = .none
        
        // Sync status properties
        var syncStatusItems: [SyncStatusInfo] = []
        var isSyncEnabled = true  // Track sync status here

        var isLoading = false
        var isQueryExecuting = false

        var eventMode = "inserted"
        let dittoToolsFeatures = [
            "Presence Viewer", "Peers List", "Permissions Health", "Disk Usage",
        ]
        var subscriptions: [DittoSubscription] = []
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [DittoCollectionModel] = []
        var observerables: [DittoObservable] = []
        var observableEvents: [DittoObserveEvent] = []
        var selectedObservableEvents: [DittoObserveEvent] = []
        var mongoCollections: [String] = []

        // Collapsible section states
        var isHistoryExpanded: Bool = true
        var isFavoritesExpanded: Bool = true
        var isSubscriptionsExpanded: Bool = true
        var isObserversExpanded: Bool = true

        //query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        //results view
        var jsonResults: [String]
        var hasExecutedQuery: Bool = false

        //pagination
        var currentPage: Int = 0
        var pageSize: Int = 100  // Default page size
        var totalResults: Int = 0  // Total number of results available
        var isLoadingPage: Bool = false

        //MainMenu Toolbar
        var selectedMenuItem: MenuItem
        var mainMenuItems: [MenuItem] = []

        //Tab Management (shared between Store Explorer and Query tool)
        var openTabs: [TabItem] = []
        var activeTabId: UUID?
        var tabQueries: [String: String] = [:] // Maps query tab IDs to their query strings
        var tabTitles: [String: String] = [:] // Maps query tab IDs to their titles
        var tabResults: [String: [String]] = [:] // Maps query tab IDs to their results

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            let syncItem = MenuItem(
                id: 1,
                name: "Sync",
                icon: "arrow.triangle.2.circlepath"
            )
            let storeExplorerItem = MenuItem(
                id: 2,
                name: "Store Explorer",
                icon: "cylinder.split.1x2"
            )

            self.selectedMenuItem = syncItem

            // Initialize with no tabs (Sync doesn't use tabs)
            self.openTabs = []
            self.activeTabId = nil
            self.selectedItem = .none
            self.mainMenuItems = [
                syncItem,
                storeExplorerItem,
                MenuItem(id: 3, name: "Observers", icon: "eye"),
                MenuItem(id: 4, name: "Ditto Tools", icon: "gearshape"),
            ]

            //query section
            self.selectedQuery = ""
            self.selectedExecuteMode = "Local"
            if dittoAppConfig.httpApiUrl == ""
                || dittoAppConfig.httpApiKey == ""
            {
                self.executeModes = ["Local"]

            } else {
                self.executeModes = ["Local", "HTTP"]
            }

            //query results section
            self.jsonResults = []

            //default the tool to presence viewer
            selectedDataTool = "Presence Viewer"
            
            // Setup SystemRepository callback
            Task {
                await SystemRepository.shared.setOnSyncStatusUpdate { [weak self] statusItems in
                    Task { @MainActor in
                        self?.syncStatusItems = statusItems
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
            
            // Setup HistoryService callback
            Task {
                await HistoryService.shared.setOnHistoryUpdate { [weak self] history in
                    Task { @MainActor in
                        self?.history = history
                    }
                }
            }

            Task {
                isLoading = true

                // Setup observers callback BEFORE registering observer
                await ObserverService.shared.setOnObservablesUpdate { [weak self] observables in
                    print("🔍 MainStudioView: Callback received \(observables.count) observables")
                    // Debug: Print each observer's ID and name
                    for (index, obs) in observables.enumerated() {
                        print("🔍   Observer[\(index)]: id=\(obs.id), name='\(obs.name)', query='\(obs.query)', hasStoreObserver=\(obs.storeObserver != nil)")
                    }

                    Task { @MainActor in
                        print("🔍 MainStudioView: Setting observerables to \(observables.count) items")
                        // Filter out duplicates by ID
                        var uniqueObservables = Dictionary(grouping: observables, by: { $0.id })
                            .compactMap { $0.value.first }
                        print("🔍 After deduplication: \(uniqueObservables.count) unique observers")

                        // Preserve storeObserver references from existing observerables
                        if let existingObservers = self?.observerables {
                            for i in 0..<uniqueObservables.count {
                                if let existingObserver = existingObservers.first(where: { $0.id == uniqueObservables[i].id }) {
                                    // Preserve the in-memory storeObserver reference
                                    uniqueObservables[i].storeObserver = existingObserver.storeObserver
                                    if existingObserver.storeObserver != nil {
                                        print("🔍 Preserved storeObserver for: \(uniqueObservables[i].name)")
                                    }
                                }
                            }
                        }

                        // Preserve selectedObservable reference by finding the matching one in the new array
                        let previouslySelectedId = self?.selectedObservable?.id
                        self?.observerables = uniqueObservables

                        // Re-establish selectedObservable reference to the new instance
                        if let selectedId = previouslySelectedId {
                            self?.selectedObservable = uniqueObservables.first { $0.id == selectedId }
                            print("🔍 Re-established selectedObservable: \(self?.selectedObservable?.id ?? "nil")")
                        }

                        print("🔍 MainStudioView: observerables now has \(self?.observerables.count ?? -1) items")
                    }
                }

                await SubscriptionsRepository.shared.setOnSubscriptionsUpdate { newSubscriptions in
                    self.subscriptions = newSubscriptions
                }
                subscriptions = try await SubscriptionsRepository.shared.hydrateDittoSubscriptions()

                // Setup collections callback BEFORE hydrating
                await EdgeStudioCollectionService.shared.setOnCollectionsUpdate { [weak self] newCollections in
                    print("🔍 MainStudioView: Collections callback received \(newCollections.count) collections")
                    Task { @MainActor in
                        self?.collections = newCollections
                        print("🔍 MainStudioView: collections now has \(self?.collections.count ?? -1) items")
                    }
                }
                collections = try await EdgeStudioCollectionService.shared.hydrateCollections()

                history = try await HistoryService.shared.loadHistory()

                favorites = try await FavoritesRepository.shared.hydrateQueryFavorites()

                // Load favorites into in-memory service
                FavoritesService.shared.loadFavorites(favorites)

                // Start observing observables through service (callback is now set)
                do {
                    try await ObserverService.shared.registerObservablesObserver(for: selectedApp._id)
                } catch {
                    assertionFailure("Failed to register observables observer: \(error)")
                }
                
                if collections.isEmpty {
                    selectedQuery = subscriptions.first?.query ?? ""
                } else {
                    selectedQuery = "SELECT * FROM \(collections.first?.name ?? "")"
                }

                // Start observing sync status
                do {
                    try await SystemRepository.shared.registerSyncStatusObserver()
                } catch {
                    assertionFailure("Failed to register sync status observer: \(error)")
                }

                isLoading = false
            }
        }

        var selectedEventObject: DittoObserveEvent? {
            get {
                guard let selectedId = selectedEventId else { return nil }
                return observableEvents.first(where: { $0.id == selectedId })
            }
        }

        func addQueryToHistory(appState: AppState) async {
            // Use HistoryService to record every query execution
            await HistoryService.shared.recordQueryExecution(selectedQuery, appState: appState)
        }

        func addCurrentQueryToFavorites(appState: AppState) async {
            let trimmedQuery = selectedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                let queryHistory = DittoQueryHistory(
                    id: UniqueIDGenerator.generateFavoritesID(),
                    query: trimmedQuery,
                    createdDate: Date().ISO8601Format()
                )
                do {
                    try await FavoritesRepository.shared.saveFavorite(queryHistory)
                    // Update the in-memory service
                    FavoritesService.shared.addToFavorites(trimmedQuery)
                } catch {
                    appState.setError(error)
                }
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
            isSyncEnabled = false

            // Clear favorites service
            FavoritesService.shared.clear()

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
                    // Stop repository observers (now using detached tasks internally)
                    await SystemRepository.shared.stopObserver()
                    await ObserverService.shared.stopObserver()
                    await FavoritesRepository.shared.stopObserver()
                    await HistoryService.shared.stopObserving()
                    await EdgeStudioCollectionService.shared.stopObserver()
                    await SubscriptionsRepository.shared.cancelAllSubscriptions()
                    await DatabaseRepository.shared.stopDatabaseConfigSubscription()
                }
                
                group.addTask(priority: .utility) {
                    // Close DittoManager selected app
                    await DittoManager.shared.closeDittoSelectedApp()
                }
            }
        }
        
        func toggleSync() async throws {
            if isSyncEnabled {
                await DittoManager.shared.selectedAppStopSync()
                isSyncEnabled = false
            } else {
                try await DittoManager.shared.selectedAppStartSync()
                isSyncEnabled = true
            }
        }
        
        func startSync() async throws {
            try await DittoManager.shared.selectedAppStartSync()
            isSyncEnabled = true
        }
        
        func stopSync() async {
            await DittoManager.shared.selectedAppStopSync()
            isSyncEnabled = false
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            // Use the new ObserverService to handle deletion
            try await ObserverService.shared.deleteObservable(observable)

            // Clean up local state
            observableEvents.removeAll(where: {$0.observeId == observable.id})

            if (selectedObservable?.id == observable.id) {
                selectedObservable = nil
            }
            if selectedEventObject?.observeId == observable.id {
                selectedEventId = nil
            }

            // Force update the observables array by removing the deleted item
            // This ensures immediate UI feedback even if the observer callback hasn't fired yet
            observerables.removeAll(where: { $0.id == observable.id })
        }

        func deleteSubscription(_ subscription: DittoSubscription) async throws
        {
            try await SubscriptionsRepository.shared.removeDittoSubscription(subscription)
        }

        // Helper function to add pagination to a query
        func addPaginationToQuery(_ query: String, limit: Int, offset: Int) -> String {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if query already has LIMIT or OFFSET
            let upperQuery = trimmedQuery.uppercased()
            if upperQuery.contains("LIMIT") || upperQuery.contains("OFFSET") {
                // Query already has pagination, return as-is
                return query
            }

            // Add LIMIT and OFFSET to the query
            return "\(trimmedQuery) LIMIT \(limit) OFFSET \(offset)"
        }

        func executeQuery(appState: AppState, page: Int? = nil, forceServerPagination: Bool = false) async {
            isQueryExecuting = true
            isLoadingPage = true

            // If page is specified, use it; otherwise reset to page 0 for new queries
            let targetPage = page ?? 0
            let offset = targetPage * pageSize

            do {
                // Always use in-memory pagination - load all data in one shot
                // This is faster and provides better user experience for typical dataset sizes
                let shouldUseServerPagination = false

                // Execute query - always load all results
                let queryToExecute = shouldUseServerPagination
                    ? addPaginationToQuery(selectedQuery, limit: pageSize, offset: offset)
                    : selectedQuery

                if selectedExecuteMode == "Local" {
                     jsonResults = try await QueryService.shared
                        .executeSelectedAppQuery(query: queryToExecute)
                } else {
                    jsonResults = try await QueryService.shared
                        .executeSelectedAppQueryHttp(query: queryToExecute)
                }

                // Save results to the current query tab if we're on one
                if case .query(let queryId) = selectedItem {
                    tabResults[queryId] = jsonResults
                }

                // Update current page
                currentPage = targetPage
                hasExecutedQuery = true

                // Add query to history (original query, not paginated) - only on first page
                if targetPage == 0 {
                    await addQueryToHistory(appState: appState)
                }
            } catch {
                appState.setError(error)
            }
            isQueryExecuting = false
            isLoadingPage = false
        }

        // Pagination navigation functions
        func nextPage(appState: AppState) async {
            guard !isLoadingPage else { return }
            await executeQuery(appState: appState, page: currentPage + 1)
        }

        func previousPage(appState: AppState) async {
            guard currentPage > 0, !isLoadingPage else { return }
            await executeQuery(appState: appState, page: currentPage - 1)
        }

        func goToFirstPage(appState: AppState) async {
            guard currentPage > 0, !isLoadingPage else { return }
            await executeQuery(appState: appState, page: 0)
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
                        try await SubscriptionsRepository.shared.saveDittoSubscription(
                            subscription
                        )
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
                        try await ObserverService.shared.saveObservable(observer)

                        // Update in the observerables array
                        await MainActor.run {
                            if let index = observerables.firstIndex(where: { $0.id == observer.id }) {
                                observerables[index].name = observer.name
                                observerables[index].query = observer.query
                                observerables[index].args = observer.args
                            }

                            // Update selectedObservable if it matches the edited observer
                            if selectedObservable?.id == observer.id {
                                selectedObservable = observer
                            }
                        }
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
            if observerables[index].storeObserver != nil {
                throw InvalidStoreState(message: "Observer already registered")
            }

            //if you activate an observable it's instantly selected
            selectedObservable = observable

            // Use the new ObserverService to register the observer
            let observer = try await ObserverService.shared.registerStoreObserver(
                for: observable
            ) { [weak self] event in
                Task { @MainActor in
                    print("🔍 Observer event received: observeId=\(event.observeId), data count=\(event.data.count), insertions=\(event.insertIndexes.count)")
                    self?.observableEvents.append(event)

                    //if this is the selected observable, add it to the selectedEvents array too
                    if let selectedObservableId = self?.selectedObservable?.id {
                        print("🔍 Selected observable ID: \(selectedObservableId)")
                        if (event.observeId == selectedObservableId) {
                            print("🔍 Adding event to selectedObservableEvents (count before: \(self?.selectedObservableEvents.count ?? 0))")
                            self?.selectedObservableEvents.append(event)
                            print("🔍 selectedObservableEvents count after: \(self?.selectedObservableEvents.count ?? 0)")
                        } else {
                            print("🔍 Event observeId (\(event.observeId)) does not match selected (\(selectedObservableId))")
                        }
                    } else {
                        print("🔍 No selected observable")
                    }
                }
            }

            // Update the local state (don't persist storeObserver - it's not serializable)
            observerables[index].storeObserver = observer
            print("🔍 Observer registered. selectedObservable=\(selectedObservable?.id ?? "nil"), selectedObservableEvents count=\(selectedObservableEvents.count)")
        }
        
        func removeStoreObserver(_ observable: DittoObservable) async throws {
            guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
                throw InvalidStoreState(message: "Could not find observable")
            }
            observerables[index].storeObserver?.cancel()
            observerables[index].storeObserver = nil

            // Only clear events for this specific observer
            observableEvents.removeAll { $0.observeId == observable.id }

            // If this was the selected observable, clear selected events too
            if selectedObservable?.id == observable.id {
                selectedEventId = nil
                selectedObservableEvents.removeAll()
            }
        }

        func showObservableEditor(_ observable: DittoObservable) {
            editorObservable = observable
            actionSheetMode = .observer
        }

        func showSubscriptionEditor(_ subscription: DittoSubscription) {
            editorSubscription = subscription
            actionSheetMode = .subscription
        }

        // MARK: - Tab Management
        func openTab(for selectedItem: SelectedItem) {
            let (title, systemImage) = tabInfo(for: selectedItem)

            // Check if tab already exists
            if let existingTab = openTabs.first(where: { $0.content == selectedItem }) {
                activeTabId = existingTab.id
                return
            }

            let newTab = TabItem(title: title, content: selectedItem, systemImage: systemImage)
            openTabs.append(newTab)
            activeTabId = newTab.id
        }

        func closeTab(_ tab: TabItem) {
            // Find the index of the tab being closed
            guard let closingIndex = openTabs.firstIndex(where: { $0.id == tab.id }) else {
                return // Tab not found
            }

            var newActiveTab: TabItem? = nil

            // If closed tab was active, determine which tab to select next
            if activeTabId == tab.id {
                // Try to select the next tab (same index after removal)
                if closingIndex < openTabs.count - 1 {
                    newActiveTab = openTabs[closingIndex + 1]
                }
                // If no next tab, try the previous tab
                else if closingIndex > 0 {
                    newActiveTab = openTabs[closingIndex - 1]
                }
            }

            // Remove the tab
            openTabs.removeAll { $0.id == tab.id }

            // Clean up the query, title, and results dictionaries if this was a query tab
            if case .query(let queryId) = tab.content {
                tabQueries.removeValue(forKey: queryId)
                tabTitles.removeValue(forKey: queryId)
                tabResults.removeValue(forKey: queryId)
            }

            // Update active tab and selected item
            if let newTab = newActiveTab {
                activeTabId = newTab.id
                selectedItem = newTab.content
            } else if activeTabId == tab.id {
                // Only reset if the closed tab was active and no replacement found
                activeTabId = nil
                selectedItem = .none
            }
        }

        func selectTab(_ tab: TabItem) {
            // Update tab selection
            activeTabId = tab.id
            selectedItem = tab.content

            // If this is a query tab, restore its query text and results
            if case .query(let queryId) = tab.content {
                // Restore query text
                selectedQuery = tabQueries[queryId] ?? ""

                // Restore the tab's results, or empty array if no results yet
                let restoredResults = tabResults[queryId] ?? []
                jsonResults = restoredResults

                // Set hasExecutedQuery based on whether we have results
                hasExecutedQuery = !restoredResults.isEmpty
            } else {
                // For non-query tabs (subscriptions, collections, etc.), keep existing behavior
                // Results will be managed by the subscription/collection specific logic
            }
        }

        /// Opens a query tab with the given query text
        /// - Parameters:
        ///   - query: The query string to execute
        ///   - uniqueID: Optional uniqueID (with namespace prefix). If nil, generates a new 'query-' prefixed ID
        ///   - reuseExisting: If true and uniqueID is provided, will reuse an existing tab with that ID if found
        func openQueryTab(_ query: String, uniqueID: String? = nil, reuseExisting: Bool = true) {
            let queryId: String
            let isNewQuery = uniqueID == nil

            // Determine the query ID
            if let providedID = uniqueID {
                queryId = providedID

                // If reuse is enabled and it's not a new query, check for existing tab
                if reuseExisting && !isNewQuery {
                    let queryItem = SelectedItem.query(queryId)
                    if let existingTab = openTabs.first(where: { $0.content == queryItem }) {
                        // Reuse existing tab - just switch to it
                        activeTabId = existingTab.id
                        self.selectedItem = queryItem

                        // Load the stored query and results
                        if let storedQuery = tabQueries[queryId] {
                            selectedQuery = storedQuery
                        }
                        if let storedResults = tabResults[queryId] {
                            jsonResults = storedResults
                        }
                        return
                    }
                }
            } else {
                // Generate a new unique ID for a new query
                queryId = UniqueIDGenerator.generateQueryID()
            }

            // Create new tab (either no existing tab found, or it's a new query)
            let queryItem = SelectedItem.query(queryId)
            let title = generateTabTitle(from: query)

            let newTab = TabItem(
                title: title,
                content: queryItem,
                systemImage: "doc.text"
            )
            openTabs.append(newTab)
            activeTabId = newTab.id
            self.selectedItem = queryItem

            // Store the query text, title, and initialize empty results in dictionaries
            tabQueries[queryId] = query
            tabTitles[queryId] = title
            tabResults[queryId] = []

            // Set the query text and clear results for new tab
            selectedQuery = query
            jsonResults = []
        }

        /// Ensures a blank query tab is available and active
        /// If already in a query tab, does nothing
        /// If a blank query tab already exists, switches to it
        /// Otherwise, opens a new blank query tab
        func ensureBlankQueryTab() {
            // If we're already in a query tab, don't switch
            if case .query = selectedItem {
                return
            }

            // Check if there's an existing blank query tab
            for tab in openTabs {
                if case .query(let queryId) = tab.content {
                    let query = tabQueries[queryId] ?? ""
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Found a blank query tab, switch to it
                        selectTab(tab)
                        return
                    }
                }
            }

            // No blank query tab found, open a new one
            openQueryTab("", uniqueID: nil, reuseExisting: false)
        }

        // Helper method to update query text and save to dictionary if we're on a query tab
        func updateQueryText(_ newQuery: String) {
            selectedQuery = newQuery

            // If currently viewing a query tab, update its stored query
            if case .query(let queryId) = selectedItem {
                tabQueries[queryId] = newQuery
            }
        }

        // Generate a tab title from a query string
        func generateTabTitle(from query: String) -> String {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

            // If empty, return default
            guard !trimmed.isEmpty else {
                return "New Query"
            }

            // Try to extract collection name for a more meaningful title
            if let collectionName = DQLQueryParser.extractCollectionName(from: trimmed) {
                // Check if it's a SELECT, INSERT, UPDATE, DELETE, or EVICT
                let upperQuery = trimmed.uppercased()
                if upperQuery.hasPrefix("SELECT") {
                    return "SELECT \(collectionName)"
                } else if upperQuery.hasPrefix("INSERT") {
                    return "INSERT \(collectionName)"
                } else if upperQuery.hasPrefix("UPDATE") {
                    return "UPDATE \(collectionName)"
                } else if upperQuery.hasPrefix("DELETE") || upperQuery.hasPrefix("EVICT") {
                    return "DELETE \(collectionName)"
                } else {
                    return collectionName
                }
            }

            // Fallback: use first line or first 30 characters
            let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
            if firstLine.count > 30 {
                return String(firstLine.prefix(30)) + "..."
            }
            return firstLine
        }

        // Get the display title for a tab (returns updated title from dictionary if available)
        func getTabTitle(for tab: TabItem) -> String {
            if case .query(let queryId) = tab.content {
                return tabTitles[queryId] ?? tab.title
            }
            return tab.title
        }

        func viewContext(for selectedItem: SelectedItem) -> ViewContext {
            switch selectedItem {
            case .sync:
                return .sync
            case .network:
                return .home
            case .subscription(let id):
                let subscription = subscriptions.first(where: { $0.id == id })
                return .query(subscription: subscription)
            case .observer(let id):
                if let observer = observerables.first(where: { $0.id == id }) {
                    return .observer(observable: observer)
                }
                return .empty
            case .observersView:
                return .observersView
            case .collection(let name):
                return .collection(name: name)
            case .query(_):
                return .query(subscription: nil)
            case .none:
                return .empty
            }
        }

        private func tabInfo(for selectedItem: SelectedItem) -> (title: String, systemImage: String) {
            switch selectedItem {
            case .sync:
                return ("Sync", "arrow.triangle.2.circlepath")
            case .network:
                return ("Home", "house")
            case .subscription(let id):
                if let subscription = subscriptions.first(where: { $0.id == id }) {
                    return (subscription.name.isEmpty ? "Subscription" : subscription.name, "arrow.trianglehead.2.clockwise")
                }
                return ("Subscription", "arrow.trianglehead.2.clockwise")
            case .observer(let id):
                if let observer = observerables.first(where: { $0.id == id }) {
                    return (observer.name.isEmpty ? "Observer" : observer.name, "eye")
                }
                return ("Observer", "eye")
            case .observersView:
                return ("Observers", "eye")
            case .collection(let name):
                return (name, "square.stack.fill")
            case .query(_):
                return ("Query", "doc.text")
            case .none:
                return ("Store Explorer", "cylinder.split.1x2")
            }
        }
    }
}

//MARK: Helpers

enum ActionSheetMode: String {
    case none = "none"
    case subscription = "subscription"
    case observer = "observer"
    case mongoDB = "mongoDB"
}

struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var icon: String
}

enum SelectedItem: Equatable, Hashable {
    case sync                  // sync/peer status view
    case subscription(String)  // subscription ID
    case observer(String)      // observer ID (deprecated - use observersView instead)
    case observersView         // single observers tab showing all events
    case collection(String)    // collection name
    case query(String)         // query ID
    case network              // network/home view
    case none

    var id: String {
        switch self {
        case .sync:
            return "sync"
        case .subscription(let id):
            return "subscription_\(id)"
        case .observer(let id):
            return "observer_\(id)"
        case .observersView:
            return "observers"
        case .collection(let name):
            return "collection_\(name)"
        case .query(let id):
            return "query_\(id)"
        case .network:
            return "network"
        case .none:
            return "none"
        }
    }
}

// MARK: - Tab System
struct TabItem: Identifiable, Equatable, Hashable {
    let id = UUID()
    let title: String
    let content: SelectedItem
    let systemImage: String

    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - History Card Component
struct HistoryCard: View {
    let query: DittoQueryHistory
    let appState: AppState
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Text(query.query)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Reserve space for delete button to prevent layout shift
                Color.clear
                    .frame(width: 20, height: 20)
            }

            // Delete button - floats above text
            if isHovering {
                Button(action: {
                    Task {
                        do {
                            try await HistoryService.shared.deleteHistoryEntry(query.id)
                        } catch {
                            appState.setError(error)
                        }
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Remove from history")
                .transition(.opacity)
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .hoverableCard(isSelected: false)
        .padding(.horizontal, 2)
        .onHover { hovering in
            withAnimation(.linear(duration: 0)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        #if os(macOS)
        .contextMenu {
            HistoryQueryContextMenu(query: query, appState: appState)
        }
        #endif
    }
}

