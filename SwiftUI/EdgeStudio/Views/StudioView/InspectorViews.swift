import SwiftUI

extension MainStudioView {
    func inspectorView() -> some View {
        Group {
            switch viewModel.selectedSidebarMenuItem.name {
            case "Collections", "Query":
                queryTabInspectorView()
            case "Observers":
                observeDetailInspectorView()
            case "App Metrics", "Query Metrics":
                metricsInspectorView()
            case "Logging":
                loggingInspectorView()
            default: // "Subscriptions"
                syncTabsInspectorView()
            }
        }
        .id(viewModel.selectedSidebarMenuItem)
        .transition(.blurReplace)
        .animation(.smooth(duration: 0.35), value: viewModel.selectedSidebarMenuItem)
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
                Picker("", selection: $viewModel.selectedQueryInspectorMenuItem) {
                    ForEach(viewModel.queryInspectorMenuItems) { item in
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

            if viewModel.selectedQueryInspectorMenuItem.name == "Help" {
                helpQueryInspectorContent()
            } else {
                ScrollView {
                    switch viewModel.selectedQueryInspectorMenuItem.name {
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
    }

    func observeDetailInspectorView() -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $viewModel.selectedObserveInspectorMenuItem) {
                    ForEach(viewModel.observeInspectorMenuItems) { item in
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

            if viewModel.selectedObserveInspectorMenuItem.name == "Help" {
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
            } else {
                metricsExportInspectorContent()
            }
        }
        .task {
            await loadMetricsExportSettings()
        }
    }

    private func metricsDocsInspectorContent() -> some View {
        let resourceName = viewModel.selectedSidebarMenuItem.name == "App Metrics" ? "appmetrics" : "querymetrics"
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

    private func metricsExportInspectorContent() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Export Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Prometheus Export", systemImage: "arrow.up.to.line")
                        .font(.headline)

                    Text("Pushgateway URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:9091 (optional)", text: $viewModel.metricsPrometheusURLText)
                    #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                        .autocorrectionDisabled()

                    HStack {
                        Text("Export interval:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("60", text: $viewModel.metricsPrometheusIntervalText)
                        #if os(macOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                            .frame(width: 60)
                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Button("Apply") {
                        Task { await applyMetricsExportSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                // Status Section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Export Status", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    if viewModel.metricsPrometheusStatusMessage.isEmpty {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text("Not configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.metricsPrometheusStatusMessage.hasPrefix("Error") ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            Text(viewModel.metricsPrometheusStatusMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.metricsPrometheusStatusMessage.hasPrefix("Error") ? .red : .primary)
                        }
                    }
                }

                Divider()

                // Actions Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Actions", systemImage: "bolt")
                        .font(.headline)

                    Button {
                        Task { await pushMetricsNow() }
                    } label: {
                        Label("Push Now", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.metricsPrometheusIsConfigured)

                    Button {
                        Task { await clearAllMetrics() }
                    } label: {
                        Label("Clear All Metrics", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private func loadMetricsExportSettings() async {
        let url = await PrometheusExportBackend.shared.pushgatewayURL
        let interval = await PrometheusExportBackend.shared.exportIntervalSeconds
        let lastPush = await PrometheusExportBackend.shared.lastPushDate
        let lastError = await PrometheusExportBackend.shared.lastPushError

        viewModel.metricsPrometheusURLText = url?.absoluteString ?? ""
        viewModel.metricsPrometheusIntervalText = "\(interval)"
        viewModel.metricsPrometheusIsConfigured = url != nil

        if let error = lastError {
            viewModel.metricsPrometheusStatusMessage = "Error: \(error)"
        } else if let date = lastPush {
            let elapsed = Int(Date().timeIntervalSince(date))
            viewModel.metricsPrometheusStatusMessage = "Last push: \(elapsed)s ago"
        } else if url != nil {
            viewModel.metricsPrometheusStatusMessage = "Configured — awaiting first push"
        } else {
            viewModel.metricsPrometheusStatusMessage = ""
        }
    }

    private func applyMetricsExportSettings() async {
        let trimmed = viewModel.metricsPrometheusURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.isEmpty ? nil : URL(string: trimmed)
        let interval = Int(viewModel.metricsPrometheusIntervalText) ?? 60
        await PrometheusExportBackend.shared.configure(url: url, intervalSeconds: interval)
        await loadMetricsExportSettings()
    }

    private func pushMetricsNow() async {
        await PrometheusExportBackend.shared.pushNow()
        await loadMetricsExportSettings()
    }

    private func clearAllMetrics() async {
        await InMemoryMetricsStore.shared.reset()
        await QueryMetricsRepository.shared.clearRecords()
        await loadMetricsExportSettings()
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
                                try await FavoritesRepository.shared.deleteFavorite(query.id)
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

            if let json = viewModel.selectedJsonForInspector {
                JsonSyntaxView(jsonString: json)
                    .id(json) // Force recreation when JSON changes
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

    private func queryMetricsInspectorContent() -> some View {
        Group {
            if let record = viewModel.lastQueryMetricsRecord {
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
        if ms < 10 { return .green }
        if ms < 100 { return .primary }
        return .orange
    }

    // MARK: - Inspector Helper Methods

    /// Loads a query from the inspector and automatically switches to Collections view if needed
    /// to ensure the QueryEditor is visible.
    func loadQueryFromInspector(_ query: String) {
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
