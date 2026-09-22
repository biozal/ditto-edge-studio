import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Aligns the peer search field with the segmented picker even when the picker
/// lives above the title in the compact Presence header.
private extension VerticalAlignment {
    enum PresenceHeaderControls: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let presenceHeaderControls = VerticalAlignment(PresenceHeaderControls.self)
}

extension MainStudioView {
    func syncTabsDetailView() -> some View {
        VStack(spacing: 0) {
            // The compact alternative puts the title below the picker. A custom
            // guide keeps the adjacent search field aligned to the picker—not to
            // the taller picker-and-title stack—without relying on fixed offsets.
            HStack(alignment: .presenceHeaderControls, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    // ── Wide layout: title on left, picker centered ───────────────
                    // NOTE: No dynamic data inside ViewThatFits — avoids onChange(of: Layout)
                    // feedback loop caused by measuring both alternatives while syncStatusItems
                    // updates rapidly. The "Last updated" subtitle lives below this HStack.
                    HStack {
                        Text("Presence")
                            .font(.title2)
                            .bold()
                            .padding(.leading, 10)

                        Spacer()

                        DittoSegmentedPicker(
                            options: [0, 1],
                            selection: $selectedSyncTab
                        ) { $0 == 0 ? "Peers" : "Viewer" }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .alignmentGuide(.presenceHeaderControls) { dimensions in
                                dimensions[VerticalAlignment.center]
                            }
                            .accessibilityIdentifier("SyncTabPicker")

                        Spacer()
                    }

                    // ── Narrow layout: picker on top, title below ─────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        DittoSegmentedPicker(
                            options: [0, 1],
                            selection: $selectedSyncTab
                        ) { $0 == 0 ? "Peers" : "Viewer" }
                            .padding(.leading, 10)
                            .padding(.vertical, 8)
                            .alignmentGuide(.presenceHeaderControls) { dimensions in
                                dimensions[VerticalAlignment.center]
                            }
                            .accessibilityIdentifier("SyncTabPicker")

                        Text("Presence")
                            .font(.title2)
                            .bold()
                            .padding(.leading, 10)
                            .padding(.bottom, 8)
                    }
                }

                // Peer search rides in the tab bar so the canvas keeps its full
                // height (extension parity). Deliberately OUTSIDE the ViewThatFits
                // above: the box is dynamic, and ViewThatFits measures every
                // alternative on each change — the documented feedback loop the
                // note at the top of this method exists to prevent.
                //
                // The child view owns every read of the query. Reading it here
                // would make it a dependency of MainStudioView.body.
                if selectedSyncTab == 1 {
                    PresencePeerSearchField(viewModel: presenceViewerVM)
                        .padding(.trailing, 8)
                        .alignmentGuide(.presenceHeaderControls) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                }

