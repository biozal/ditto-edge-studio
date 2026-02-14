import SwiftUI

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
                     PresenceViewerSK()
                        .padding(.bottom, 28)  // Add padding for status bar
                case 2:
                    TransportConfigView()
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
                        print("Failed to register sync status observer: \(error)")
                    }
                }
            }
        }
        .onChange(of: selectedSyncTab) { oldValue, newValue in
            Task {
                // Stop observer when leaving Peers List tab (tab 0)
                if oldValue == 0 && newValue != 0 {
                    await SystemRepository.shared.stopObserver()
                }

                // Start observer when entering Peers List tab (tab 0)
                if newValue == 0 && oldValue != 0 {
                    do {
                        try await SystemRepository.shared.registerSyncStatusObserver()
                    } catch {
                        print("Failed to register sync status observer: \(error)")
                    }
                }
            }
        }
        // Note: Toolbar buttons are already added at NavigationSplitView level (line 198)
        // on macOS, so no need to add them here
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

    // Observe helper views

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
