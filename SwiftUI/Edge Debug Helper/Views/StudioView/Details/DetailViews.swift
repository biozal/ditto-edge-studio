import SwiftUI

extension MainStudioView {
    func syncTabsDetailView() -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                // ── Wide layout: all on one row ──────────────────────────────────
                HStack {
                    VStack(alignment: .leading) {
                        Text("Connected Peers")
                            .font(.title2)
                            .bold()
                        if let statusInfo = viewModel.syncStatusItems.first {
                            Text("Last updated: \(statusInfo.formattedLastUpdate)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 10)

                    Spacer()

                    Picker("", selection: $selectedSyncTab) {
                        Text("Peers List").tag(0)
                        Text("Presence Viewer").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("SyncTabPicker")

                    Spacer()

                    TransportSettingsButton()
                        .padding(.trailing, 5)
                }

                // ── Narrow layout: picker + gear on top, title below ─────────────
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Picker("", selection: $selectedSyncTab) {
                            Text("Peers List").tag(0)
                            Text("Presence Viewer").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.leading, 10)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("SyncTabPicker")

                        TransportSettingsButton()
                            .padding(.trailing, 5)
                    }

                    VStack(alignment: .leading) {
                        Text("Connected Peers")
                            .font(.title2)
                            .bold()
                        if let statusInfo = viewModel.syncStatusItems.first {
                            Text("Last updated: \(statusInfo.formattedLastUpdate)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.bottom, 8)
                }
            }

            // Tab content
            Group {
                switch selectedSyncTab {
                case 0:
                    ConnectedPeersView(viewModel: viewModel)
                case 1:
                    PresenceViewerSK()
                default:
                    ConnectedPeersView(viewModel: viewModel)
                }
            }

            DetailBottomBar(connections: viewModel.connectionsByTransport)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
            appNameToolbarLabel()
            syncToolbarButton()
            closeToolbarButton()
            inspectorToggleButton()
        }
        #endif
    }

    // MARK: - Pagination helpers (used by queryDetailView)

    private var queryResultsCount: Int {
        viewModel.jsonResults.count
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
        viewModel.observableEvents.count
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
        return Array(viewModel.observableEvents[start ..< end])
    }

    func queryDetailView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content split — GeometryReader fills all remaining space
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    QueryEditorView(
                        queryText: $viewModel.selectedQuery,
                        executeModes: $viewModel.executeModes,
                        selectedExecuteMode: $viewModel.selectedExecuteMode,
                        isLoading: $viewModel.isQueryExecuting,
                        onExecuteQuery: executeQuery
                    )
                    .frame(height: geometry.size.height * 0.5)

                    Divider()

                    QueryResultsView(
                        jsonResults: $viewModel.jsonResults,
                        currentPage: $queryCurrentPage,
                        pageSize: $queryPageSize,
                        onJsonSelected: { json in
                            viewModel.showJsonInInspector(json)
                            showInspector = true
                        }
                    )
                    .frame(height: geometry.size.height * 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif

            DetailBottomBar(connections: viewModel.connectionsByTransport) {
                if !viewModel.jsonResults.isEmpty {
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
                        }
                    )
                    queryGenerateDQLButton
                    Button { queryIsExporting = true } label: {
                        FontAwesomeText(icon: ActionIcon.download, size: 14)
                    }
                    .help("Export query results to JSON file")
                }
            }
        }
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
                    .foregroundColor(.primary)
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
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
                inspectorToggleButton()
            }
        #endif
    }

    // MARK: - Query footer helpers

    private var queryGenerateDQLButton: some View {
        Menu {
            Button("SELECT with all fields") { queryGenerateAndInsert(.select) }
            Button("INSERT template") { queryGenerateAndInsert(.insert) }
            Button("UPDATE template") { queryGenerateAndInsert(.update) }
            Button("DELETE template") { queryGenerateAndInsert(.delete) }
            Button("EVICT template") { queryGenerateAndInsert(.evict) }
        } label: {
            FontAwesomeText(icon: DataIcon.code, size: 14)
        }
        .disabled(viewModel.jsonResults.isEmpty)
        .help("Generate DQL statement templates based on query results")
        .padding(.trailing, 8)
    }

    private enum QueryDQLStatementType {
        case select, insert, update, delete, evict
    }

    private func queryGenerateAndInsert(_ type: QueryDQLStatementType) {
        let lastQuery = viewModel.selectedQuery
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
        viewModel.selectedQuery = dql
        queryShowNotification("DQL inserted into editor")
    }

    private func queryExtractFieldNames() -> [String] {
        guard let first = viewModel.jsonResults.first,
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
        let results = viewModel.jsonResults
        guard results.count > 1 else { return results.first ?? "[]" }
        return "[\n" + results.joined(separator: ",\n") + "\n]"
    }

    private func queryShowNotification(_ message: String) {
        queryCopiedDQLNotification = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                        .frame(height: geometry.size.height * 0.5)

                    Divider()

                    // Bottom pane (50%) — selected event detail
                    observableDetailSelectedEvent(observeEvent: viewModel.selectedEventObject)
                        .frame(height: geometry.size.height * 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif

            DetailBottomBar(connections: viewModel.connectionsByTransport) {
                if !viewModel.observableEvents.isEmpty {
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
                }
            }
        }
        .onChange(of: viewModel.observableEvents.count) { _, _ in
            observerCurrentPage = 1
            if !observerPageSizes.contains(observerPageSize) {
                observerPageSize = observerPageSizes.first ?? 25
            }
        }
        #if os(iOS)
        .toolbar {
            appNameToolbarLabel()
            syncToolbarButton()
            closeToolbarButton()
            inspectorToggleButton()
        }
        #endif
    }

    // Observe helper views

    private func observableEventsList() -> some View {
        VStack {
            if viewModel.selectedObservable == nil {
                ContentUnavailableView(
                    "No Observer Selected",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Select an observer from the sidebar to view events.")
                )
            } else if viewModel.observableEvents.isEmpty {
                ContentUnavailableView(
                    "No Observer Events",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Activate an observer to see observable events.")
                )
            } else {
                Table(
                    pagedObservableEvents,
                    selection: Binding<Set<String>>(
                        get: {
                            if let selectedId = viewModel.selectedEventId {
                                return Set([selectedId])
                            } else {
                                return Set<String>()
                            }
                        },
                        set: { newValue in
                            if let first = newValue.first {
                                viewModel.selectedEventId = first
                            } else {
                                viewModel.selectedEventId = nil
                            }
                        }
                    )
                ) {
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

    private func observableDetailSelectedEvent(observeEvent: DittoObserveEvent?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
