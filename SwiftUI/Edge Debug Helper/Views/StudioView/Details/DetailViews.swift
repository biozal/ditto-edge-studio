import SwiftUI

extension MainStudioView {
    func syncTabsDetailView() -> some View {
        VStack(spacing: 0) {
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

                // Tab selector (segmented picker with icons)
                Picker("", selection: $selectedSyncTab) {
                    Text("Peers List")
                        .tag(0)

                    Text("Presence Viewer")
                        .tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .accessibilityIdentifier("SyncTabPicker")

                Spacer()

                // Right: Transport settings popover button
                TransportSettingsButton()
                    .padding(.trailing, 5)
            }

            // Tab content
            Group {
                switch selectedSyncTab {
                case 0:
                    ConnectedPeersView(viewModel: viewModel)
                case 1:
                    PresenceViewerSK()
                        .padding(.bottom, 28) // Add padding for status bar
                default:
                    ConnectedPeersView(viewModel: viewModel)
                }
            }
        }
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
        // Note: Toolbar buttons are already added at NavigationSplitView level (line 198)
        // on macOS, so no need to add them here
    }

    func queryDetailView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 50/50 split using GeometryReader for exact percentage heights (works on all platforms)
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
                            showInspector = true // Auto-open inspector
                        }
                    )
                    .frame(height: geometry.size.height * 0.5)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 28) // Add padding for status bar height
        #if os(iOS)
            .toolbar {
                appNameToolbarLabel()
                syncToolbarButton()
                closeToolbarButton()
            }
        #endif
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 28) // Add padding for status bar height
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
                    viewModel.observableEvents,
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
