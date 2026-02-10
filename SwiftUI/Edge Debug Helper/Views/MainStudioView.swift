import SwiftUI
import Combine
import DittoSwift

struct MainStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel
    @State private var showingImportView = false
    @State private var showingImportSubscriptionsView = false
    @State private var selectedSyncTab = 0  // Persists tab selection

    // Inspector state
    @State private var showInspector = false

    // Column visibility control - keeps sidebar always visible
    @State private var columnVisibility: NavigationSplitViewVisibility = .all



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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Picker("", selection: $viewModel.selectedSidebarMenuItem) {
                        ForEach(viewModel.sidebarMenuItems) { item in
                            item.image
                                .tag(item)
                                .accessibilityIdentifier("NavigationItem_\(item.name)")
                                .accessibilityLabel(item.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .liquidGlassToolbar()
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
                        if viewModel.selectedSidebarMenuItem.name == "Subscriptions" &&
                           !viewModel.selectedApp.httpApiUrl.isEmpty &&
                           !viewModel.selectedApp.httpApiKey.isEmpty {
                            Button("Import from Server", systemImage: "arrow.down.circle") {
                                showingImportSubscriptionsView = true
                            }
                        }
                    } label: {
                        FontAwesomeText(icon: ActionIcon.circlePlus, size: 20)
                            .padding(4)
                    }
                    Spacer()
                    if viewModel.selectedSidebarMenuItem.name == "Collections" {
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
            .padding(.bottom, 16)  // Add padding for status bar height
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)

        } detail: {
            switch viewModel.selectedSidebarMenuItem.name {
            case "Collections":
                queryDetailView()
            case "Observer":
                observeDetailView()
            default:
                syncTabsDetailView()
            }
        }
        .navigationTitle(viewModel.selectedApp.name)
        .inspector(isPresented: $showInspector) {
            inspectorView()
                .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
        }
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
                inspectorToggleButton()  // Rightmost, after close button
            }
        #endif
        .overlay(alignment: .bottom) {
            ConnectionStatusBar(
                connections: viewModel.connectionsByTransport,
                isSyncEnabled: viewModel.isSyncEnabled
            )
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
                FontAwesomeText(icon: NavigationIcon.syncLight, size: 20,
                    color: viewModel.isSyncEnabled ? .green : .red)
            }
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
                FontAwesomeText(icon: ActionIcon.circleXmarkLight, size: 20, color: .red)
            }
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
            .help("Toggle Inspector")
            .accessibilityIdentifier("Toggle Inspector")
        }
    }

    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
    }

    // MARK: - Inspector Helper Methods

    /// Loads a query from the inspector and automatically switches to Collections view if needed
    /// to ensure the QueryEditor is visible.
    private func loadQueryFromInspector(_ query: String) {
        // CRITICAL: Force sidebar to stay visible BEFORE any state changes
        columnVisibility = .all

        // Only Collections view has the QueryEditor now (History/Favorites are in inspector)
        if viewModel.selectedSidebarMenuItem.name != "Collections" {
            // Switch to Collections to show the QueryEditor
            if let collectionsItem = viewModel.sidebarMenuItems.first(where: { $0.name == "Collections" }) {
                viewModel.selectedSidebarMenuItem = collectionsItem
            }
        }

        // Load the query
        viewModel.selectedQuery = query

        // Double-check sidebar stays visible after state changes
        DispatchQueue.main.async { [self] in
            self.columnVisibility = .all
        }
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
                    FontAwesomeText(icon: NavigationIcon.refresh, size: 14)
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

    func syncTabsDetailView() -> some View {
        return VStack(spacing: 0) {
            // Tab selector (segmented picker with icons)
            Picker("", selection: $selectedSyncTab) {
                Text("Peers List")
                .tag(0)

                Text("Presence Viewer")
                .tag(1)

                Text("Settings")
                .tag(2)

                Text("Viewer")
                .tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .accessibilityIdentifier("SyncTabPicker")

            // Tab content
            Group {
                switch selectedSyncTab {
                case 0:
                    ConnectedPeersView(viewModel: viewModel)
                case 1:
                    PresenceViewerTab()
                        .padding(.bottom, 28)  // Add padding for status bar
                case 2:
                    TransportConfigView()
                case 3:
                    PresenceViewerSK()
                        .padding(.bottom, 28)  // Add padding for status bar
                default:
                    ConnectedPeersView(viewModel: viewModel)
                }
            }
        }
        // Note: Toolbar buttons are already added at NavigationSplitView level (line 198)
        // on macOS, so no need to add them here
    }

    // MARK: - Legacy Connected Peers View (extracted to ConnectedPeersView component)
    // This function is kept for reference but no longer used
    private func legacySyncDetailView() -> some View {
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

                        // Separator section
                        if let deviceName = viewModel.localPeerDeviceName,
                           let sdkLanguage = viewModel.localPeerSDKLanguage,
                           let sdkPlatform = viewModel.localPeerSDKPlatform,
                           let sdkVersion = viewModel.localPeerSDKVersion {

                            Spacer()
                                .frame(height: 20)

                            Divider()
                                .padding(.horizontal)

                            Spacer()
                                .frame(height: 20)

                            // Local Peer Info Card
                            LocalPeerInfoCard(
                                deviceName: deviceName,
                                sdkLanguage: sdkLanguage,
                                sdkPlatform: sdkPlatform,
                                sdkVersion: sdkVersion
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.bottom, 28)  // Add padding for status bar height
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
                            FontAwesomeText(icon: osIcon(for: osInfo), size: 12, color: .secondary)
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
                        FontAwesomeText(icon: SystemIcon.sdk, size: 12, color: .secondary)
                        Text("Ditto SDK: \(sdkVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Connection address
                if let addressInfo = status.addressInfo {
                    HStack {
                        FontAwesomeText(icon: connectionIcon(for: addressInfo.connectionType), size: 12, color: .secondary)
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
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .secondary)
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
                            FontAwesomeText(icon: SystemIcon.link, size: 12, color: .secondary)
                            Text("Active Connections (\(connections.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Existing sync information
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        FontAwesomeText(icon: SystemIcon.circleCheck, size: 12, color: .green)
                        Text("Synced to commit: \(commitId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    FontAwesomeText(icon: SystemIcon.clock, size: 12, color: .secondary)
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

    private func osIcon(for os: PeerOS) -> FAIcon {
        switch os {
        case .iOS:
            return PlatformIcon.iOS
        case .android:
            return PlatformIcon.android
        case .macOS:
            return PlatformIcon.apple
        case .linux:
            return PlatformIcon.linux
        case .windows:
            return PlatformIcon.windows
        case .unknown:
            return SystemIcon.question
        }
    }

    private func connectionIcon(for connectionType: String) -> FAIcon {
        let type = connectionType.lowercased()
        if type.contains("wifi") || type.contains("wireless") {
            return ConnectivityIcon.wifi
        } else if type.contains("bluetooth") || type.contains("ble") {
            return ConnectivityIcon.bluetooth
        } else if type.contains("websocket") || type.contains("internet") {
            return ConnectivityIcon.network
        } else if type.contains("lan") || type.contains("ethernet") {
            return ConnectivityIcon.ethernet
        } else {
            return ConnectivityIcon.broadcastTower
        }
    }

    private func connectionBadge(for connection: ConnectionInfo, currentPeerId: String) -> some View {
        HStack(spacing: 6) {
            FontAwesomeText(icon: connection.type.icon, size: 12, color: .secondary)

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
        return VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
                // 50/50 split: 50% editor, 50% results
                // GeometryReader provides exact percentage heights
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top section - Query Editor (50% of available height)
                        QueryEditorView(
                            queryText: $viewModel.selectedQuery,
                            executeModes: $viewModel.executeModes,
                            selectedExecuteMode: $viewModel.selectedExecuteMode,
                            isLoading: $viewModel.isQueryExecuting,
                            onExecuteQuery: executeQuery
                        )
                        .frame(height: geometry.size.height * 0.5)

                        // Visual divider
                        Divider()

                        // Bottom section - Query Results (50% of available height)
                        QueryResultsView(
                            jsonResults: $viewModel.jsonResults,
                            onGetLastQuery: { viewModel.selectedQuery },
                            onInsertQuery: { dql in
                                viewModel.selectedQuery = dql
                            },
                            onJsonSelected: { json in
                                viewModel.showJsonInInspector(json)
                                showInspector = true  // Auto-open inspector
                            }
                        )
                        .frame(height: geometry.size.height * 0.5)
                    }
                }
            #else
                VStack(spacing: 0) {
                    //top half
                    QueryEditorView(
                        queryText: $viewModel.selectedQuery,
                        executeModes: $viewModel.executeModes,
                        selectedExecuteMode: $viewModel.selectedExecuteMode,
                        isLoading: $viewModel.isQueryExecuting,
                        onExecuteQuery: executeQuery
                    )
                    .frame(maxHeight: .infinity)

                    Divider()

                    //bottom half
                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        onGetLastQuery: { viewModel.selectedQuery },
                        onInsertQuery: { dql in
                            viewModel.selectedQuery = dql
                        },
                        onJsonSelected: { json in
                            viewModel.showJsonInInspector(json)
                            showInspector = true  // Auto-open inspector
                        }
                    )
                    .frame(maxHeight: .infinity)
                }
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 28)  // Add padding for status bar height
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

                } else {
                    observableEventsList()
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
        .padding(.bottom, 28)  // Add padding for status bar height
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
    }
}

//MARK: Inspector Views
extension MainStudioView {

    @ViewBuilder
    private func inspectorView() -> some View {
        VStack(spacing: 0) {
            // Tab picker using standard SwiftUI segmented picker
            HStack {
                Spacer()
                Picker("", selection: $viewModel.selectedInspectorMenuItem) {
                    ForEach(viewModel.inspectorMenuItems) { item in
                        item.image
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .liquidGlassToolbar()
                .accessibilityIdentifier("InspectorSegmentedPicker")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Inspector content
            ScrollView {
                switch viewModel.selectedInspectorMenuItem.name {
                case "History":
                    historyInspectorContent()
                case "Favorites":
                    favoritesInspectorContent()
                case "JSON":
                    jsonInspectorContent()
                default:
                    historyInspectorContent()
                }
            }
            .scrollIndicators(.hidden)
            .padding()
        }
    }

    @ViewBuilder
    private func historyInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query History")
                .font(.headline)
                .padding(.bottom, 4)

            if viewModel.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("No queries have been run yet.")
                )
            } else {
                ForEach(viewModel.history) { query in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            FontAwesomeText(icon: UIIcon.clock, size: 12)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)  // Align with first line of text
                            Text(query.query)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)  // Take full available width
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .onTapGesture {
                        // KEY: Use helper method to auto-switch sidebar
                        loadQueryFromInspector(query.query)
                    }
                    .contextMenu {
                        Button("Delete") {
                            Task {
                                try await HistoryRepository.shared.deleteQueryHistory(query.id)
                            }
                        }
                        Button("Add to Favorites") {
                            Task {
                                try await FavoritesRepository.shared.saveFavorite(query)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func favoritesInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorite Queries")
                .font(.headline)
                .padding(.bottom, 4)

            if viewModel.favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("No favorite queries saved yet.")
                )
            } else {
                ForEach(viewModel.favorites) { query in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            FontAwesomeText(icon: UIIcon.star, size: 12)
                                .foregroundColor(.yellow)
                                .padding(.top, 2)  // Align with first line of text
                            Text(query.query)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)  // Take full available width
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .onTapGesture {
                        // KEY: Use helper method to auto-switch sidebar
                        loadQueryFromInspector(query.query)
                    }
                    .contextMenu {
                        Button("Remove from Favorites") {
                            Task {
                                try await FavoritesRepository.shared.deleteFavorite(query.id)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func jsonInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JSON Viewer")
                .font(.headline)
                .padding(.bottom, 4)

            if let json = viewModel.selectedJsonForInspector {
                JsonSyntaxView(jsonString: json)
                    .id(json)  // Force recreation when JSON changes
            } else {
                // Empty state: centered message
                VStack(spacing: 12) {
                    Spacer()
                    FontAwesomeText(icon: DataIcon.code, size: 48, color: .secondary)
                    Text("Select a JSON result to view it here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        var connectionsByTransport: ConnectionsByTransport = .empty

        // Local peer info
        var localPeerDeviceName: String?
        var localPeerSDKLanguage: String?
        var localPeerSDKPlatform: String?
        var localPeerSDKVersion: String?

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

        //query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        //results view
        var jsonResults: [String]

        //Sidebar Toolbar
        var selectedSidebarMenuItem: MenuItem
        var sidebarMenuItems: [MenuItem] = []
        
        //Inspector Toolbar
        var selectedInspectorMenuItem: MenuItem
        var inspectorMenuItems: [MenuItem] = []

        // JSON Inspector State
        var selectedJsonForInspector: String?

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            let subscriptionItem = MenuItem(
                id: 1,
                name: "Subscriptions",
                systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"
            )

            self.selectedSidebarMenuItem = subscriptionItem
            self.sidebarMenuItems = [
                subscriptionItem,
                MenuItem(id: 2, name: "Collections", systemIcon: "macpro.gen2"),
                MenuItem(id: 3, name: "Observer", systemIcon: "eye"),
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
            
            // Inspector toolbar (initialize after all non-optional properties)
            let historyItem = MenuItem(id: 4, name: "History", systemIcon: "clock")
            self.inspectorMenuItems = [
                historyItem,
                MenuItem(id: 5, name: "Favorites", systemIcon: "bookmark"),
                MenuItem(id: 6, name: "JSON", systemIcon: "text.document.fill")
            ]
            self.selectedInspectorMenuItem = historyItem

            //default the tool to presence viewer
            selectedDataTool = "Presence Viewer"
            
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

                // Start observing connections via presence graph
                do {
                    try await SystemRepository.shared.registerConnectionsPresenceObserver()
                } catch {
                    assertionFailure("Failed to register connections presence observer: \(error)")
                }

                // Fetch local peer info via local query
                do {
                    let query = "SELECT device_name, ditto_sdk_language, ditto_sdk_platform, ditto_sdk_version FROM __small_peer_info"
                    let jsonResults = try await QueryService.shared.executeSelectedAppQuery(query: query)

                    // Parse first result (should only be one - local peer)
                    if let firstResult = jsonResults.first,
                       let data = firstResult.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        localPeerDeviceName = json["device_name"] as? String
                        localPeerSDKLanguage = json["ditto_sdk_language"] as? String
                        localPeerSDKPlatform = json["ditto_sdk_platform"] as? String
                        localPeerSDKVersion = json["ditto_sdk_version"] as? String
                    }
                } catch {
                    // Fail silently - not critical to app functionality
                    print("Failed to fetch local peer info: \(error)")
                }

                isLoading = false
            }
        }

        /// Shows JSON in the inspector panel
        func showJsonInInspector(_ json: String) {
            selectedJsonForInspector = json
            if let jsonTab = inspectorMenuItems.first(where: { $0.name == "JSON" }) {
                selectedInspectorMenuItem = jsonTab
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
                // Disable sync
                await DittoManager.shared.selectedAppStopSync()

                // Stop observers to prevent stale data updates
                await SystemRepository.shared.stopObserver()

                // Reset connection counts
                connectionsByTransport = .empty
                syncStatusItems = []

                isSyncEnabled = false
            } else {
                // Enable sync
                try await DittoManager.shared.selectedAppStartSync()
                isSyncEnabled = true

                // Restart observers with fresh connections
                do {
                    try await SystemRepository.shared.registerSyncStatusObserver()
                    try await SystemRepository.shared.registerConnectionsPresenceObserver()
                } catch {
                    assertionFailure("Failed to restart observers: \(error)")
                }
            }
        }
        
        func startSync() async throws {
            try await DittoManager.shared.selectedAppStartSync()
            isSyncEnabled = true

            // Restart observers with fresh connections
            do {
                try await SystemRepository.shared.registerSyncStatusObserver()
                try await SystemRepository.shared.registerConnectionsPresenceObserver()
            } catch {
                assertionFailure("Failed to restart observers: \(error)")
            }
        }
        
        func stopSync() async {
            await DittoManager.shared.selectedAppStopSync()

            // Stop observers to prevent stale data updates
            await SystemRepository.shared.stopObserver()

            // Reset connection counts
            connectionsByTransport = .empty
            syncStatusItems = []

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
    var systemIcon: String  // SF Symbol name (e.g., "clock", "bookmark")

    // Computed property for rendering in pickers
    @ViewBuilder
    var image: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 48))
    }
}

