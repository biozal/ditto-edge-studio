import SwiftUI

extension MainStudioView {
    func inspectorView() -> some View {
        Group {
            switch viewModel.selectedSidebarMenuItem.name {
            case "Collections":
                queryTabInspectorView()
            case "Observer":
                observeDetailInspectorView()
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Observable Help").font(.headline)
                Divider()
            }
            .padding(.horizontal)
            .padding(.top)
            HelpContentView(markdownContent: loadMarkdown(named: "observe"))
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
    }
}