                #if os(macOS)
                // macOS keeps this contextual action in the Presence header. On iOS
                // it is a native detail-toolbar item so iPhone Duo can place it in
                // the shared vertical action rail.
                TransportSettingsButton()
                    .padding(.trailing, 5)
                #endif
            }
            // The search results card is an overlay on the box above; without
            // this the tab content below paints over it.
            .zIndex(1)

            // Read inside a child view, never here. `syncTabsDetailView()` is a
            // *method* on MainStudioView, so anything it touches becomes a
            // dependency of MainStudioView.body — i.e. the whole
            // NavigationSplitView, sidebar and ViewThatFits included. Reading
            // the presence feed here re-ran all of that on every tick.
            SyncLastUpdatedLabel(viewModel: viewModel)

            // Tab content
            Group {
                switch selectedSyncTab {
                case 0:
                    ConnectedPeersView(viewModel: viewModel)
                case 1:
                    PresenceViewerSK(viewModel: presenceViewerVM)
                default:
                    ConnectedPeersView(viewModel: viewModel)
                }
            }
        }
        #if os(macOS)
        // macOS keeps the floating glass bar. On iOS the same actions are native
        // toolbar content, so iPhone Duo can arrange them on its trailing rail.
        .overlay(alignment: .bottom) {
            // The Viewer tab injects its own Direct/reset/zoom controls into the
            // toolbar's middle slot so the canvas stays unobstructed. The Peers tab
            // doesn't need any extra controls — the @ViewBuilder closure returns an
            // empty conditional branch in that case (the bar's middle slot collapses).
            // Same reasoning: the connections read is confined to a leaf.
            SyncBottomBar(viewModel: viewModel) {
                if selectedSyncTab == 1 {
                    PresenceViewerToolbarControls(viewModel: presenceViewerVM)
                }
            }
            .padding(.bottom, 12)
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
        #endif
        .onAppear {
            // Only start observer if Peers List tab (tab 0) is selected
            if selectedSyncTab == 0 {
                Task {
                    do {
                        try await SystemRepository.shared.registerSyncStatusObserver()
                    } catch {
                        Log.error("Failed to register sync status observer: \(error.localizedDescription)")
                    }
                }
            }
        }
        .onChange(of: selectedSyncTab) { oldValue, newValue in
            Task {
                // Stop only the sync-status observer when leaving Peers List tab (tab 0).
                // The connections-presence observer stays alive to keep the status bar updating.
                if oldValue == 0 && newValue != 0 {
                    await SystemRepository.shared.stopSyncStatusObserver()
                }

                // Start observer when entering Peers List tab (tab 0)
                if newValue == 0 && oldValue != 0 {
                    do {
                        try await SystemRepository.shared.registerSyncStatusObserver()
                    } catch {
                        Log.error("Failed to register sync status observer: \(error.localizedDescription)")
                    }
                }
            }
        }
        #if os(iOS)
        .toolbar {
            // Same native items in every size class. Separate ToolbarItems
            // (not a custom HStack cluster) are required for iPhone Duo:
            // custom-view items are dropped when the system presents bars
            // vertically on the trailing edge.
            if showsLeadingSidebarToggle {
                sidebarToggleButton()
            }
            if horizontalSizeClass == .regular {
                appNameToolbarLabel()
            }
            transportSettingsToolbarButton()

            // Independent native items let iPhone Duo stack these controls in its
            // vertical bar (or put low-priority items in overflow). A custom
            // HStack plus Spacer keeps the whole strip horizontal and collides
            // with the connection counter on the outer display.
            SyncConnectionsToolbarItem(viewModel: viewModel)
            if selectedSyncTab == 1 {
                PresenceViewerToolbarItems(viewModel: presenceViewerVM)
            }

            // Persistent workspace actions always trail the contextual Presence
            // actions, so their order is Sync, Close, then Inspector.
            workspaceToolbarActions()
        }
        #endif
    }

    // MARK: - Pagination helpers (used by queryDetailView)

    private var queryResultsCount: Int {
        viewModel.queryVM.jsonResults.count
    }

    private var queryPageSizes: [Int] {
        switch queryResultsCount {
        case 0 ... 10: return [10]
        case 11 ... 25: return [10, 25]
        case 26 ... 50: return [10, 25, 50]
        case 51 ... 100: return [10, 25, 50, 100]
        case 101 ... 200: return [10, 25, 50, 100, 200]
        case 201 ... 250: return [10, 25, 50, 100, 200, 250]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }

    private var queryPageCount: Int {
        max(1, Int(ceil(Double(queryResultsCount) / Double(queryPageSize))))
    }

    // MARK: - Pagination helpers (used by observeDetailView)

    private var observerEventsCount: Int {
        viewModel.subObsVM.eventStore.count
    }

    private var observerPageSizes: [Int] {
        switch observerEventsCount {
        case 0 ... 10: return [10]
        case 11 ... 25: return [10, 25]
        case 26 ... 50: return [10, 25, 50]
        case 51 ... 100: return [10, 25, 50, 100]
        case 101 ... 200: return [10, 25, 50, 100, 200]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }

    private var observerPageCount: Int {
        max(1, Int(ceil(Double(observerEventsCount) / Double(observerPageSize))))
    }

    private var pagedObservableEvents: [DittoObserveEvent] {
        let start = (observerCurrentPage - 1) * observerPageSize
        guard start < observerEventsCount else { return [] }
        let end = min(start + observerPageSize, observerEventsCount)
        return Array(viewModel.subObsVM.eventStore.events[start ..< end])
    }

    // MARK: - Pagination helpers (used by observe detail pane)

    private var observeDetailPageSizes: [Int] {
        let count = observeDetailFilteredData.count
        switch count {
        case 0 ... 10: return [10]
        case 11 ... 25: return [10, 25]
        case 26 ... 50: return [10, 25, 50]
        case 51 ... 100: return [10, 25, 50, 100]
        case 101 ... 200: return [10, 25, 50, 100, 200]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }

    private var observeDetailPageCount: Int {
        max(1, Int(ceil(Double(observeDetailFilteredData.count) / Double(observeDetailPageSize))))
    }

    func queryDetailView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content split — GeometryReader fills all remaining space
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    QueryEditorView(queryText: $viewModel.queryVM.selectedQuery)
                        .frame(height: geometry.size.height * 0.5)

                    // ADVISE (SDK 5.1) index-advice card — sits between editor and
                    // results so it doesn't displace the results pane's layout.
                    if let advice = viewModel.queryVM.queryAdvice {
                        QueryAdviceCardView(
                            advice: advice,
                            onApply: { suggestion in
                                do {
                                    try await viewModel.queryVM.applyAdviceSuggestion(suggestion, appState: appState)
                                    return true
                                } catch {
                                    return false
                                }
                            },
                            onDismiss: { viewModel.queryVM.queryAdvice = nil }
                        )
                        .transition(.opacity)
                    }

                    Divider()

                    QueryResultsView(
                        jsonResults: $viewModel.queryVM.jsonResults,
                        currentPage: $queryCurrentPage,
                        pageSize: $queryPageSize,
                        // Forward the captured profile + last query
                        // text so the Profile tab can render either
                        // the populated card view or the right
                        // empty state (metrics off / non-SELECT /
                        // no query yet). See `QueryProfile` and the
                        // viewer at `Components/ProfileViewer/`.
                        profile: viewModel.queryVM.latestProfile,
                        lastQueryText: viewModel.queryVM.selectedQuery,
                        onJsonSelected: { json in
                            viewModel.showJsonInInspector(json)
                            showInspector = true
                        },
                        onAddAttachment: { json in
                            presentAddAttachment(documentJson: json)
                        },
                        onDeleteAttachment: { json in
                            presentDeleteAttachment(documentJson: json)
                        }
                    )
                    .frame(height: geometry.size.height * 0.5)
                    .overlay(alignment: .bottom) {
                        AttachmentProgressOverlay(
                            isActive: viewModel.attachmentVM.attachmentProgress.isActive,
                            message: viewModel.attachmentVM.attachmentProgress.message,
                            fractionCompleted: viewModel.attachmentVM.attachmentProgress.fractionCompleted
                        )
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
            #endif
        }
        #if os(macOS)
        // macOS-only floating glass bar; iOS uses the native bottom toolbar
        // declared in the .toolbar block below.
        .overlay(alignment: .bottom) {
            DetailBottomBar(connections: viewModel.syncVM.connectionsByTransport) {
                if !viewModel.queryVM.jsonResults.isEmpty {
                    PaginationControls(
                        totalCount: queryResultsCount,
                        currentPage: $queryCurrentPage,
                        pageCount: queryPageCount,
                        pageSize: $queryPageSize,
                        pageSizes: queryPageSizes,
                        onPageChange: { newPage in
                            queryCurrentPage = max(1, min(newPage, queryPageCount))
                        },
                        onPageSizeChange: { newSize in
                            queryPageSize = newSize
                            queryCurrentPage = 1
                        },
                        onExport: { queryIsExporting = true }
                    )
                }
            }
            .padding(.bottom, 12)
        }
        #endif
        .fileExporter(
            isPresented: $queryIsExporting,
            document: QueryResultsDocument(jsonData: queryFlattenResults()),
            contentType: .json,
            defaultFilename: "query_results"
        ) { _ in }
        .overlay(alignment: .top) {
            if let message = queryCopiedDQLNotification {
                Text(message)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .subtleShadow()
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: queryCopiedDQLNotification)
        #if os(iOS)
            .toolbar {
                if horizontalSizeClass == .compact {
                    // COMPACT: sidebar + query controls leading, standard
                    // actions trailing as separate native items. Custom-view
                    // clusters are dropped from iPhone Duo's vertical side
                    // bar, so sync/close/inspector must be real ToolbarItems.
                    sidebarToggleButton()
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 8) {
                            // Execute mode picker
                            Picker("", selection: $viewModel.queryVM.selectedExecuteMode) {
                                ForEach(viewModel.queryVM.executeModes, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 85)

                            // Execute play button
                            Button { Task { await executeQuery() } } label: {
                                Label("Execute Query", systemImage: "play")
                                    .foregroundStyle(viewModel.queryVM.isQueryExecuting ? .gray : .green)
                            }
                            .disabled(viewModel.queryVM.isQueryExecuting)
                            .accessibilityIdentifier("ExecuteQueryButton")
                        }
                    }
                    workspaceToolbarActions()
                } else {
                    // REGULAR (iPad, iPhone Duo inner display)
                    if showsLeadingSidebarToggle {
                        // Regular-width split views already show the sidebar.
                        // This remains available only if the environment later
                        // reports collapsed navigation.
                        sidebarToggleButton()
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 2) {
                            Picker("", selection: $viewModel.queryVM.selectedExecuteMode) {
                                ForEach(viewModel.queryVM.executeModes, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 90)

                            Divider().frame(height: 18)

                            Button { Task { await executeQuery() } } label: {
                                FontAwesomeText(
                                    icon: NavigationIcon.play,
                                    size: 14,
                                    color: viewModel.queryVM.isQueryExecuting ? .gray : .green
                                )
                                .accessibilityLabel("Execute Query")
                                .padding(.horizontal, 4)
                            }
                            .disabled(viewModel.queryVM.isQueryExecuting)
                            .accessibilityIdentifier("ExecuteQueryButton")
                        }
                    }
                    appNameToolbarLabel()
                    workspaceToolbarActions()
                }

                // BOTTOM BAR — all of iOS (was compact-only). A native bottom
                // toolbar lets the system present it vertically on iPhone Duo;
                // the previous floating overlay could not move.
                ToolbarItemGroup(placement: .bottomBar) {
                    SyncConnectionsMenu(
                        viewModel: viewModel,
                        pageSize: $queryPageSize,
                        pageSizes: queryPageSizes,
                        onPageSizeChange: { newSize in
                            queryPageSize = newSize
                            queryCurrentPage = 1
                        }
                    )

                    Spacer()

                    if !viewModel.queryVM.jsonResults.isEmpty {
                        Button {
                            queryCurrentPage = max(1, queryCurrentPage - 1)
                        } label: {
                            Label("Previous Page", systemImage: "chevron.left")
                        }
                        .disabled(queryCurrentPage <= 1)

                        if queryPageCount > 1 {
                            Menu {
                                ForEach(1 ... queryPageCount, id: \.self) { page in
                                    Button("Page \(page)") { queryCurrentPage = page }
                                }
                            } label: {
                                Text("Pg \(queryCurrentPage)")
                                    .font(.caption.monospacedDigit())
                            }
                        } else {
                            Text("Pg 1")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            queryCurrentPage = min(queryPageCount, queryCurrentPage + 1)
                        } label: {
                            Label("Next Page", systemImage: "chevron.right")
                        }
                        .disabled(queryCurrentPage >= queryPageCount)

                        Spacer()

                        Menu {
                            // ADVISE (SDK 5.1) — index suggestions for the editor query.
                            Button {
                                Task { await viewModel.queryVM.runAdvise(appState: appState) }
                            } label: {
                                Label("Advise (index suggestions)…", systemImage: "lightbulb")
                            }
                            .disabled(!viewModel.queryVM.canRunAdvise)
                            .accessibilityIdentifier("QueryAdviseMenuItem")
                            Divider()
                            Button("Export JSON") { queryIsExporting = true }
                            Divider()
                            Button("Generate SELECT") { queryGenerateAndInsert(.select) }
                            Button("Generate INSERT") { queryGenerateAndInsert(.insert) }
                            Button("Generate UPDATE") { queryGenerateAndInsert(.update) }
                            Button("Generate DELETE") { queryGenerateAndInsert(.delete) }
                            Button("Generate EVICT") { queryGenerateAndInsert(.evict) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $viewModel.queryVM.selectedExecuteMode) {
                    ForEach(viewModel.queryVM.executeModes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            ToolbarItem(placement: .navigation) {
                Button { Task { await executeQuery() } } label: {
                    FontAwesomeText(
                        icon: NavigationIcon.play,
                        size: 14,
                        color: viewModel.queryVM.isQueryExecuting ? .gray : .green
                    )
                    .accessibilityLabel("Execute Query")
                }
                .disabled(viewModel.queryVM.isQueryExecuting)
                .accessibilityIdentifier("ExecuteQueryButton")
            }
            ToolbarItem(placement: .primaryAction) {
                queryGenerateDQLButton
            }
        }
        #endif
    }

    // MARK: - Query footer helpers

    private var queryGenerateDQLButton: some View {
        Menu {
            // ADVISE (SDK 5.1) — index suggestions for the editor query.
            Button {
                Task { await viewModel.queryVM.runAdvise(appState: appState) }
            } label: {
                Label("Advise (index suggestions)…", systemImage: "lightbulb")
            }
            .disabled(!viewModel.queryVM.canRunAdvise)
            .accessibilityIdentifier("QueryAdviseMenuItem")
            Divider()
            Button("SELECT with all fields") { queryGenerateAndInsert(.select) }
            Button("INSERT template") { queryGenerateAndInsert(.insert) }
            Button("UPDATE template") { queryGenerateAndInsert(.update) }
            Button("DELETE template") { queryGenerateAndInsert(.delete) }
            Button("EVICT template") { queryGenerateAndInsert(.evict) }
        } label: {
            FontAwesomeText(icon: DataIcon.code, size: 14)
        }
        .disabled(viewModel.queryVM.jsonResults.isEmpty)
        .help("Generate DQL statement templates based on query results")
        .padding(.trailing, 8)
    }

    private enum QueryDQLStatementType {
        case select, insert, update, delete, evict
    }

    private func queryGenerateAndInsert(_ type: QueryDQLStatementType) {
        let lastQuery = viewModel.queryVM.selectedQuery
        guard !lastQuery.isEmpty else {
            queryShowNotification("No query available")
            return
        }
        let queryInfo = QueryInfo(query: lastQuery)
        guard let collectionName = queryInfo.collectionName else {
            queryShowNotification("Could not extract collection name from query")
            return
        }
        let fieldNames = queryExtractFieldNames()
        let dql: String = switch type {
        case .select: DQLGenerator.generateSelect(collection: collectionName, fields: fieldNames)
        case .insert: DQLGenerator.generateInsert(collection: collectionName, fields: fieldNames)
        case .update: DQLGenerator.generateUpdate(collection: collectionName, fields: fieldNames)
        case .delete: DQLGenerator.generateDelete(collection: collectionName)
        case .evict: DQLGenerator.generateEvict(collection: collectionName)
        }
        viewModel.queryVM.selectedQuery = dql
        queryShowNotification("DQL inserted into editor")
    }

    private func queryExtractFieldNames() -> [String] {
        guard let first = viewModel.queryVM.jsonResults.first,
              let data = first.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var keys = Array(obj.keys).sorted()
        if let idx = keys.firstIndex(of: "_id") {
            keys.remove(at: idx)
            keys.insert("_id", at: 0)
        }
        return keys
    }

    private func queryFlattenResults() -> String {
        let results = viewModel.queryVM.jsonResults
        guard results.count > 1 else { return results.first ?? "[]" }
        return "[\n" + results.joined(separator: ",\n") + "\n]"
    }

    private func queryShowNotification(_ message: String) {
        queryCopiedDQLNotification = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { queryCopiedDQLNotification = nil }
        }
    }

    func observeDetailView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 50/50 split using GeometryReader — same pattern as queryDetailView (no VSplitView)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Top pane (50%) — events list, or "no observer" / "no events" states inline
                    observableEventsList()
                        .frame(maxWidth: .infinity)
                        .frame(height: geometry.size.height * 0.5, alignment: .top)

                    Divider()

                    // Bottom pane (50%) — selected event detail
                    observableDetailSelectedEvent(observeEvent: viewModel.subObsVM.selectedEventObject)
                        .frame(height: geometry.size.height * 0.5, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
            #endif
        }
        #if os(macOS)
        // macOS-only floating glass bar; iOS uses the native bottom toolbar
        // declared in the .toolbar block below.
        .overlay(alignment: .bottom) {
            DetailBottomBar(connections: viewModel.syncVM.connectionsByTransport) {
                if viewModel.subObsVM.selectedEventObject != nil && !observeDetailFilteredData.isEmpty {
                    PaginationControls(
                        totalCount: observeDetailFilteredData.count,
                        currentPage: $observeDetailCurrentPage,
                        pageCount: observeDetailPageCount,
                        pageSize: $observeDetailPageSize,
                        pageSizes: observeDetailPageSizes,
                        onPageChange: { newPage in
                            observeDetailCurrentPage = max(1, min(newPage, observeDetailPageCount))
                        },
                        onPageSizeChange: { newSize in
                            observeDetailPageSize = newSize
                            observeDetailCurrentPage = 1
                        }
                    )
                }
            }
            .padding(.bottom, 12)
        }
        #endif
        .onChange(of: viewModel.subObsVM.eventStore.count) { _, _ in
            observerCurrentPage = 1
            if !observerPageSizes.contains(observerPageSize) {
                observerPageSize = observerPageSizes.first ?? 25
            }
        }
        .onChange(of: viewModel.subObsVM.selectedEventId) { _, _ in refreshObserveDetailData() }
        .onChange(of: viewModel.subObsVM.eventMode) { _, _ in refreshObserveDetailData() }
        #if os(iOS)
            .navigationTitle("Observer Events")
            .toolbar {
                // Same native items in every size class so the system can
                // present them vertically on iPhone Duo (custom-view clusters
                // are dropped from vertical bars).
                if showsLeadingSidebarToggle {
                    sidebarToggleButton()
                }
                if horizontalSizeClass == .regular {
                    appNameToolbarLabel()
                }
                workspaceToolbarActions()

                // Native bottom toolbar for all of iOS (was compact-only).
                ToolbarItemGroup(placement: .bottomBar) {
                    SyncConnectionsMenu(
                        viewModel: viewModel,
                        pageSize: $observeDetailPageSize,
                        pageSizes: observeDetailPageSizes,
                        onPageSizeChange: { newSize in
                            observeDetailPageSize = newSize
                            observeDetailCurrentPage = 1
                        }
                    )

                    Spacer()

                    if viewModel.subObsVM.selectedEventObject != nil && !observeDetailFilteredData.isEmpty {
                        Button {
                            observeDetailCurrentPage = max(1, observeDetailCurrentPage - 1)
                        } label: {
                            Label("Previous Page", systemImage: "chevron.left")
                        }
                        .disabled(observeDetailCurrentPage <= 1)

                        if observeDetailPageCount > 1 {
                            Menu {
                                ForEach(1 ... observeDetailPageCount, id: \.self) { page in
                                    Button("Page \(page)") { observeDetailCurrentPage = page }
                                }
                            } label: {
                                Text("Pg \(observeDetailCurrentPage)")
                                    .font(.caption.monospacedDigit())
                            }
                        } else {
                            Text("Pg 1")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            observeDetailCurrentPage = min(observeDetailPageCount, observeDetailCurrentPage + 1)
                        } label: {
                            Label("Next Page", systemImage: "chevron.right")
                        }
                        .disabled(observeDetailCurrentPage >= observeDetailPageCount)
                    }
                }
            }
        #endif
    }

    // Observe helper views

    private func observableEventsList() -> some View {
        VStack(spacing: 0) {
            if !viewModel.subObsVM.eventStore.isEmpty {
                HStack {
                    Spacer()
                    PaginationControls(
                        totalCount: observerEventsCount,
                        currentPage: $observerCurrentPage,
                        pageCount: observerPageCount,
                        pageSize: $observerPageSize,
                        pageSizes: observerPageSizes,
                        onPageChange: { newPage in
                            observerCurrentPage = max(1, min(newPage, observerPageCount))
                        },
                        onPageSizeChange: { newSize in
                            observerPageSize = newSize
                            observerCurrentPage = 1
                        }
                    )
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                Divider()
            }

            if viewModel.subObsVM.selectedObservable == nil {
                ContentUnavailableView(
                    "No Observer Selected",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Select an observer from the sidebar to view events.")
                )
            } else if viewModel.subObsVM.eventStore.isEmpty {
                ContentUnavailableView(
                    "No Observer Events",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Activate an observer to see observable events.")
                )
            } else {
                ObserverEventsTableView(
                    events: pagedObservableEvents,
                    selectedEventId: $viewModel.subObsVM.selectedEventId
                )
            }
        }
    }

    private func filteredObserveEventData(_ event: DittoObserveEvent) -> [String] {
        switch viewModel.subObsVM.eventMode {
        case "inserted": return event.getInsertedData()
        case "updated": return event.getUpdatedData()
        default: return event.data
        }
    }

    private func refreshObserveDetailData() {
        guard let event = viewModel.subObsVM.selectedEventObject else {
            observeDetailFilteredData = []
            return
        }
        observeDetailFilteredData = filteredObserveEventData(event)
        observeDetailCurrentPage = 1
    }

    private func observableDetailSelectedEvent(observeEvent: DittoObserveEvent?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if observeEvent != nil {
                HStack(spacing: 8) {
                    // Allow-list rather than a filter: observe events are not
                    // queries, so .profile does not apply here. The switch below
                    // keeps it exhaustive but unreachable.
                    DittoSegmentedPicker(
                        options: [ResultViewTab.raw, .table],
                        selection: $observeDetailViewMode,
                        label: { Label($0.rawValue, systemImage: $0.icon).font(.caption.weight(.medium)) }
                    )
                    .frame(width: 160)

                    Spacer()

                    Picker("Filter", selection: $viewModel.subObsVM.eventMode) {
                        Text("Items").tag("items")
                        Text("Inserted").tag("inserted")
                        Text("Updated").tag("updated")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                switch observeDetailViewMode {
                case .raw:
                    ResultJsonViewer(
                        resultText: $observeDetailFilteredData,
                        externalCurrentPage: $observeDetailCurrentPage,
                        externalPageSize: $observeDetailPageSize,
                        showPaginationControls: false,
                        showExportButton: false,
                        onJsonSelected: { json in
                            viewModel.showJsonInObserveInspector(json)
                            showInspector = true
                        }
                    )
                case .table:
                    ResultTableViewer(
                        resultText: $observeDetailFilteredData,
                        currentPage: $observeDetailCurrentPage,
                        pageSize: $observeDetailPageSize,
                        onJsonSelected: { json in
                            viewModel.showJsonInObserveInspector(json)
                            showInspector = true
                        }
                    )
                case .profile:
                    // Unreachable — the picker above lists only .raw/.table.
                    // Present here only so the switch is exhaustive.
                    EmptyView()
                }
            } else {
                ContentUnavailableView(
                    "No Event Selected",
                    systemImage: "eye.slash",
                    description: Text("Select an event from the list above to view its details.")
                )
            }
        }
        .padding(.leading, 12)
    }
}

// MARK: - Presence-feed leaves

/// The "Last updated" subtitle.
///
/// A separate `View` purely so the presence-feed read happens in *this* body
/// rather than in `MainStudioView.body`. Observation records dependencies
/// against whichever body performs the read, so confining it here confines the
/// invalidation to a single line of text.
private struct SyncLastUpdatedLabel: View {
    @Bindable var viewModel: MainStudioView.ViewModel

    var body: some View {
        if let statusInfo = viewModel.syncVM.syncStatusItems.first {
            Text("Last updated: \(statusInfo.formattedLastUpdate)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.bottom, 4)
        }
    }
}

/// Wraps `DetailBottomBar` so the `connectionsByTransport` read is scoped to
/// the bar instead of the enclosing split view. See `SyncLastUpdatedLabel`.
/// macOS-only: iOS detail views declare native trailing toolbar items instead.
private struct SyncBottomBar<Middle: View>: View {
    @Bindable var viewModel: MainStudioView.ViewModel
    @ViewBuilder var middle: Middle

    var body: some View {
        DetailBottomBar(
            connections: viewModel.syncVM.connectionsByTransport
        ) { middle }
    }
}

#if os(iOS)
/// Native toolbar wrapper for the connection counter. It intentionally owns the
/// `connectionsByTransport` read so frequent presence updates don't invalidate
/// the enclosing detail view.
private struct SyncConnectionsToolbarItem: ToolbarContent {
    @Bindable var viewModel: MainStudioView.ViewModel

    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItem(id: "connectionStatus", placement: .primaryAction) {
                SyncConnectionsMenu(viewModel: viewModel)
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(id: "connectionStatus", placement: .primaryAction) {
                SyncConnectionsMenu(viewModel: viewModel)
            }
        }
    }
}

/// Leaf wrapper around `ConnectionStatusMenu` so the `connectionsByTransport`
/// read happens in this body rather than in the enclosing detail view (same
/// invalidation-confinement reasoning as `SyncLastUpdatedLabel`). Used by the
/// native iOS trailing toolbars.
private struct SyncConnectionsMenu: View {
    @Bindable var viewModel: MainStudioView.ViewModel
    var pageSize: Binding<Int>?
    var pageSizes: [Int] = []
    var onPageSizeChange: ((Int) -> Void)?

    var body: some View {
        ConnectionStatusMenu(
            connections: viewModel.syncVM.connectionsByTransport,
            pageSize: pageSize,
            pageSizes: pageSizes,
            onPageSizeChange: onPageSizeChange ?? { _ in }
        )
    }
}
#endif
