import SwiftUI
import Combine
import DittoSwift

struct MainStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel
    @State private var showingImportView = false
    @State private var showingImportSubscriptionsView = false



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
                HStack(spacing: 0) {
                    ForEach(Array(viewModel.mainMenuItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Spacer()  // Distribute spacing between icons like Xcode
                        }

                        Button {
                            viewModel.selectedMenuItem = item
                        } label: {
                            Image(systemName: item.icon)
                                .font(.system(size: 13))  // Much smaller to match Xcode
                                .foregroundColor(viewModel.selectedMenuItem == item ? .primary : .secondary)
                                .frame(width: 28, height: 28)  // Smaller frame matching Xcode
                                .background(
                                    Circle()  // Circular highlight like Xcode
                                        .fill(viewModel.selectedMenuItem == item ? Color.secondary.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.name)

                        // Add divider after each icon except the last
                        // Hide divider if current or next icon is selected (Xcode behavior)
                        if index < viewModel.mainMenuItems.count - 1 {
                            let nextItem = viewModel.mainMenuItems[index + 1]
                            let shouldHideDivider = viewModel.selectedMenuItem == item || viewModel.selectedMenuItem == nextItem

                            Divider()
                                .frame(height: 20)
                                .padding(.horizontal, 4)
                                .opacity(shouldHideDivider ? 0 : 1)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)  // Small padding on both sides
                .liquidGlassToolbar()
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

                        // Only show Import from Server when HTTP API is configured
                        if viewModel.selectedMenuItem.name == "Subscriptions" &&
                           !viewModel.selectedApp.httpApiUrl.isEmpty &&
                           !viewModel.selectedApp.httpApiKey.isEmpty {
                            Button("Import from Server", systemImage: "arrow.down.circle") {
                                showingImportSubscriptionsView = true
                            }
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
                                try await HistoryRepository.shared
                                    .clearQueryHistory()
                            }
                        } label: {
                            Label("Clear History", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    } else if viewModel.selectedMenuItem.name == "Collections" {
                        Button("Import") {
                            showingImportView = true
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 12)

        } detail: {
            switch viewModel.selectedMenuItem.name {
            case "Collections", "History", "Favorites":
                queryDetailView()
            case "Observer":
                observeDetailView()
            case "Ditto Tools":
                dittoToolsDetailView()
            default:
                syncDetailView()
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
        .sheet(isPresented: $showingImportSubscriptionsView) {
            ImportSubscriptionsView(
                isPresented: $showingImportSubscriptionsView,
                existingSubscriptions: viewModel.subscriptions,
                selectedAppId: viewModel.selectedApp._id
            )
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

    private func collectionsHeaderView() -> some View {
        HStack {
            Spacer()

            Text("Ditto Collections")
                .padding(.top, 4)

            Spacer()

            Button {
                Task {
                    await viewModel.refreshCollectionCounts()
                }
            } label: {
                if viewModel.isRefreshingCollections {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshingCollections)
            .help("Refresh document counts")
            .padding(.trailing, 8)
            .padding(.top, 4)
        }
    }

    func collectionsSidebarView() -> some View {
        return VStack(alignment: .leading) {
            collectionsHeaderView()
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
                List(viewModel.collections, id: \._id) { collection in
                    HStack {
                        Text(collection.name)

                        Spacer()

                        // Badge showing document count (like Mail.app)
                        if let count = collection.documentCount {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(10)
                        }
                    }
                    .contentShape(Rectangle())
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
                    // Show device name if available, otherwise peer type
                    Text(status.deviceName ?? status.peerType)
                        .font(.headline)
                        .bold()

                    // Show OS info if available
                    if let osInfo = status.osInfo {
                        HStack(spacing: 4) {
                            Image(systemName: osIconName(for: osInfo))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(osInfo.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(status.id)
                        .font(.caption2)
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

            // Peer information (new enrichment fields)
            VStack(alignment: .leading, spacing: 8) {
                // SDK Version
                if let sdkVersion = status.dittoSDKVersion {
                    HStack {
                        Image(systemName: "apps.iphone")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Ditto SDK: \(sdkVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Connection address
                if let addressInfo = status.addressInfo {
                    HStack {
                        Image(systemName: connectionIcon(for: addressInfo.connectionType))
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(addressInfo.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // Identity metadata (collapsible with chevron)
                if let metadata = status.identityMetadata {
                    DisclosureGroup {
                        ScrollView {
                            Text(metadata)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Identity Metadata")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Active connections (collapsible with chevron)
                if let connections = status.connections, !connections.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(connections) { connection in
                                connectionBadge(for: connection, currentPeerId: status.id)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack {
                            Image(systemName: "link.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Active Connections (\(connections.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Existing sync information
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Synced to commit: \(commitId)")
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

    private func osIconName(for os: PeerOS) -> String {
        switch os {
        case .iOS:
            return "iphone"
        case .android:
            return "circle.filled.iphone"
        case .macOS:
            return "laptopcomputer"
        case .linux:
            return "server.rack"
        case .windows:
            return "pc"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func connectionIcon(for connectionType: String) -> String {
        let type = connectionType.lowercased()
        if type.contains("wifi") || type.contains("wireless") {
            return "wifi"
        } else if type.contains("bluetooth") || type.contains("ble") {
            return "bluetooth"
        } else if type.contains("websocket") || type.contains("internet") {
            return "network"
        } else if type.contains("lan") || type.contains("ethernet") {
            return "cable.connector"
        } else {
            return "antenna.radiowaves.left.and.right"
        }
    }

    private func connectionBadge(for connection: ConnectionInfo, currentPeerId: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: connection.type.iconName)
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.type.displayName)
                    .font(.caption)
                    .foregroundColor(.primary)

                if let distance = connection.displayDistance {
                    Text("Distance: \(distance)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
                        onExecuteQuery: executeQuery
                    )

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        onGetLastQuery: { viewModel.selectedQuery },
                        onInsertQuery: { dql in
                            viewModel.selectedQuery = dql
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
                        onExecuteQuery: executeQuery
                    )
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        onGetLastQuery: { viewModel.selectedQuery },
                        onInsertQuery: { dql in
                            viewModel.selectedQuery = dql
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
        
        // Sync status properties
        var syncStatusItems: [SyncStatusInfo] = []
        var isSyncEnabled = true  // Track sync status here

        var isLoading = false
        var isQueryExecuting = false
        var isRefreshingCollections = false

        var eventMode = "items"
        let dittoToolsFeatures = [
            "Presence Viewer", "Peers List", "Permissions Health", "Disk Usage",
        ]
        var subscriptions: [DittoSubscription] = []
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [DittoCollection] = []
        var observerables: [DittoObservable] = []
        var observableEvents: [DittoObserveEvent] = []
        var selectedObservableEvents: [DittoObserveEvent] = []

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

        @MainActor
        func refreshCollectionCounts() async {
            guard !isRefreshingCollections else { return } // Prevent concurrent refreshes

            isRefreshingCollections = true
            defer { isRefreshingCollections = false }

            do {
                collections = try await CollectionsRepository.shared.refreshDocumentCounts()
            } catch {
                // Error will be set in repository via appState
                print("Failed to refresh collection counts: \(error)")
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
    }
}

//MARK: Helpers

enum ActionSheetMode: String {
    case none = "none"
    case subscription = "subscription"
    case observer = "observer"
}

struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var icon: String
}

