//
//  MainStudioView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
import Combine
import SwiftUI

struct MainStudioView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel

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
                case "Collections":
                    collectionsSidebarView()
                case "History":
                    historySidebarView()
                case "Favorites":
                    favoritesSidebarView()
                case "Observer":
                    observeSidebarView()
                case "Ditto Tools":
                    dittoToolsSidebarView()
                case "MongoDb":
                    mongoDbSidebarView()
                default:
                    subscriptionSidebarView()
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
                            // Replace with proper action to add observer
                            viewModel.actionSheetMode = .observer
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .padding(4)
                    }
                    Spacer()
                    if viewModel.selectedMenuItem.name == "History" {
                        Button {
                            Task {
                                try await DittoManager.shared
                                    .clearQueryHistory()
                            }
                        } label: {
                            Label("Clear History", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    } else if viewModel.selectedMenuItem.name == "Collections" {
                        Button {
                            Task {
                                try await DittoManager.shared
                                    .clearQueryHistory()
                            }
                        } label: {
                            Label(
                                "Import",
                                systemImage: "square.and.arrow.down.on.square"
                            )
                            .labelStyle(.titleAndIcon)
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
            case "Collections", "History", "Favorites":
                queryDetailView()
            case "Observer":
                observeDetailView()
            case "Ditto Tools":
                dittoToolsDetailView()
            case "MongoDb":
                mongoDBDetailView()
            default:
                tutorialDetailView()
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
            }
        }
        .toolbar {
            #if os(macOS)
                ToolbarItem(id: "closeButton", placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.closeSelectedApp()
                            isMainStudioViewPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            #endif
        }
    }
    
    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
    }

}

#Preview {
    MainStudioView(
        isMainStudioViewPresented: Binding<Bool>.constant(false),
        dittoAppConfig: DittoAppConfig.new()
    )
}

//MARK: Sidebar Views
extension MainStudioView {

