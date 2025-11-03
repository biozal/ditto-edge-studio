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
                    Spacer()
                }
                switch viewModel.selectedMenuItem.name {
                case "Store Explorer":
                    storeExplorerSidebarView()
                case "Query":
                    querySidebarView()
                case "Favorites":
                    favoritesSidebarView()
                case "Ditto Tools":
                    dittoToolsSidebarView()
                default:
                    storeExplorerSidebarView()
                }
                Spacer()

                //Bottom Toolbar in Sidebar
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
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .padding(4)
                    }
                    Spacer()
                    if viewModel.selectedMenuItem.name == "Query" {
                        Button {
                            Task {
                                try await HistoryRepository.shared
                                    .clearQueryHistory()
                            }
                        } label: {
                            Label("Clear History", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 6)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.top, 4)

        } detail: {
            switch viewModel.selectedMenuItem.name {
            case "Store Explorer":
                storeExplorerTabView()
            case "Query":
                queryTabView()
            case "Favorites":
                queryDetailView()
            case "Observer":
                observeDetailView()
            case "Ditto Tools":
                dittoToolsDetailView()
            case "MongoDb":
                mongoDBDetailView()
            default:
                queryDetailView()
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
            if viewModel.isLoading {
                Spacer()
                AnyView(
                    ProgressView("Loading Subscriptions...")
                        .progressViewStyle(.circular)
                )
                Spacer()
            } else if viewModel.subscriptions.isEmpty {
                Spacer()
                AnyView(
                    ContentUnavailableView(
                        "No Subscriptions",
                        systemImage:
                            "exclamationmark.triangle.fill",
                        description: Text(
                            "No apps have been added yet. Click the plus button in the bottom left corner to add your first subscription."
                        )
                    )
                )
                Spacer()
            } else {
                SubscriptionList(
                    subscriptions: $viewModel.subscriptions,
                    onEdit: viewModel.showSubscriptionEditor,
                    onDelete: viewModel.deleteSubscription,
                    appState: appState
                )
            }
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
                    Text(collection)
                        .onTapGesture {
                            viewModel.selectedQuery =
                                "SELECT * FROM \(collection)"
                        }
                    Divider()
                }
                Spacer()
            }
        }
    }

    func querySidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Query History")

            // New Query button
            Button(action: {
                viewModel.openQueryTab("")  // Open empty query
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("New Query")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            if viewModel.isLoading {
                Spacer()
                AnyView(
                    ProgressView("Loading History...")
                        .progressViewStyle(.circular)
                )
                Spacer()
            } else if viewModel.history.isEmpty {
                Spacer()
                AnyView(
                    ContentUnavailableView(
                        "No History",
                        systemImage:
                            "exclamationmark.triangle.fill",
                        description: Text(
                            "No queries have been ran or query history has been cleared."
                        )
                    )
                )
                Spacer()
            } else {
                List(viewModel.history) { query in
                    VStack(alignment: .leading) {
                        Text(query.query)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onTapGesture {
                        // Open query in a new tab
                        viewModel.openQueryTab(query.query)
                    }
                    #if os(macOS)
                        .contextMenu {
                            Button {
                                Task {
                                    do {
                                        try await HistoryRepository.shared
                                        .deleteQueryHistory(query.id)
                                    }catch{
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label(
                                    "Delete",
                                    systemImage: "trash"
                                )
                                .labelStyle(.titleAndIcon)
                            }
                            Button {
                                Task {
                                    do {
                                        try await FavoritesRepository.shared.saveFavorite(query)
                                    }catch{
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label(
                                    "Favorite",
                                    systemImage: "star"
                                )
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    #else
                        .swipeActions(edge: .trailing) {
                            Button(role: .cancel) {
                                Task {
                                    try await FavoritesRepository.shared
                                    .saveFavorite(query)
                                }
                            } label: {
                                Label("Favorite", systemImage: "star")
                            }

                            Button(role: .destructive) {
                                Task {
                                    try await DittoManager.shared
                                    .deleteQueryHistory(query.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    #endif
                    Divider()
                }
            }
        }
    }

    func favoritesSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Favorites")
            List(viewModel.favorites) { query in
                VStack(alignment: .leading) {
                    Text(query.query)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(.body, design: .monospaced))
                }
                .onTapGesture {
                    viewModel.selectedQuery = query.query
                }
                #if os(macOS)
                    .contextMenu {
                        Button {
                            Task {
                                do {
                                    try await FavoritesRepository.shared.deleteFavorite(query.id)
                                }catch{
                                    appState.setError(error)
                                }
                            }
                        } label: {
                            Label(
                                "Delete",
                                systemImage: "trash"
                            )
                            .labelStyle(.titleAndIcon)
                        }
                    }
                #else
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                try await FavoritesRepository.shared.deleteFavorite(
                                    query.id
                                )
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                #endif
                Divider()
            }
            Spacer()
        }
    }

    func observeSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "Observers")
            if viewModel.observerables.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Observers",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No observers have been added yet. Click the plus button to add your first observers."
                    )
                )
            } else {
                List(viewModel.observerables) { observer in
                    observerCard(observer: observer)
                        .onTapGesture {
                            viewModel.selectedObservable = observer
                            Task {
                                await viewModel.loadObservedEvents()
                            }
                        }
                        #if os(macOS)
                            .contextMenu {
                                if observer.storeObserver == nil {
                                    Button {
                                        Task {
                                            do {
                                                try await viewModel.registerStoreObserver(observer)
                                                                                          
                                            } catch {
                                                appState.setError(error)
                                            }
                                        }
                                    } label: {
                                        Label(
                                            "Activate",
                                            systemImage: "play.circle"
                                        )
                                        .labelStyle(.titleAndIcon)
                                    }
                                } else {
                                    Button {
                                        Task {
                                            do {
                                                try await viewModel.removeStoreObserver(observer)
                                            } catch {
                                                appState.setError(error)
                                            }
                                        }
                                    } label: {
                                        Label(
                                            "Stop",
                                            systemImage: "stop.circle"
                                        )
                                        .labelStyle(.titleAndIcon)
                                    }
                                }
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.deleteObservable(observer)
                                        }catch{
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label(
                                        "Delete",
                                        systemImage: "trash"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                        #else
                            .swipeActions(edge: .trailing) {
                                if observer.storeObserver == nil {
                                    Button {
                                        Task {
                                            do {
                                                try await viewModel.registerStoreObserver(observer)
                                            } catch {
                                                appState.setError(error)
                                            }
                                        }
                                    } label: {
                                        Label("Activate", systemImage: "play.circle")
                                    }
                                } else {
                                    Button {
                                        Task {
                                            do {
                                                try await viewModel.removeStoreObserver(observer)
                                            } catch {
                                                appState.setError(error)
                                            }
                                        }
                                    } label: {
                                        Label("Stop", systemImage: "stop.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await viewModel.deleteObservable(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        #endif
                    Divider()
                }
            }
            Spacer()
        }
    }

    func storeExplorerSidebarView() -> some View {
        return VStack(alignment: .leading) {
            StoreExplorerContextMenuView(
                subscriptions: $viewModel.subscriptions,
                observers: $viewModel.observerables,
                collections: Binding(
                    get: { viewModel.collections.map { DittoCollectionModel(name: $0, documentCount: 0) } },
                    set: { _ in }
                ),
                selectedItem: $viewModel.selectedItem,
                onSelectNetwork: {
                    viewModel.selectedItem = .network
                    viewModel.openTab(for: .network)
                },
                onSelectSubscription: { subscription in
                    let selectedItem = SelectedItem.subscription(subscription.id)
                    viewModel.selectedItem = selectedItem
                    viewModel.openTab(for: selectedItem)
                    viewModel.selectedQuery = subscription.query
                    Task {
                        await executeQuery()
                    }
                },
                onEditSubscription: viewModel.showSubscriptionEditor,
                onDeleteSubscription: viewModel.deleteSubscription,
                onEditObserver: viewModel.showObservableEditor,
                onDeleteObserver: viewModel.deleteObservable,
                onStartObserver: viewModel.registerStoreObserver,
                onStopObserver: viewModel.removeStoreObserver,
                onSelectObserver: { observable in
                    let selectedItem = SelectedItem.observer(observable.id)
                    viewModel.selectedItem = selectedItem
                    viewModel.openTab(for: selectedItem)
                    viewModel.selectedObservable = observable
                    Task {
                        await viewModel.loadObservedEvents()
                    }
                },
                onSelectCollection: { collection in
                    let selectedItem = SelectedItem.collection(collection.name)
                    viewModel.selectedItem = selectedItem
                    viewModel.openTab(for: selectedItem)
                    viewModel.selectedQuery = "SELECT * FROM \(collection.name)"
                    Task {
                        await executeQuery()
                    }
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

    private func observerCard(observer: DittoObservable) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill((observer.storeObserver == nil ? Color.gray.opacity(0.15) : Color.green.opacity(0.15)))
                .shadow(radius: 1)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(observer.name)
                        .font(.headline)
                        .bold()
                  
                }
                Spacer()
                if (observer.storeObserver == nil){
                    Text("Idle")
                        .font(.subheadline)
                        .padding(.trailing, 4)
                } else {
                    Text("Active")
                        .font(.subheadline)
                        .bold()
                        .padding(.trailing, 4)
                }
            }
            .padding()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
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
                    .padding()
                )
            },
            titleForTab: { tab in
                viewModel.getTabTitle(for: tab)
            }
        )
    }


    func syncDetailView() -> some View {
        return VStack(alignment: viewModel.syncStatusItems.isEmpty ? .center : .leading) {
            // Header with last update time
            HStack {
                Text("Connected Peers")
                    .font(.title2)
                    .bold()
                Spacer()
                if let lastUpdate = viewModel.syncStatusItems.first?.lastUpdateReceivedTime {
                    Text("Last updated: \(Date(timeIntervalSince1970: lastUpdate / 1000.0), formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            if viewModel.syncStatusItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Sync Status Available",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        description: Text("Enable sync to see connected peers and their status")
                    )
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.syncStatusItems) { statusInfo in
                            syncStatusCard(for: statusInfo)
                        }
                    }
                    .padding()
                }
            }
        }
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }
    
    private func syncStatusCard(for status: SyncStatusInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with peer type and connection status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.peerType)
                        .font(.headline)
                        .bold()
                    Text(status.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: status.syncSessionStatus))
                        .frame(width: 8, height: 8)
                    Text(status.syncSessionStatus)
                        .font(.subheadline)
                        .foregroundColor(statusColor(for: status.syncSessionStatus))
                }
            }
            
            Divider()
            
            // Sync information
            VStack(alignment: .leading, spacing: 8) {
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Synced to local database commit: \(commitId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Last update: \(status.formattedLastUpdate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "Connected":
            return .green
        case "Connecting":
            return .orange
        case "Disconnected":
            return .red
        default:
            return .gray
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
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
                        onExecuteQuery: executeQuery
                    )

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        queryText: viewModel.selectedQuery,
                        hasExecutedQuery: viewModel.hasExecutedQuery,
                        appId: viewModel.selectedApp.appId
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
                        onExecuteQuery: executeQuery
                    )
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        queryText: viewModel.selectedQuery,
                        hasExecutedQuery: viewModel.hasExecutedQuery,
                        appId: viewModel.selectedApp.appId
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
        return VStack(alignment: .trailing) {
#if os(macOS)
            VSplitView {
                if viewModel.selectedObservable == nil {
                    observableDetailNoContent()
                        .frame(minHeight: 200)

                } else {
                    observableEventsList()
                        .frame(minHeight: 200)
                }
                observableDetailSelectedEvent(observeEvent: viewModel.selectedEventObject)
            }
#else
            VStack {
                if viewModel.selectedObservable == nil {
                    observableDetailNoContent()
                } else {
                    observableEventsList()
                }
                observableDetailSelectedEvent(observeEvent: viewModel.selectedEventObject)
            }
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

//MARK: Observe functions
extension MainStudioView {
    
    fileprivate func observableEventsList() -> some View {
        return VStack {
            if viewModel.observableEvents.isEmpty {
                ContentUnavailableView(
                    "No Observer Events",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "Activate an observer to see observable events."
                    )
                )
            } else {
                Table(viewModel.observableEvents, selection: Binding<Set<String>>(get: {
                    if let selectedId = viewModel.selectedEventId {
                        return Set([selectedId])
                    } else {
                        return Set<String>()
                    }
                }, set: { newValue in
                    if let first = newValue.first {
                        viewModel.selectedEventId = first
                    } else {
                        viewModel.selectedEventId = nil
                    }
                })) {
                    TableColumn("Time") { event in
                        Text(event.eventTime)
                    }
                    TableColumn("Count") { event in
                        Text("\(event.data.count)")
                    }
                    TableColumn("Inserted") { event in
                        Text("\(event.insertIndexes.count)")
                    }
                    TableColumn("Updated") { event in
                        Text("\(event.updatedIndexes.count)")
                    }
                    TableColumn("Deleted") { event in
                        Text("\(event.deletedIndexes.count)")
                    }
                    TableColumn("Moves") { event in
                        Text("\(event.movedIndexes.count)")
                    }
                }
                .navigationTitle("Observer Events")
            }
        }
    }
    
    fileprivate func observableDetailNoContent() -> some View {
        return VStack {
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "Please select an observer from the siderbar to view events."
                )
            )
        }
    }
    
    fileprivate func observableDetailSelectedEvent(observeEvent: DittoObserveEvent?) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            if let event = observeEvent {
                Picker("", selection: $viewModel.eventMode) {
                    Text("Items")
                        .tag("items")
                    Text("Inserted")
                        .tag("inserted")
                    Text("Updated")
                        .tag("updated")
                }
#if os(macOS)
                .padding(.top, 24)
#else
                .padding(.top, 8)
#endif
                .padding(.bottom, 8)
                .pickerStyle(.segmented)
                .frame(width: 200)
                switch viewModel.eventMode {
                    case "inserted":
                        VStack(alignment: .leading, spacing: 0) {
                            ResultJsonViewer(resultText: event.getInsertedData())
                        }
                    case "updated":
                        VStack(alignment: .leading, spacing: 0) {
                            ResultJsonViewer(resultText: event.getUpdatedData())
                        }
                    default:
                        VStack(alignment: .leading, spacing: 0) {
                            ResultJsonViewer(resultText: event.data)
                        }
                }
                Spacer()
            
            } else {
                ResultJsonViewer(resultText: [])
            }
        }
        .padding(.leading, 12)
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
        
        var eventMode = "items"
        let dittoToolsFeatures = [
            "Presence Viewer", "Peers List", "Permissions Health", "Disk Usage",
        ]
        var subscriptions: [DittoSubscription] = []
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [String] = []
        var observerables: [DittoObservable] = []
        var observableEvents: [DittoObserveEvent] = []
        var selectedObservableEvents: [DittoObserveEvent] = []
        var mongoCollections: [String] = []

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

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            let storeExplorerItem = MenuItem(
                id: 1,
                name: "Store Explorer",
                icon: "cylinder.split.1x2"
            )

            self.selectedMenuItem = storeExplorerItem

            // Initialize with home tab
            let homeTab = TabItem(title: "Home", content: .network, systemImage: "house")
            self.openTabs = [homeTab]
            self.activeTabId = homeTab.id
            self.selectedItem = .network
            self.mainMenuItems = [
                storeExplorerItem,
                MenuItem(id: 2, name: "Query", icon: "doc.text"),
                MenuItem(id: 3, name: "Favorites", icon: "star"),
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
                subscriptions = try await SubscriptionsRepository.shared.hydrateDittoSubscriptions()

                await CollectionsRepository.shared.setOnCollectionsUpdate { newCollections in
                    self.collections = newCollections
                }
                collections = try await CollectionsRepository.shared.hydrateCollections()

                history = try await HistoryRepository.shared.hydrateQueryHistory()

                favorites = try await FavoritesRepository.shared.hydrateQueryFavorites()
                
                // Start observing observables through repository
                do {
                    try await ObservableRepository.shared.registerObservablesObserver(for: selectedApp._id)
                } catch {
                    print("Failed to register observables observer: \(error)")
                }
                
                if collections.isEmpty {
                    selectedQuery = subscriptions.first?.query ?? ""
                } else {
                    selectedQuery = "SELECT * FROM \(collections.first ?? "")"
                }

                // Start observing sync status
                do {
                    try await SystemRepository.shared.registerSyncStatusObserver()
                } catch {
                    print("Failed to register sync status observer: \(error)")
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
            if !selectedQuery.isEmpty && selectedQuery.count > 0 {
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
                    await ObservableRepository.shared.stopObserver()
                    await FavoritesRepository.shared.stopObserver()
                    await HistoryRepository.shared.stopObserver()
                    await CollectionsRepository.shared.stopObserver()
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
            
            if let storeObserver = observable.storeObserver {
                storeObserver.cancel()
            }
            
            try await ObservableRepository.shared.removeDittoObservable(observable)
            
            //remove events for the observable
            observableEvents.removeAll(where: {$0.observeId == observable.id})
            
            if (selectedObservable?.id == observable.id) {
                selectedObservable = nil
            }
            if selectedEventObject?.observeId == observable.id {
                selectedEventId = nil
            }
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

        func executeQuery(appState: AppState, page: Int? = nil) async {
            isQueryExecuting = true
            isLoadingPage = true

            // If page is specified, use it; otherwise reset to page 0 for new queries
            let targetPage = page ?? 0
            let offset = targetPage * pageSize

            do {
                // Add pagination to the query
                let paginatedQuery = addPaginationToQuery(selectedQuery, limit: pageSize, offset: offset)

                if selectedExecuteMode == "Local" {
                     jsonResults = try await QueryService.shared
                        .executeSelectedAppQuery(query: paginatedQuery)
                } else {
                    jsonResults = try await QueryService.shared
                        .executeSelectedAppQueryHttp(query: paginatedQuery)
                }

                // Update current page
                currentPage = targetPage
                hasExecutedQuery = true

                // Add query to history (original query, not paginated)
                await addQueryToHistory(appState: appState)
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
            
            //if you activate an observable it's instantly selected
            selectedObservable = observable
            
            //used for calculating the diffs
            let dittoDiffer = DittoDiffer()
            
            //TODO: fix arguments serialization
            let observer = try ditto.store.registerObserver(
                query: observable.query,
                arguments: [:]
            ) { [weak self] results in
                //required to show the end user when the event fired
                var event = DittoObserveEvent.new(observeId: observable.id)

                let diff = dittoDiffer.diff(results.items)

                event.eventTime = Date().ISO8601Format()

                //set diff information
                event.insertIndexes = Array(diff.insertions)
                event.deletedIndexes = Array(diff.deletions)
                event.updatedIndexes = Array(diff.updates)
                event.movedIndexes = Array(diff.moves)

                event.data = results.items.compactMap {
                    let data = $0.jsonData()
                    return String(data: data, encoding: .utf8)
                }

                self?.observableEvents.append(event)
                
                //if this is the selected observable, add it to the selectedEvents array too
                if let selectedObservableId = self?.selectedObservable?.id {
                    if (event.observeId == selectedObservableId) {
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
            print("DEBUG: closeTab called for tab: \(tab.title) with id: \(tab.id)")
            print("DEBUG: Current open tabs count: \(openTabs.count)")
            print("DEBUG: Current active tab id: \(String(describing: activeTabId))")

            // Find the index of the tab being closed
            guard let closingIndex = openTabs.firstIndex(where: { $0.id == tab.id }) else {
                print("DEBUG: Tab not found in openTabs array!")
                return // Tab not found
            }

            print("DEBUG: Tab found at index: \(closingIndex)")

            var newActiveTab: TabItem? = nil

            // If closed tab was active, determine which tab to select next
            if activeTabId == tab.id {
                print("DEBUG: Closing the active tab, need to select a new one")
                // Try to select the next tab (same index after removal)
                if closingIndex < openTabs.count - 1 {
                    newActiveTab = openTabs[closingIndex + 1]
                    print("DEBUG: Will select next tab: \(newActiveTab?.title ?? "nil")")
                }
                // If no next tab, try the previous tab
                else if closingIndex > 0 {
                    newActiveTab = openTabs[closingIndex - 1]
                    print("DEBUG: Will select previous tab: \(newActiveTab?.title ?? "nil")")
                }
                // If no other tabs, newActiveTab remains nil
                else {
                    print("DEBUG: No other tabs available")
                }
            } else {
                print("DEBUG: Closing non-active tab")
            }

            // Remove the tab
            let countBefore = openTabs.count
            openTabs.removeAll { $0.id == tab.id }
            let countAfter = openTabs.count
            print("DEBUG: Removed tab. Count before: \(countBefore), after: \(countAfter)")

            // Clean up the query and title dictionaries if this was a query tab
            if case .query(let queryId) = tab.content {
                tabQueries.removeValue(forKey: queryId)
                tabTitles.removeValue(forKey: queryId)
            }

            // Update active tab and selected item
            if let newTab = newActiveTab {
                activeTabId = newTab.id
                selectedItem = newTab.content
                print("DEBUG: Set new active tab: \(newTab.title)")
            } else if activeTabId == tab.id {
                // Only reset if the closed tab was active and no replacement found
                activeTabId = nil
                selectedItem = .none
                print("DEBUG: Reset to no active tab")
            }

            print("DEBUG: closeTab completed. Final tab count: \(openTabs.count)")
        }

        func selectTab(_ tab: TabItem) {
            activeTabId = tab.id
            selectedItem = tab.content

            // If this is a query tab, restore its query text
            if case .query(let queryId) = tab.content {
                if let savedQuery = tabQueries[queryId] {
                    selectedQuery = savedQuery
                }
            }
        }

        func openQueryTab(_ query: String) {
            // Generate a unique ID for this query tab
            let queryId = UUID().uuidString

            // Use a special query case instead of subscription
            let queryItem = SelectedItem.query(queryId)

            // Generate title from query
            let title = generateTabTitle(from: query)

            // Open the tab
            let newTab = TabItem(
                title: title,
                content: queryItem,
                systemImage: "doc.text"
            )
            openTabs.append(newTab)
            activeTabId = newTab.id
            self.selectedItem = queryItem

            // Store the query text and title in dictionaries
            tabQueries[queryId] = query
            tabTitles[queryId] = title

            // Set the query text
            selectedQuery = query
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
    case subscription(String)  // subscription ID
    case observer(String)      // observer ID
    case collection(String)    // collection name
    case query(String)         // query ID
    case network              // network view
    case none

    var id: String {
        switch self {
        case .subscription(let id):
            return "subscription_\(id)"
        case .observer(let id):
            return "observer_\(id)"
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

