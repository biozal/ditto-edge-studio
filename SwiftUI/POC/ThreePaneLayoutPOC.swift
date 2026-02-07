import SwiftUI

// MARK: - Proof of Concept for 3-Pane Layout Like Xcode
// This POC demonstrates how to achieve Sidebar -> Detail -> Inspector layout
// using NavigationSplitView + .inspector() modifier

struct ThreePaneLayoutPOC: View {
    // Sidebar state
    @State private var selectedMenuItem: MenuItem = .collections
    @State private var selectedCollection: String?

    // Inspector state
    @State private var showInspector = true
    @State private var selectedInspectorTab: InspectorTab = .history

    var body: some View {
        NavigationSplitView {
            // SIDEBAR (Left Panel)
            sidebarView()
        } detail: {
            // DETAIL (Center Panel - Main Content)
            detailView()
        }
        .inspector(isPresented: $showInspector) {
            // INSPECTOR (Right Panel - Like Xcode's Inspector)
            inspectorView()
                .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
        }
        .toolbar {
            // Toggle inspector button (like Xcode's inspector toggle)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
    }

    // MARK: - Helper Methods

    /// Loads a query from the inspector and ensures the QueryEditor is visible
    /// This demonstrates automatic context switching when clicking History/Favorites
    private func loadQueryFromInspector(_ query: String) {
        // Check if current view supports QueryEditor
        // In this POC, only "Collections" view shows the QueryEditor
        let queryEditorViews: [MenuItem] = [.collections]

        if !queryEditorViews.contains(selectedMenuItem) {
            // Auto-switch to Collections to show QueryEditor
            print("🔄 Auto-switching sidebar to Collections (current: \(selectedMenuItem.title))")
            selectedMenuItem = .collections
        }

        // Simulate loading query into editor
        print("✅ Loaded query: \(query)")

        // Optional: ensure inspector stays visible
        if !showInspector {
            showInspector = true
        }
    }

    // MARK: - Sidebar View (Left)
    @ViewBuilder
    private func sidebarView() -> some View {
        VStack(alignment: .leading) {
            Text("Navigation Menu")
                .font(.headline)
                .padding()

            List(MenuItem.allCases, id: \.self, selection: $selectedMenuItem) { item in
                Label(item.title, systemImage: item.icon)
            }

            Spacer()

            HStack {
                Button(action: {}) {
                    Image(systemName: "plus.circle")
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Sidebar")
    }

    // MARK: - Detail View (Center)
    @ViewBuilder
    private func detailView() -> some View {
        VStack {
            Text("Main Content Area")
                .font(.title)
                .padding()

            Text("Selected: \(selectedMenuItem.title)")
                .font(.headline)

            Divider()

            // Simulate query editor and results
            VStack(alignment: .leading, spacing: 10) {
                Text("Query Editor")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: .constant("SELECT * FROM collection"))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))

                Text("Results")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top)

                ScrollView {
                    Text("Query results would appear here...")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .border(Color.gray.opacity(0.3))
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Detail View")
    }

    // MARK: - Inspector View (Right)
    @ViewBuilder
    private func inspectorView() -> some View {
        VStack(spacing: 0) {
            // Tab selector for inspector
            Picker("Inspector Tab", selection: $selectedInspectorTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Inspector content based on selected tab
            ScrollView {
                switch selectedInspectorTab {
                case .history:
                    historyInspectorContent()
                case .favorites:
                    favoritesInspectorContent()
                case .settings:
                    settingsInspectorContent()
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector Content Views
    @ViewBuilder
    private func historyInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Query History")
                .font(.headline)
                .padding(.bottom, 4)

            Text("💡 Try clicking a query while viewing 'Subscriptions' sidebar")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.vertical, 4)

            ForEach(1...5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text("SELECT * FROM collection\(index)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)

                    Text("2 minutes ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .onTapGesture {
                    // KEY: Auto-switch to Collections if needed
                    loadQueryFromInspector("SELECT * FROM collection\(index)")
                }
            }
        }
    }

    @ViewBuilder
    private func favoritesInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorite Queries")
                .font(.headline)
                .padding(.bottom, 4)

            Text("💡 Try clicking a query while viewing 'Observers' sidebar")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.vertical, 4)

            ForEach(1...3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Query \(index)")
                            .font(.subheadline)
                    }

                    Text("SELECT * FROM favorite_\(index)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .onTapGesture {
                    // KEY: Auto-switch to Collections if needed
                    loadQueryFromInspector("SELECT * FROM favorite_\(index)")
                }
            }
        }
    }

    @ViewBuilder
    private func settingsInspectorContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transport Settings")
                .font(.headline)
                .padding(.bottom, 4)

            // Simulate transport config settings
            VStack(alignment: .leading, spacing: 12) {
                Toggle("WebSocket", isOn: .constant(true))
                Toggle("Bluetooth LE", isOn: .constant(true))
                Toggle("P2P WiFi", isOn: .constant(false))
                Toggle("Access Point", isOn: .constant(false))
            }

            Divider()
                .padding(.vertical)

            Text("Connection Settings")
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Timeout:")
                    Spacer()
                    Text("30s")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Retry Count:")
                    Spacer()
                    Text("3")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum MenuItem: String, CaseIterable {
    case collections = "Collections"
    case subscriptions = "Subscriptions"
    case observers = "Observers"
    case tools = "Tools"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .collections: return "tray.2"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .observers: return "eye"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

enum InspectorTab: String, CaseIterable {
    case history = "History"
    case favorites = "Favorites"
    case settings = "Settings"

    var title: String { rawValue }
}

// MARK: - Preview

#Preview {
    ThreePaneLayoutPOC()
        .frame(width: 1200, height: 800)
}

// MARK: - Testing Instructions
/*
 HOW TO TEST THIS POC:

 1. Open this file in Xcode
 2. Use the Preview or create a new macOS app target that uses this view as the root
 3. Verify the following behaviors:

 LAYOUT:
 - [ ] Three distinct panes: Sidebar (left), Detail (center), Inspector (right)
 - [ ] Inspector appears on the RIGHT side (not between sidebar and detail)
 - [ ] Inspector can be toggled via toolbar button
 - [ ] Inspector is resizable by dragging the divider
 - [ ] Inspector respects min/ideal/max width constraints

 FUNCTIONALITY:
 - [ ] Sidebar navigation items are selectable
 - [ ] Detail view updates based on sidebar selection
 - [ ] Inspector tabs (History, Favorites, Settings) are switchable
 - [ ] Inspector content updates based on selected tab
 - [ ] Inspector state persists when switching sidebar items

 AUTOMATIC CONTEXT SWITCHING (Critical Feature):
 - [ ] Navigate to "Subscriptions" or "Observers" sidebar
 - [ ] Open inspector → History tab
 - [ ] Click a history query item
 - [ ] ✅ Sidebar automatically switches to "Collections"
 - [ ] ✅ Check console for "🔄 Auto-switching..." message
 - [ ] ✅ Check console for "✅ Loaded query..." message
 - [ ] Repeat test with Favorites tab
 - [ ] Already viewing "Collections" → click query
 - [ ] ✅ Sidebar stays on "Collections" (no unnecessary switch)

 ADAPTIVE BEHAVIOR (iPad/Compact):
 - [ ] On iPad in narrow mode, inspector becomes a sheet
 - [ ] Toggle button still works in compact mode

 KEY OBSERVATIONS:
 - Does this match Xcode's inspector behavior?
 - Is the inspector on the RIGHT side as expected?
 - Can we easily integrate History and Favorites here?
 - Does this work well with the existing MainStudioView structure?

 INTEGRATION NOTES:
 - The inspector can be shown/hidden programmatically
 - Multiple views can share the same inspector state
 - Inspector content can be context-sensitive based on main view selection
 - We can use @Binding to coordinate between detail view and inspector
 */
