import SwiftUI

/// Complete POC demonstrating NavigationSplitView + Inspector with dynamic view switching
/// This POC validates the pattern for Edge Debug Helper's use case:
/// - 3-pane layout (Sidebar + Detail + Inspector)
/// - Inspector with History/Favorites tabs
/// - **CRITICAL USE CASE**: Clicking queries in inspector CHANGES the detail view content:
///   * User on Subscriptions view → clicks query in inspector
///   * Sidebar switches to Collections
///   * Detail view changes to show Collections content with query loaded
///   * Sidebar and Inspector BOTH remain visible and functional
/// - No constraint loop crashes
///
/// CRITICAL: This POC proves that removing .frame(minWidth:) from detail views
/// prevents the constraint loop crash while maintaining proper layout even when
/// the inspector triggers detail view changes.

struct NavigationSplitViewInspectorTest: View {
    // Sidebar state
    @State private var selectedMenuItem: TestMenuItem = .subscriptions

    // Inspector state
    @State private var showInspector = true
    @State private var selectedInspectorTab: TestInspectorTab = .history

    // Column visibility - keeps sidebar always visible
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Query state (simulates loading query from inspector)
    @State private var currentQuery: String = ""
    @State private var lastAction: String = "App started" // Tracks what triggered the current view

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR (Left Pane)
            sidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)

        } detail: {
            // DETAIL (Center Pane)
            // CRITICAL: NO .frame(minWidth: 400) here!
            // This is the key to preventing constraint loops
            detailView()
        }
        .navigationTitle("POC Test")
        .inspector(isPresented: $showInspector) {
            // INSPECTOR (Right Pane)
            inspectorView()
                .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(showInspector ? .primary : .secondary)
                }
                .help("Toggle Inspector")
            }
        }
    }

    // MARK: - Sidebar View

    @ViewBuilder
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Navigation")
                .font(.headline)
                .padding()

            List(TestMenuItem.allCases, id: \.self, selection: $selectedMenuItem) { item in
                Label(item.title, systemImage: item.icon)
            }
            .onChange(of: selectedMenuItem) { oldValue, newValue in
                // Track manual sidebar navigation
                if !lastAction.contains("Inspector clicked") {
                    lastAction = "Manually clicked \(newValue.title) in sidebar"
                }
            }

            Spacer()

            HStack {
                Text("POC Test")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private func detailView() -> some View {
        VStack(spacing: 0) {
            // Header showing current view and status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(selectedMenuItem.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("✅ Detail View Active")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Text("Last Action: \(lastAction)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Show different content based on selected view
                    switch selectedMenuItem {
                    case .subscriptions:
                        subscriptionsContent()
                    case .collections:
                        collectionsContent()
                    case .observer:
                        observerContent()
                    case .tools:
                        toolsContent()
                    }
                }
                .padding()
            }
            // CRITICAL: Use maxWidth/maxHeight .infinity, NOT minWidth
            // This allows the detail view to flex and fill available space
            // without creating rigid minimum constraints
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func subscriptionsContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscriptions View")
                .font(.headline)

            Text("This view shows active subscriptions.")
                .foregroundColor(.secondary)

            Text("💡 Try opening the Inspector and clicking a query in History or Favorites.")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 8)

            Text("The sidebar should auto-switch to Collections without crashing.")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private func collectionsContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collections View - Query Editor")
                .font(.headline)

            if !currentQuery.isEmpty {
                Text("Loaded Query:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(currentQuery)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            Divider()

            Text("Query Editor")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: $currentQuery)
                .font(.system(.body, design: .monospaced))
                .frame(height: 150)
                .border(Color.gray.opacity(0.3))

            Text("Results")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top)

            ScrollView {
                Text("Query results would appear here...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .border(Color.gray.opacity(0.3))
        }
    }

    @ViewBuilder
    private func observerContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observer View")
                .font(.headline)

            Text("This view shows observers.")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func toolsContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ditto Tools View")
                .font(.headline)

            Text("This view shows Ditto tools.")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Inspector View

    @ViewBuilder
    private func inspectorView() -> some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedInspectorTab) {
                ForEach(TestInspectorTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: 28)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Inspector content
            ScrollView {
                switch selectedInspectorTab {
                case .history:
                    historyInspectorContent()
                case .favorites:
                    favoritesInspectorContent()
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func historyInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query History")
                .font(.headline)
                .padding(.bottom, 4)

            Text("💡 Click a query below while viewing Subscriptions")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.bottom, 8)

            ForEach(1...5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text("SELECT * FROM collection\(index)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3)

                    Text("\(index * 2) minutes ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .onTapGesture {
                    // KEY TEST: Click query while on Subscriptions view
                    // Should auto-switch to Collections without crash
                    loadQueryFromInspector("SELECT * FROM collection\(index)")
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

            Text("⭐ Click a favorite query below")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.bottom, 8)

            ForEach(1...3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Favorite \(index)")
                            .font(.subheadline)
                    }

                    Text("SELECT * FROM favorite_\(index)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .onTapGesture {
                    loadQueryFromInspector("SELECT * FROM favorite_\(index)")
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Loads a query from inspector and switches to Collections view if needed
    /// This is the critical test case that was causing crashes in MainStudioView
    private func loadQueryFromInspector(_ query: String) {
        let previousView = selectedMenuItem.title
        print("📋 Loading query from inspector: \(query)")
        print("📍 Current view: \(previousView)")

        // CRITICAL: Force sidebar to stay visible BEFORE switching views
        // Without this, SwiftUI auto-hides the sidebar when selectedMenuItem changes
        columnVisibility = .all

        // Switch to Collections if not already there
        if selectedMenuItem != .collections {
            print("🔄 Auto-switching from \(previousView) to Collections")
            selectedMenuItem = .collections
            lastAction = "Inspector clicked → switched from \(previousView) to Collections"
        } else {
            lastAction = "Inspector clicked → already on Collections"
        }

        // Load the query
        currentQuery = query
        print("✅ Query loaded: \(query)")
        print("✅ Detail view now showing: Collections with query editor")

        // Double-check sidebar stays visible after state changes
        // This async check catches cases where SwiftUI tries to hide sidebar after state update
        DispatchQueue.main.async { [self] in
            self.columnVisibility = .all
            print("✅ Sidebar visibility confirmed: \(self.columnVisibility)")
            print("✅ Inspector remains open: \(self.showInspector)")
        }
    }
}

// MARK: - Supporting Types

enum TestMenuItem: String, CaseIterable {
    case subscriptions = "Subscriptions"
    case collections = "Collections"
    case observer = "Observer"
    case tools = "Tools"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .collections: return "tray.2"
        case .observer: return "eye"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

enum TestInspectorTab: String, CaseIterable, Identifiable {
    case history = "History"
    case favorites = "Favorites"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .history: return "clock"
        case .favorites: return "bookmark"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitViewInspectorTest()
        .frame(width: 1200, height: 800)
}

// MARK: - Testing Instructions
/*
 HOW TO TEST THIS POC:

 1. Run this POC in Xcode Preview or as standalone window
 2. Verify window size works from 600px to 1400px width
 3. Test the critical scenario:

 CRITICAL TEST CASE (Inspector triggers detail view change):
 a. Navigate to "Subscriptions" in sidebar
    → Detail view shows Subscriptions content
 b. Open Inspector (sidebar.right button)
 c. Go to History tab in inspector
 d. Click any query in the history list
 e. EXPECTED BEHAVIOR (all must work):
    ✅ Sidebar selection auto-switches from "Subscriptions" to "Collections"
    ✅ Detail view CHANGES to show Collections content (query editor)
    ✅ Query text loads into the editor in detail view
    ✅ Sidebar REMAINS VISIBLE (does not disappear)
    ✅ Inspector REMAINS VISIBLE and functional (can still switch tabs)
    ✅ NO CRASHES
    ✅ NO "Update Constraints in Window pass" errors in console
    ✅ Layout remains stable - all three panes visible and working

 f. ADDITIONAL VALIDATION:
    → Click History tab again - should still work
    → Click another query - should load without issues
    → Switch back to Favorites tab - should work
    → Click a favorite query - should load in Collections view
    → Manually click Subscriptions in sidebar - should switch back
    → Inspector should still function after all these changes

 4. Repeat test from Observer view
 5. Repeat test with Favorites tab
 6. Resize window while switching views
 7. Toggle inspector open/closed multiple times

 SUCCESS CRITERIA:
 - All navigation works smoothly
 - No constraint loop crashes
 - Sidebar never disappears unexpectedly
 - Console shows no Auto Layout warnings
 - Layout adapts gracefully to window resizing

 KEY OBSERVATION:
 This POC uses .frame(maxWidth: .infinity) on detail view,
 NOT .frame(minWidth: 400).

 This is the critical difference that prevents constraint loops
 while still providing a proper three-pane layout.
 */
