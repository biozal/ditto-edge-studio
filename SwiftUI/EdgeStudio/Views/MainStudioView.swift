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
            if let subscription = viewModel.subObsVM.editorSubscription {
                SubscriptionObserverEditor(
                    title: subscription.name.isEmpty
                        ? "New Query Argument"
                        : subscription.name,
                    name: subscription.name,
                    query: subscription.query,
                    onSave: { name, query, appState in
                        viewModel.subObsVM.formSaveSubscription(name: name, query: query, appState: appState)
                        activeSheet = nil
                    },
                    onCancel: {
                        viewModel.subObsVM.formCancel()
                        activeSheet = nil
                    }
                ).environment(appState)
            }
        case .editObserver:
            if let observer = viewModel.subObsVM.editorObservable {
                SubscriptionObserverEditor(
                    title: observer.name.isEmpty
                        ? "New Observer"
                        : observer.name,
                    name: observer.name,
                    query: observer.query,
                    onSave: { name, query, appState in
                        viewModel.subObsVM.formSaveObserver(name: name, query: query, appState: appState)
                        activeSheet = nil
                    },
                    onCancel: {
                        viewModel.subObsVM.formCancel()
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
                existingSubscriptions: viewModel.subObsVM.subscriptions,
                selectedAppId: viewModel.selectedApp._id
            )
            .environment(appState)
        case .subscriptionQRDisplay:
            SubscriptionQRDisplayView(subscriptions: viewModel.subObsVM.subscriptions.map {
                SubscriptionQRItem(name: $0.name, query: $0.query, args: nil)
            })
        case .subscriptionQRScanner:
            SubscriptionQRScannerView { items, onProgress in
                await viewModel.subObsVM.importSubscriptionsFromQR(items, appState: appState, onProgress: onProgress)
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 360)
            #endif
        case .attachmentPicker:
            if let json = viewModel.attachmentVM.attachmentTargetJson,
               let docId = viewModel.attachmentVM.parseDocumentId(from: json)
            {
                AttachmentPickerSheet(
                    documentId: String(describing: docId),
                    collection: viewModel.attachmentVM.attachmentTargetCollection ?? "unknown",
                    executeMode: viewModel.queryVM.selectedExecuteMode
                ) { fileURL, fieldName, metadata in
                    Task {
                        await viewModel.attachmentVM.executeAddAttachment(
                            fileURL: fileURL,
                            fieldName: fieldName,
                            metadata: metadata,
                            executeMode: viewModel.queryVM.selectedExecuteMode,
                            appState: appState
                        )
                    }
                }
            }
        case .deleteAttachmentPicker:
            if let json = viewModel.attachmentVM.deleteAttachmentTargetJson,
               let docId = viewModel.attachmentVM.parseDocumentId(from: json)
            {
                let attachments = AttachmentInfo.detectTokens(in: json)
                DeleteAttachmentSheet(
                    documentId: String(describing: docId),
                    collection: viewModel.attachmentVM.deleteAttachmentTargetCollection ?? "unknown",
                    attachments: attachments
                ) { selected in
                    Task {
                        await viewModel.attachmentVM.executeDeleteAttachment(
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
                            viewModel.subObsVM.stageNewSubscription()
                            activeSheet = .editSubscription
                        }
                        Button("Add Observer", systemImage: "eye") {
                            viewModel.subObsVM.stageNewObservable()
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
                if viewModel.isLoading {
                    ProgressView("Loading…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("MainStudioLoadingIndicator")
                } else {
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
            }
            .id(viewModel.isLoading ? "loading" : viewModel.selectedSidebarDestination.rawValue)
            .transition(.blurReplace)
            .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarDestination)
            .animation(.smooth(duration: 0.35), value: viewModel.isLoading)
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
                viewModel.queryVM.queryInspectorMenuItems = QueryViewModel.buildQueryInspectorItems(
                    metricsEnabled: metricsEnabled
                )
                viewModel.startLoad()
            }
            // React to metrics setting changes (macOS Settings window or iOS Settings app)
            .onChange(of: metricsEnabled) { _, enabled in
                viewModel.queryVM.queryInspectorMenuItems = QueryViewModel.buildQueryInspectorItems(metricsEnabled: enabled)
                if !enabled {
                    // Auto-navigate away from metrics sidebar destinations
                    if viewModel.selectedSidebarDestination.isMetricsDestination {
                        viewModel.selectedSidebarDestination = .subscriptions
                    }
                    // Auto-navigate away from Metrics inspector tab
                    if viewModel.queryVM.selectedQueryInspectorMenuItem.name == "Metrics" {
                        viewModel.queryVM.selectedQueryInspectorMenuItem = viewModel.queryVM.queryInspectorMenuItems[0]
                    }
                }
            }
            // Refresh metrics record whenever query results change
            .onChange(of: viewModel.queryVM.jsonResults) { _, _ in
                Task { await viewModel.queryVM.refreshLastQueryMetrics() }
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
                do { try await viewModel.syncVM.toggleSync() } catch { appState.setError(error) }
            }
        } label: {
            Image(systemName: "arrow.2.circlepath")
                .foregroundStyle(viewModel.syncVM.isSyncEnabled ? Color.green : Color.red)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .help(viewModel.syncVM.isSyncEnabled ? "Disable Sync" : "Enable Sync")
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
        await viewModel.queryVM.executeQuery(appState: appState)
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

// MARK: Helpers

// MARK: - Sheet Presentation Helpers

extension MainStudioView {
    /// Stages the editor for an existing subscription and presents the editor
    /// sheet. Called from the sidebar's context menu.
    func presentSubscriptionEditor(_ subscription: DittoSubscription) {
        viewModel.subObsVM.stageSubscriptionEditor(subscription)
        activeSheet = .editSubscription
    }

    /// Stages a brand-new subscription and presents the editor sheet. Mirrors the
    /// `+` FAB menu's "Add Subscription" action so the empty-state CTA can hand
    /// off to the same editor flow.
    func presentNewSubscriptionEditor() {
        viewModel.subObsVM.stageNewSubscription()
        activeSheet = .editSubscription
    }

    /// Stages the editor for an existing observable and presents the editor sheet.
    func presentObservableEditor(_ observable: DittoObservable) {
        viewModel.subObsVM.stageObservableEditor(observable)
        activeSheet = .editObserver
    }

    /// Stages a brand-new observable and presents the editor sheet. Mirrors the
    /// `+` FAB menu's "Add Observer" action so the empty-state CTA can hand off
    /// to the same editor flow.
    func presentNewObserverEditor() {
        viewModel.subObsVM.stageNewObservable()
        activeSheet = .editObserver
    }

    /// Stages the document JSON for the add-attachment sheet and presents it.
    func presentAddAttachment(documentJson: String) {
        viewModel.attachmentVM.stageAddAttachment(
            documentJson: documentJson,
            currentQuery: viewModel.queryVM.selectedQuery
        )
        activeSheet = .attachmentPicker
    }

    /// Stages the document JSON for the delete-attachment sheet and presents it.
    func presentDeleteAttachment(documentJson: String) {
        viewModel.attachmentVM.stageDeleteAttachment(
            documentJson: documentJson,
            currentQuery: viewModel.queryVM.selectedQuery
        )
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
