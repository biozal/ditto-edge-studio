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
    @AppStorage("selectedSyncTab", store: StudioPreferences.store) var selectedSyncTab = 0
    /// Shared VM for the Presence Viewer. Lives at MainStudioView level so the
    /// `syncTabsDetailView` body can BOTH host the viewer AND inject its controls
    /// into the native trailing Viewer Controls menu on iOS (or the floating
    /// `DetailBottomBar` on macOS).
    @State var presenceViewerVM = PresenceViewerSK.ViewModel()
    @State var queryCurrentPage = 1
    @State var queryPageSize = 10
    @State var observerCurrentPage = 1
    @State var observerPageSize = 25
    @State var queryIsExporting = false
    @State var queryCopiedDQLNotification: String?
    /// Sidebar disclosure state. Private — sidebar code in
    /// `SidebarViews.swift` toggles via `expandedBinding(for:)` /
    /// `toggleSubscriptionExpansion(_:)` / `toggleObserverExpansion(_:)`
    /// helpers below.
    @State private var expandedCollectionIds: Set<String> = []
    @State private var expandedSubscriptionIds: Set<String> = []
    @State private var expandedObserverIds: Set<String> = []

    // Observe detail pane state
    @State var observeDetailViewMode: ResultViewTab = .raw
    @State var observeDetailCurrentPage = 1
    @State var observeDetailPageSize = 10
    @State var observeDetailFilteredData: [String] = []

    /// Mirrors the UserDefaults "metricsEnabled" key; drives sidebar visibility.
    /// Updated by the macOS Settings window or iOS Settings app via @AppStorage KVO.
    @AppStorage("metricsEnabled", store: StudioPreferences.store) var metricsEnabled = true

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
                databaseId: viewModel.selectedApp.databaseId
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
                DeleteAttachmentSheet(
                    documentId: String(describing: docId),
                    collection: viewModel.attachmentVM.deleteAttachmentTargetCollection ?? "unknown",
                    attachments: viewModel.attachmentVM.deleteAttachmentTokens
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
            set: {
                if !$0 {
                    activeSheet = nil
                }
            }
        )
    }

    private var importSubscriptionsBinding: Binding<Bool> {
        Binding(
            get: { activeSheet == .importSubscriptions },
            set: {
                if !$0 {
                    activeSheet = nil
                }
            }
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
                unifiedSidebarView()
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 16) // Add padding for status bar height
            #if os(iOS)
                .toolbar {
                    // This toolbar belongs to the sidebar, so it is visible only
                    // while the compact split view presents that column. Native
                    // toolbar chrome supplies Liquid Glass and adapts the action
                    // into iPhone Duo's vertical control rail.
                    if horizontalSizeClass == .compact {
                        sidebarDismissToolbarButton()
                    }
                }
            #endif
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
                    case .systemMetrics:
                        SystemMetricsDetailView(
                            databaseId: viewModel.selectedApp._id,
                            service: viewModel.systemMetricsService
                        )
                        #if os(iOS)
                            .toolbar { passiveDetailToolbar() }
                        #endif
                    case .queryMetrics:
                        QueryMetricsDetailView()
                        #if os(iOS)
                            .toolbar { passiveDetailToolbar() }
                        #endif
                    case .logging:
                        #if os(iOS)
                        LoggingDetailView(
                            leadingToolbar: {
                                if showsLeadingSidebarToggle {
                                    sidebarToggleButton()
                                }
                                studioActionsToolbarMenu()
                            },
                            trailingWorkspaceToolbar: {
                                workspaceToolbarActions()
                            }
                        )
                        #else
                        // macOS does not render these injected iOS toolbar
                        // slots. Keep its existing Logs header/footer and root
                        // window toolbar unchanged while supplying concrete
                        // toolbar-content types for this generic view.
                        LoggingDetailView(
                            leadingToolbar: {
                                ToolbarItem(placement: .automatic) { EmptyView() }
                            },
                            trailingWorkspaceToolbar: {
                                ToolbarItem(placement: .automatic) { EmptyView() }
                            }
                        )
                        #endif
                    }
                }
            }
            .id(viewModel.isLoading ? "loading" : viewModel.selectedSidebarDestination.rawValue)
            .transition(.blurReplace)
            .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarDestination)
            .animation(.smooth(duration: 0.35), value: viewModel.isLoading)
            #if os(iOS)
                // The detail toolbars own the compact Sidebar action. Hide
                // NavigationSplitView's automatic back affordance so passive detail
                // screens do not render a second control that opens the same sidebar.
                .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
            #endif
            #if os(iOS)
            .toolbar {
                if viewModel.selectedSidebarDestination != .logging {
                    studioActionsToolbarMenu()
                }
            }
            #endif
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
                studioActionsToolbarMenu()
                workspaceToolbarActions()
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

    /// Creation and import actions belong to native toolbar chrome instead of a
    /// custom floating sidebar control. This lets iPhone Duo keep the menu in
    /// its trailing action rail and lets macOS present it in the window toolbar.
    private var studioActionsMenu: some View {
        Menu {
            Button("Add Subscription", systemImage: "arrow.trianglehead.2.clockwise") {
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
            Label("Add", systemImage: "plus")
        }
        .accessibilityIdentifier("StudioActionsMenu")
    }

    @ToolbarContentBuilder
    func studioActionsToolbarMenu() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "studioActions", placement: .primaryAction) {
                studioActionsMenu
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "studioActions", placement: .primaryAction) {
                studioActionsMenu
            }
        }
        #else
        ToolbarItem(id: "studioActions", placement: .primaryAction) {
            studioActionsMenu
        }
        #endif
    }

    /// Label(title + symbol) instead of a bare Image: iPhone Duo presents bar
    /// items vertically and drops any item that has neither a title nor a
    /// symbol; the title also feeds the system overflow menu. See
    /// "Preparing your app for iPhone Duo" — Organize items in your bars.
    private var syncButtonContent: some View {
        Button {
            Task {
                do { try await viewModel.syncVM.toggleSync() } catch { appState.setError(error) }
            }
        } label: {
            Label("Sync", systemImage: "arrow.2.circlepath")
                .foregroundStyle(viewModel.syncVM.isSyncEnabled ? Color.green : Color.red)
        }
        .help(viewModel.syncVM.isSyncEnabled ? "Disable Sync" : "Enable Sync")
        // Distinct from the three bottom-bar sync buttons, which all use "SyncButton" —
        // a shared identifier makes an XCUITest query ambiguous. The value exposes the
        // state itself, so sync-state regressions are mechanically checkable rather than
        // only inspectable as a colour.
        .accessibilityIdentifier("SyncToggleButton")
        .accessibilityValue(viewModel.syncVM.isSyncEnabled ? "on" : "off")
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
            Label("Close", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
        .help("Close App")
        .accessibilityIdentifier("CloseButton")
    }

    @ToolbarContentBuilder
    func syncToolbarButton() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "syncButton", placement: .primaryAction) { syncButtonContent }
                .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "syncButton", placement: .primaryAction) { syncButtonContent }
        }
        #else
        ToolbarItem(id: "syncButton", placement: .primaryAction) { syncButtonContent }
        #endif
    }

    @ToolbarContentBuilder
    func closeToolbarButton() -> some ToolbarContent {
        #if os(iOS)
        // Closing a database changes the workspace; it is not cancellation of
        // transient UI. Keep it with the other workspace actions on Duo.
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "closeDatabase", placement: .primaryAction) { closeButtonContent }
                .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "closeDatabase", placement: .primaryAction) { closeButtonContent }
        }
        #else
        ToolbarItem(placement: .cancellationAction) { closeButtonContent }
        #endif
    }

    func syncCloseToolbarGroup() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            syncButtonContent
            closeButtonContent
        }
    }

    @ToolbarContentBuilder
    func inspectorToggleButton() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            // Inspector is a frequent workspace action. Keep it in Duo's trailing
            // rail; the system can still overflow it only when space is constrained.
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                inspectorToggleContent
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                inspectorToggleContent
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            inspectorToggleContent
        }
        #endif
    }

    private var inspectorToggleContent: some View {
        Button {
            showInspector.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.right")
                .foregroundStyle(showInspector ? .primary : .secondary)
        }
        .help("Toggle Inspector")
        .accessibilityIdentifier("Toggle Inspector")
    }

    /// The persistent workspace controls are always declared after a screen's
    /// contextual actions. This keeps the trailing order stable across the
    /// Studio: Sync, Close, then Inspector.
    @ToolbarContentBuilder
    func workspaceToolbarActions() -> some ToolbarContent {
        #if os(macOS)
        syncCloseToolbarGroup()
        inspectorToggleButton()
        #else
        syncToolbarButton()
        closeToolbarButton()
        inspectorToggleButton()
        #endif
    }

    #if os(iOS)
    /// Detail toolbars provide a sidebar toggle only while split-view navigation
    /// is collapsed. On iPhone Duo’s open display the sidebar is already visible,
    /// so a second toggle would duplicate both the navigation affordance and the
    /// system’s vertical action rail.
    var showsLeadingSidebarToggle: Bool {
        horizontalSizeClass == .compact
    }

    /// iOS-only toolbar bundle used by passive detail views (App Metrics,
    /// Query Metrics, Logging) that have no domain-specific toolbar of their
    /// own. NavigationSplitView's parent toolbar items don't surface in the
    /// detail column on iPad regular size class, so each passive detail view
    /// declares its own.
    @ToolbarContentBuilder
    func passiveDetailToolbar() -> some ToolbarContent {
        if showsLeadingSidebarToggle {
            sidebarToggleButton()
        }
        workspaceToolbarActions()
    }

    /// Native Presence action so iPhone Duo can place it in the shared detail
    /// toolbar instead of leaving a custom gear button in the content header.
    @ToolbarContentBuilder
    func transportSettingsToolbarButton() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "transportSettings", placement: .primaryAction) {
                TransportSettingsButton()
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "transportSettings", placement: .primaryAction) {
                TransportSettingsButton()
            }
        }
    }

    func sidebarToggleButton() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                preferredCompactColumn = .sidebar
            } label: {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            .accessibilityIdentifier("SidebarToggleButton")
        }
    }

    /// Dismisses a compact sidebar without changing its selected destination.
    /// As a native primary action, the system renders this as a Liquid Glass
    /// control in the standard top bar on iPhone and iPad, and moves it into
    /// iPhone Duo's trailing vertical action rail when supported.
    private var sidebarDismissButtonContent: some View {
        Button {
            preferredCompactColumn = .detail
        } label: {
            Label("Dismiss Sidebar", systemImage: "xmark")
        }
        .accessibilityIdentifier("SidebarDismissButton")
    }

    @ToolbarContentBuilder
    func sidebarDismissToolbarButton() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "dismissSidebar", placement: .primaryAction) {
                sidebarDismissButtonContent
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "dismissSidebar", placement: .primaryAction) {
                sidebarDismissButtonContent
            }
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
                if isExpanded {
                    expandedCollectionIds.insert(collection._id)
                } else {
                    expandedCollectionIds.remove(collection._id)
                }
            }
        )
    }

    func expandedSubscriptionBinding(for sub: DittoSubscription) -> Binding<Bool> {
        Binding(
            get: { expandedSubscriptionIds.contains(sub.id) },
            set: {
                if $0 {
                    expandedSubscriptionIds.insert(sub.id)
                } else {
                    expandedSubscriptionIds.remove(sub.id)
                }
            }
        )
    }

    /// Toggles whether the named subscription is expanded in the sidebar.
    /// Public so sidebar button taps in `SidebarViews.swift` can flip expansion
    /// without reaching into the private `expandedSubscriptionIds` state.
    func toggleSubscriptionExpansion(_ id: String) {
        expandedSubscriptionIds.formSymmetricDifference([id])
    }

    /// Toggles whether the named observable is expanded in the sidebar.
    func toggleObserverExpansion(_ id: String) {
        expandedObserverIds.formSymmetricDifference([id])
    }

    func expandedObserverBinding(for obs: DittoObservable) -> Binding<Bool> {
        Binding(
            get: { expandedObserverIds.contains(obs.id) },
            set: {
                if $0 {
                    expandedObserverIds.insert(obs.id)
                } else {
                    expandedObserverIds.remove(obs.id)
                }
            }
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
    case systemMetrics
    case logging

    var id: String {
        rawValue
    }

    /// Human-readable label used in the sidebar list. Mirrors the Android labels in
    /// `StudioNavItem` so users moving between platforms see the same names.
    var displayName: String {
        switch self {
        case .subscriptions: "Presence"
        case .query: "Query Workbench"
        case .observers: "Observation"
        case .appMetrics: "App Metrics"
        case .queryMetrics: "Query Metrics"
        case .systemMetrics: "System Metrics"
        case .logging: "Log Analyzer"
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
        case .systemMetrics: "waveform.path.ecg"
        case .logging: "doc.plaintext.fill"
        }
    }

    /// True when this destination should only appear when telemetry is enabled.
    var isMetricsDestination: Bool {
        self == .appMetrics || self == .queryMetrics || self == .systemMetrics
    }
}