    func headerView(title: String) -> some View {
        return HStack {
            Spacer()
            Text(title)
                .padding(.top, 4)
            Spacer()
        }
    }

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
                DittoSubscriptionList(
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

    func historySidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "History")
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
                        viewModel.selectedQuery = query.query
                    }
                    #if os(macOS)
                        .contextMenu {
                            Button("Delete") {
                                Task {
                                    try await DittoManager.shared
                                    .deleteQueryHistory(query.id)
                                }
                            }
                            Button("Favorite") {
                                Task {
                                    try await DittoManager.shared.saveFavorite(
                                        query
                                    )
                                }
                            }
                        }
                    #else
                        .swipeActions(edge: .trailing) {
                            Button(role: .cancel) {
                                Task {
                                    try await DittoManager.shared
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
                        Button("Delete") {
                            Task {
                                try await DittoManager.shared.deleteFavorite(
                                    query.id
                                )
                            }
                        }
                    }
                #else
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                try await DittoManager.shared.deleteFavorite(
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
                VStack {
                    Text(
                        "No observers have been added yet. Click the plus button to add your first observers."
                    )
                    .font(.caption)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                List(viewModel.observerables) { observer in
                    Text(observer.name)
                        .onTapGesture {
                            viewModel.selectedObservable = observer
                            Task {
                                await viewModel.loadObservedEvents()
                            }
                        }
                        #if os(macOS)
                            .contextMenu {
                                Button("Edit") {
                                    Task {
                                        viewModel.showObservableEditor(observer)
                                    }
                                }
                                Button("Delete") {
                                    Task {
                                        do {
                                            try await viewModel.deleteObservable(
                                                observer
                                            )
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            }
                        #else
                                //TODO add in swipe for edit and delete
                        #endif
                    Divider()
                }
            }
            Spacer()
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

    func mongoDbSidebarView() -> some View {
        return VStack(alignment: .leading) {
            headerView(title: "MongoDB Collections")
            if viewModel.isLoading {
                AnyView(
                    ProgressView("Loading Collections...")
                        .progressViewStyle(.circular)
                )
            } else if viewModel.subscriptions.isEmpty {
                AnyView(
                    ContentUnavailableView(
                        "No Collections Found",
                        systemImage:
                            "exclamationmark.triangle.fill",
                        description: Text(
                            "No collections returned from the MongoDB API. Check your MongoDB connection string in your app configuration and try again."
                        )
                    )
                )
            } else {
                List(viewModel.mongoCollections, id: \.self) { collection in
                    Text(collection)
                        .onTapGesture {

                        }
                    Divider()
                }
            }
            Spacer()
        }
    }
}

//MARK: Detail Views
extension MainStudioView {

    func tutorialDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("Tutorial Detail View")
        }
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
                    jsonResults: $viewModel.jsonResults
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
                    jsonResults: $viewModel.jsonResults
                )
            }
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    func observeDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("Observe Detail View")
        }
    }

    func dittoToolsDetailView() -> some View {
        return ToolsViewer(selectedDataTool: $viewModel.selectedDataTool)
    }

    func mongoDBDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("MongoDb Details View")
        }
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
        var selectedEvent: DittoObserveEvent?
        var selectedDataTool: String?

        var isLoading = false
        var isQueryExecuting = false

        let dittoToolsFeatures = [
            "Presence Viewer", "Peers List", "Permissions Health", "Disk Usage",
        ]
        var subscriptions: [DittoSubscription] = []
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [String] = []
        var observerables: [DittoObservable] = []
        var observableEvents: [DittoObserveEvent] = []
        var mongoCollections: [String] = []

        //query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        //results view
        var jsonResults: [String]

        //MainMenu Toolbar
        var selectedMenuItem: MenuItem
        var mainMenuItems: [MenuItem] = []

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            let subscriptionItem = MenuItem(
                id: 1,
                name: "Subscriptions",
                icon: "arrow.trianglehead.2.clockwise"
            )

            self.selectedMenuItem = subscriptionItem
            self.mainMenuItems = [
                subscriptionItem,
                MenuItem(id: 2, name: "Collections", icon: "square.stack.fill"),
                MenuItem(id: 3, name: "History", icon: "clock"),
                MenuItem(id: 4, name: "Favorites", icon: "star"),
                MenuItem(id: 5, name: "Observer", icon: "eye"),
                MenuItem(id: 6, name: "Ditto Tools", icon: "gearshape"),
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

            Task {
                isLoading = true
                if await MongoManager.shared.isConnected {
                    self.mainMenuItems.append(
                        MenuItem(id: 7, name: "MongoDb", icon: "leaf")
                    )
                }
                subscriptions = await DittoManager.shared.dittoSubscriptions

                collections = try await DittoManager.shared
                    .hydrateCollections(updateCollections: {
                        self.collections = $0
                    })

                history = try await DittoManager.shared
                    .hydrateQueryHistory(updateHistory: {
                        self.history = $0
                    })

                favorites = try await DittoManager.shared
                    .hydrateQueryFavorites(updateFavorites: {
                        self.favorites = $0
                    })

                observerables = await DittoManager.shared.dittoObservables

                if collections.isEmpty {
                    let subscriptions = await DittoManager.shared
                        .dittoSubscriptions
                    selectedQuery = subscriptions.first?.query ?? ""
                } else {
                    selectedQuery = "SELECT * FROM \(collections.first ?? "")"
                }

                mongoCollections = await MongoManager.shared.collections

                isLoading = false
            }
        }
        
        func addQueryToHistory(appState: DittoApp) async {
            if !selectedQuery.isEmpty && selectedQuery.count > 0 {
                let queryHistory = DittoQueryHistory(
                    id: UUID().uuidString,
                    query: selectedQuery,
                    createdDate: Date().ISO8601Format()
                )
                do {
                    try await DittoManager.shared.saveQueryHistory(queryHistory)
                } catch {
                    appState.setError(error)
                }
            }
        }

        func closeSelectedApp() async {
            //nil values
            editorObservable = nil
            editorSubscription = nil
            selectedEvent = nil
            selectedObservable = nil

            subscriptions = []
            collections = []
            history = []
            favorites = []
            observerables = []
            observableEvents = []

            await DittoManager.shared.closeDittoSelectedApp()
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            try await DittoManager.shared.removeDittoObservable(observable)
            observerables = await DittoManager.shared.dittoObservables
        }

        func deleteSubscription(_ subscription: DittoSubscription) async throws
        {
            try await DittoManager.shared.removeDittoSubscription(subscription)
            subscriptions = await DittoManager.shared.dittoSubscriptions
        }
        
        func executeQuery(appState: DittoApp) async {
            isQueryExecuting = true
            do {
                if selectedExecuteMode == "Local" {
                    if let dittoResults = try await DittoManager.shared
                        .executeSelectedAppQuery(
                            query: selectedQuery
                        )
                    {
                        // Create an array of JSON strings from the results
                        let resultJsonStrings = dittoResults.compactMap {
                            item -> String? in
                            // Convert [String: Any?] to [String: Any] by removing nil values
                            let cleanedValue = item.value.compactMapValues {
                                $0
                            }

                            do {
                                let data = try JSONSerialization.data(
                                    withJSONObject: cleanedValue,
                                    options: [
                                        .prettyPrinted,
                                        .fragmentsAllowed,
                                        .sortedKeys,
                                        .withoutEscapingSlashes,
                                    ]
                                )
                                return String(data: data, encoding: .utf8)
                            } catch {
                                return nil
                            }
                        }

                        if !resultJsonStrings.isEmpty {
                            jsonResults = resultJsonStrings
                        } else {
                            jsonResults = ["No results found"]
                        }
                    } else {
                        jsonResults = ["No results found"]
                    }
                } else {
                    jsonResults = try await DittoManager.shared
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
            appState: DittoApp
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
                        try await DittoManager.shared.saveDittoSubscription(
                            subscription
                        )
                        subscriptions = await DittoManager.shared
                            .dittoSubscriptions
                    } catch {
                        appState.setError(error)
                    }
                    editorSubscription = nil
                }
            }
            actionSheetMode = .none
        }

        func loadObservedEvents() async {
            observableEvents = []
            observableEvents = await DittoManager.shared.dittoObservableEvents
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
