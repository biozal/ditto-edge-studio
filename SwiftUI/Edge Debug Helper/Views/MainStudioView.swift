//
//  MainStudioView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
import SwiftUI
import Combine
import DittoSwift

struct MainStudioView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel

    @State private var isMemoryInfoPresented = false
    @State private var memoryUsageString: String? = nil

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
                            viewModel.editorObservable = DittoObservable.new()
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
        #if os(macOS)
            .toolbar {
                ToolbarItem(id: "infoButton", placement: .primaryAction) {
                    Button {
                        if let memString = MemoryUtils.residentMemoryMBString() {
                            memoryUsageString = memString
                        } else {
                            memoryUsageString = "Unable to determine memory usage."
                        }
                        isMemoryInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
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
            }
            .alert(
                "App Memory Usage",
                isPresented: $isMemoryInfoPresented,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(memoryUsageString ?? "")
                }
            )
        #endif
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
                            Button {
                                Task {
                                    do {
                                        try await DittoManager.shared
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
                                        try await DittoManager.shared.saveFavorite(query)
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
                        Button {
                            Task {
                                do {
                                    try await DittoManager.shared.deleteFavorite(query.id)
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

    func tutorialDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("Tutorial Detail View")
        }
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(id: "infoButton", placement: .primaryAction) {
                    Button {
                        if let memString = MemoryUtils.residentMemoryMBString() {
                            memoryUsageString = memString
                        } else {
                            memoryUsageString = "Unable to determine memory usage."
                        }
                        isMemoryInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
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
            }
            .alert(
                "App Memory Usage",
                isPresented: $isMemoryInfoPresented,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(memoryUsageString ?? "")
                }
            )
        #endif
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
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(id: "infoButton", placement: .primaryAction) {
                    Button {
                        if let memString = MemoryUtils.residentMemoryMBString() {
                            memoryUsageString = memString
                        } else {
                            memoryUsageString = "Unable to determine memory usage."
                        }
                        isMemoryInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
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
            }
            .alert(
                "App Memory Usage",
                isPresented: $isMemoryInfoPresented,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(memoryUsageString ?? "")
                }
            )
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
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(id: "infoButton", placement: .primaryAction) {
                    Button {
                        if let memString = MemoryUtils.residentMemoryMBString() {
                            memoryUsageString = memString
                        } else {
                            memoryUsageString = "Unable to determine memory usage."
                        }
                        isMemoryInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
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
            }
            .alert(
                "App Memory Usage",
                isPresented: $isMemoryInfoPresented,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(memoryUsageString ?? "")
                }
            )
        #endif
    }

    func dittoToolsDetailView() -> some View {
        return ToolsViewer(selectedDataTool: $viewModel.selectedDataTool)
            #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(viewModel.selectedApp.name).font(.headline).bold()
                    }
                    ToolbarItem(id: "infoButton", placement: .primaryAction) {
                        Button {
                            if let memString = MemoryUtils.residentMemoryMBString() {
                                memoryUsageString = memString
                            } else {
                                memoryUsageString = "Unable to determine memory usage."
                            }
                            isMemoryInfoPresented = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
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
                }
                .alert(
                    "App Memory Usage",
                    isPresented: $isMemoryInfoPresented,
                    actions: {
                        Button("OK", role: .cancel) {}
                    },
                    message: {
                        Text(memoryUsageString ?? "")
                    }
                )
            #endif
    }

    func mongoDBDetailView() -> some View {
        return VStack(alignment: .trailing) {
            Text("MongoDb Details View")
        }
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(id: "infoButton", placement: .primaryAction) {
                    Button {
                        if let memString = MemoryUtils.residentMemoryMBString() {
                            memoryUsageString = memString
                        } else {
                            memoryUsageString = "Unable to determine memory usage."
                        }
                        isMemoryInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
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
            }
            .alert(
                "App Memory Usage",
                isPresented: $isMemoryInfoPresented,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(memoryUsageString ?? "")
                }
            )
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
       
        var localDbStoreObserver: DittoStoreObserver?
        var selectedObservable: DittoObservable?
        var selectedEventId: String?
        var selectedDataTool: String?

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
                
                //hydrate observerables
                let observerQuery = "SELECT * FROM dittoobservations WHERE selectedApp_id = :selectedAppId ORDER BY lastUpdated"
                let observerArguments = ["selectedAppId": selectedApp._id]
                let differ = DittoDiffer()
                if let ditto = await DittoManager.shared.dittoLocal {
                    localDbStoreObserver = try ditto.store.registerObserver(query: observerQuery, arguments: observerArguments)
                    { [weak self] results in
                        let diffs = differ.diff(results.items)
                        diffs.deletions.forEach { index in
                            self?.observerables.remove(at: (index))
                        }
                        diffs.insertions.forEach { index in
                            let item = results.items[index]
                            let insertObserver = DittoObservable(item.value)
                            self?.observerables.append(insertObserver)
                        }
                    }
                }
                
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

        var selectedEventObject: DittoObserveEvent? {
            get {
                guard let selectedId = selectedEventId else { return nil }
                return observableEvents.first(where: { $0.id == selectedId })
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
            selectedEventId = nil
            selectedObservable = nil
            
            //remove oservable events registered and running
            observerables.forEach { observable in
                if let storeObserver = observable.storeObserver {
                    storeObserver.cancel()
                }
            }
            
            if let localDbSO = localDbStoreObserver {
                localDbSO.cancel()
            }
            localDbStoreObserver = nil
            
            subscriptions = []
            collections = []
            history = []
            favorites = []
            observerables = []
            observableEvents = []
            
            await DittoManager.shared.closeDittoSelectedApp()
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            
            if let storeObserver = observable.storeObserver {
                storeObserver.cancel()
            }
            
            try await DittoManager.shared.removeDittoObservable(observable)
            
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
            try await DittoManager.shared.removeDittoSubscription(subscription)
            subscriptions = await DittoManager.shared.dittoSubscriptions
        }

        func executeQuery(appState: DittoApp) async {
            isQueryExecuting = true
            do {
                if selectedExecuteMode == "Local" {
                     jsonResults = try await DittoManager.shared
                        .executeSelectedAppQuery(query: selectedQuery)
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
        
        func formSaveObserver(
            name: String,
            query: String,
            args: String?,
            appState: DittoApp
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
                        try await DittoManager.shared.saveDittoObservable(observer)
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

                event.data = results.items.compactMap { $0.jsonString() }

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

