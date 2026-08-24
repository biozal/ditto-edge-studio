import SwiftUI

extension MainStudioView {
    func inspectorView() -> some View {
        Group {
            switch viewModel.selectedSidebarDestination {
            case .subscriptions:
                syncTabsInspectorView()
            case .query:
                queryTabInspectorView()
            case .observers:
                observeDetailInspectorView()
            case .appMetrics, .queryMetrics:
                metricsInspectorView()
            case .logging:
                loggingInspectorView()
            }
        }
        .id(viewModel.selectedSidebarDestination)
        .transition(.blurReplace)
        .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarDestination)
    }

    // MARK: - Per-Tab Inspector Dispatchers

    func syncTabsInspectorView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Subscription and Sync Help").font(.headline)
                Divider()
            }
            .padding(.horizontal)
            .padding(.top)
            HelpContentView(markdownContent: loadMarkdown(named: "subscription"))
        }
    }

    func loggingInspectorView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Logging Help").font(.headline)
                Divider()
            }
            .padding(.horizontal)
            .padding(.top)
            HelpContentView(markdownContent: loadMarkdown(named: "logging"))
        }
    }

    func queryTabInspectorView() -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $viewModel.queryVM.selectedQueryInspectorMenuItem) {
                    ForEach(viewModel.queryVM.queryInspectorMenuItems) { item in
                        item.image
                            .tag(item)
                            .font(.system(size: 20))
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(ControlSize.extraLarge)
                .labelsHidden()
                .accessibilityIdentifier("InspectorSegmentedPicker")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if viewModel.queryVM.selectedQueryInspectorMenuItem.name == "Help" {
                helpQueryInspectorContent()
            } else {
                ScrollView {
                    switch viewModel.queryVM.selectedQueryInspectorMenuItem.name {
                    case "History":
                        historyInspectorContent()
                    case "Favorites":
                        favoritesInspectorContent()
                    case "JSON":
                        jsonInspectorContent()
                    case "Metrics":
                        queryMetricsInspectorContent()
                    default:
                        historyInspectorContent()
                    }
                }
                .scrollIndicators(.hidden)
                .padding()
            }
        }
        // Container anchor so UI tests can reliably detect the inspector being
        // open. `.contain` keeps children (history/favorites rows) individually
        // queryable; the segmented picker alone doesn't reliably surface.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("QueryInspectorView")
    }

    func observeDetailInspectorView() -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $viewModel.subObsVM.selectedObserveInspectorMenuItem) {
                    ForEach(viewModel.subObsVM.observeInspectorMenuItems) { item in
                        item.image
                            .tag(item)
                            .font(.system(size: 20))
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.extraLarge)
                .labelsHidden()
                .accessibilityIdentifier("ObserveInspectorSegmentedPicker")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if viewModel.subObsVM.selectedObserveInspectorMenuItem.name == "Help" {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Observable Help").font(.headline)
                        Divider()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    HelpContentView(markdownContent: loadMarkdown(named: "observe"))
                }
            } else {
                ScrollView {
                    jsonInspectorContent()
                }
                .scrollIndicators(.hidden)
                .padding()
            }
        }
    }

    // MARK: - Metrics Inspector

    func metricsInspectorView() -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $viewModel.selectedMetricsInspectorMenuItem) {
                    ForEach(viewModel.metricsInspectorMenuItems) { item in
                        item.image
                            .tag(item)
                            .font(.system(size: 20))
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.extraLarge)
                .labelsHidden()
                .accessibilityIdentifier("MetricsInspectorSegmentedPicker")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if viewModel.selectedMetricsInspectorMenuItem.name == "Docs" {
                metricsDocsInspectorContent()
            }
        }
    }

    private func metricsDocsInspectorContent() -> some View {
        let resourceName = viewModel.selectedSidebarDestination == .appMetrics ? "appmetrics" : "querymetrics"
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Metrics Help").font(.headline)
                Divider()
            }
            .padding(.horizontal)
            .padding(.top)
            HelpContentView(markdownContent: loadMarkdown(named: resourceName))
        }
    }

    // MARK: - Help Content

    private func helpQueryInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Query Help").font(.headline)
                Divider()
            }
            .padding(.horizontal)
            .padding(.top)
            HelpContentView(markdownContent: loadMarkdown(named: "query"))
        }
    }

    private func loadMarkdown(named resourceName: String) -> String {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "# Help\n\nDocumentation not found." }
        return content
    }

    // MARK: - Inspector Content Views (Collections tab)

    private func historyInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query History")
                .font(.headline)
                .padding(.bottom, 4)

            if viewModel.queryVM.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("No queries have been run yet.")
                )
            } else {
                ForEach(viewModel.queryVM.history) { query in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            FontAwesomeText(icon: UIIcon.clock, size: 12)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2) // Align with first line of text
                            Text(query.query)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading) // Take full available width
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
                                do {
                                    try await HistoryRepository.shared.deleteQueryHistory(query.id)
                                } catch {
                                    Log.error("Failed to delete query history: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                        Button("Add to Favorites") {
                            Task {
                                do {
                                    try await FavoritesRepository.shared.saveFavorite(
                                        query,
                                        databaseId: viewModel.selectedApp.databaseId
                                    )
                                } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                                    // Correctly refused after a database switch —
                                    // don't alert in the NEW session.
                                    Log.info("Favorite save refused: \(error.message)")
                                } catch {
                                    Log.error("Failed to add favorite: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func favoritesInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorite Queries")
                .font(.headline)
                .padding(.bottom, 4)

            if viewModel.queryVM.favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("No favorite queries saved yet.")
                )
            } else {
                ForEach(viewModel.queryVM.favorites) { query in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            FontAwesomeText(icon: UIIcon.star, size: 12)
                                .foregroundStyle(.yellow)
                                .padding(.top, 2) // Align with first line of text
                            Text(query.query)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading) // Take full available width
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
                                do {
                                    try await FavoritesRepository.shared.deleteFavorite(query.id)
                                } catch {
                                    Log.error("Failed to remove favorite: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func jsonInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JSON Viewer")
                .font(.headline)
                .padding(.bottom, 4)

            if let json = viewModel.queryVM.selectedJsonForInspector {
                JsonSyntaxView(jsonString: json)
                    .id(json) // Force recreation when JSON changes

                AttachmentViewerSection(
                    attachments: viewModel.attachmentVM.detectedAttachments,
                    loadedImages: viewModel.attachmentVM.attachmentLoadedImages,
                    loadingIds: viewModel.attachmentVM.attachmentLoadingIds,
                    errorMessages: viewModel.attachmentVM.attachmentErrors,
                    onFetchAttachment: { attachment in
                        Task {
                            await viewModel.attachmentVM.fetchAttachmentForViewing(
                                attachment,
                                json: viewModel.queryVM.selectedJsonForInspector,
                                executeMode: viewModel.queryVM.selectedExecuteMode,
                                appState: appState
                            )
                        }
                    }
                )
            } else {
                // Empty state: centered message
                VStack(spacing: 12) {
                    Spacer()
                    FontAwesomeText(icon: DataIcon.code, size: 48, color: .secondary)
                    Text("Select a JSON result to view it here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func queryMetricsInspectorContent() -> some View {
        Group {
            if let record = viewModel.queryVM.lastQueryMetricsRecord {
                VStack(alignment: .leading, spacing: 16) {
                    // DQL Statement
                    VStack(alignment: .leading, spacing: 6) {
                        Label("DQL Statement", systemImage: "text.page")
                            .font(.headline)
                        Text(record.dql)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Stat badges — first row: Time, Results, Index
                    HStack(spacing: 12) {
                        metricsStatBadge(
                            label: "Time",
                            value: record.formattedExecutionTime,
                            color: metricsLatencyColor(record.executionTimeMs)
                        )
                        metricsStatBadge(label: "Results", value: "\(record.resultCount)", color: .secondary)
                        metricsStatBadge(
                            label: "Index",
                            value: record.usedIndex ? "✓ Yes" : "✗ No",
                            color: record.usedIndex ? .green : .orange
                        )
                        Spacer()
                    }
                    // Timestamp on its own row to avoid overflow on narrow inspector
                    metricsStatBadge(label: "At", value: record.formattedTimestamp, color: .secondary)

                    // EXPLAIN Output
                    VStack(alignment: .leading, spacing: 6) {
                        Label("EXPLAIN Output", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        if record.explainOutput.isEmpty {
                            Text("(no output)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            JsonSyntaxView(jsonString: record.explainOutput)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }
                }
            } else {
                // Empty state — centered vertically and horizontally
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Query Executed")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Run a query to see its performance metrics here.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 250)
            }
        }
    }

    private func metricsStatBadge(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .bold()
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private func metricsLatencyColor(_ ms: Double) -> Color {
        if ms < 10 {
            return .green
        }
        if ms < 100 {
            return .primary
        }
        return .orange
    }

    // MARK: - Inspector Helper Methods

    /// Loads a query from the inspector and automatically switches to the Query
    /// destination if needed so the QueryEditor is visible.
    func loadQueryFromInspector(_ query: String) {
        // CRITICAL: Force sidebar to stay visible BEFORE any state changes
        columnVisibility = .all

        // Only the Query destination has the QueryEditor now (History/Favorites are in inspector)
        if viewModel.selectedSidebarDestination != .query {
            viewModel.selectedSidebarDestination = .query
        }

        // Load the query
        viewModel.queryVM.selectedQuery = query

        // Double-check sidebar stays visible after state changes
        Task { @MainActor in
            columnVisibility = .all
        }

        // On iPhone, dismiss the inspector so the editor is immediately visible
        #if os(iOS)
        if horizontalSizeClass == .compact {
            showInspector = false
        }
        #endif
    }
}
