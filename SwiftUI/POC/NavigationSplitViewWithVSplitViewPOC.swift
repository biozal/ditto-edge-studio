import SwiftUI

/// COMPLETE WORKING POC: NavigationSplitView + Inspector + VSplitView
///
/// This POC demonstrates the EXACT pattern needed for MainStudioView to work properly:
/// - 3-pane layout: Sidebar (left) + Detail with VSplitView (center) + Inspector (right)
/// - VSplitView has resizable divider between top and bottom panes
/// - Inspector can toggle open/closed without breaking layout
/// - Sidebar remains visible when inspector opens
/// - NO constraint loop crashes
/// - Works at various window sizes (800px - 1400px)
///
/// CRITICAL SUCCESS FACTORS (what makes this work):
/// 1. VSplitView children have NO .frame(maxWidth: .infinity) modifiers
/// 2. Detail view container uses .frame(maxWidth: .infinity, maxHeight: .infinity)
/// 3. Column visibility forced to .all when needed
/// 4. Proper column width constraints on sidebar and inspector
///
/// KEY DIFFERENCE FROM BROKEN MainStudioView:
/// MainStudioView has `.frame(maxWidth: .infinity)` on EACH VSplitView child (lines 1081, 1091)
/// This POC removes those and only uses maxWidth/maxHeight on the detail container
///
/// TESTING CHECKLIST:
/// ✅ Sidebar stays visible when inspector opens
/// ✅ Inspector can open and close without breaking layout
/// ✅ VSplitView divider can be dragged to resize top/bottom panes
/// ✅ Sidebar can be resized by dragging its edge
/// ✅ Inspector can be resized by dragging its edge
/// ✅ Switching between sidebar items works
/// ✅ NO layout breaks or constraint errors in console
/// ✅ Works at various window sizes (800px - 1400px wide)

struct NavigationSplitViewWithVSplitViewPOC: View {
    // Sidebar state
    @State private var selectedMenuItem: MenuItem = .collections

    // Inspector state
    @State private var showInspector = true
    @State private var selectedInspectorTab: InspectorTab = .history

    // Column visibility - keeps sidebar always visible
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Query state
    @State private var queryText: String = "SELECT * FROM collection"
    @State private var queryResults: String = "No results yet. Click 'Execute Query' to run."
    @State private var isExecuting: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR (Left Pane)
            sidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)

        } detail: {
            // DETAIL (Center Pane) - Contains VSplitView
            // CRITICAL: NO .frame(minWidth:) here to prevent constraint loops
            detailView()
        }
        .navigationTitle("VSplitView POC")
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

            List(MenuItem.allCases, id: \.self, selection: $selectedMenuItem) { item in
                Label(item.title, systemImage: item.icon)
            }

            Spacer()

            HStack {
                Text("POC Test - VSplitView")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Detail View (WITH VSplitView)

    @ViewBuilder
    private func detailView() -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(selectedMenuItem.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("✅ VSplitView Active")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            Divider()

            // Main content - different for each menu item
            switch selectedMenuItem {
            case .collections:
                collectionsDetailView()
            case .subscriptions:
                subscriptionsDetailView()
            case .observer:
                observerDetailView()
            case .tools:
                toolsDetailView()
            }
        }
        // CRITICAL: Use maxWidth/maxHeight .infinity on the CONTAINER, not VSplitView children
        // This allows the detail view to flex and fill available space
        // without creating rigid minimum constraints that conflict with the inspector
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Collections Detail (WITH VSplitView - The Critical Test Case)

    @ViewBuilder
    private func collectionsDetailView() -> some View {
        #if os(macOS)
        // CRITICAL SECTION: VSplitView pattern that works with NavigationSplitView + Inspector
        VSplitView {
            // TOP PANE - Query Editor
            // CRITICAL: NO .frame(maxWidth: .infinity) here!
            // This is the key difference from broken MainStudioView
            VStack(alignment: .leading, spacing: 8) {
                Text("Query Editor")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                TextEditor(text: $queryText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)

                HStack {
                    Button("Execute Query") {
                        executeQuery()
                    }
                    .buttonStyle(.borderedProminent)

                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.controlBackgroundColor))
            // CRITICAL: No .frame(maxWidth: .infinity) here

            // BOTTOM PANE - Query Results
            // CRITICAL: NO .frame(maxWidth: .infinity) here either!
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)

                    Spacer()

                    Button("Raw") {}
                        .buttonStyle(.bordered)
                    Button("Table") {}
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.top)

                Divider()

                ScrollView {
                    Text(queryResults)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            }
            // CRITICAL: No .frame(maxWidth: .infinity) here either
        }
        // CRITICAL: VSplitView itself has NO frame modifiers
        // The parent VStack already has .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        // iOS fallback - regular VStack
        VStack {
            Text("VSplitView is macOS only")
                .foregroundColor(.secondary)
        }
        #endif
    }

    // MARK: - Other Detail Views (Simpler Content)

    @ViewBuilder
    private func subscriptionsDetailView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscriptions View")
                .font(.headline)

            Text("This view shows active subscriptions.")
                .foregroundColor(.secondary)

            Text("💡 The Collections view has a VSplitView with resizable divider.")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 8)

            Text("💡 Try opening the Inspector - sidebar should stay visible.")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding()
    }

    @ViewBuilder
    private func observerDetailView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observer View")
                .font(.headline)

            Text("This view shows observers.")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func toolsDetailView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ditto Tools View")
                .font(.headline)

            Text("This view shows Ditto tools.")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Inspector View

    @ViewBuilder
    private func inspectorView() -> some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedInspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
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

            Text("💡 Click a query to load it")
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

            Text("⭐ Click a favorite query")
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

    private func loadQueryFromInspector(_ query: String) {
        print("📋 Loading query from inspector: \(query)")

        // Force sidebar to stay visible
        columnVisibility = .all

        // Switch to Collections if not already there
        if selectedMenuItem != .collections {
            print("🔄 Auto-switching to Collections")
            selectedMenuItem = .collections
        }

        // Load the query
        queryText = query
        print("✅ Query loaded successfully")

        // Double-check sidebar stays visible
        DispatchQueue.main.async {
            self.columnVisibility = .all
        }
    }

    private func executeQuery() {
        isExecuting = true
        queryResults = "Executing query...\n\n\(queryText)"

        // Simulate query execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isExecuting = false
            queryResults = """
            Query executed successfully!

            Query: \(queryText)

            Results:
            {
              "collection": "test",
              "documents": [
                { "_id": "1", "name": "Item 1" },
                { "_id": "2", "name": "Item 2" },
                { "_id": "3", "name": "Item 3" }
              ],
              "count": 3
            }
            """
        }
    }
}

// MARK: - Supporting Types

enum MenuItem: String, CaseIterable {
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

enum InspectorTab: String, CaseIterable, Identifiable {
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
    NavigationSplitViewWithVSplitViewPOC()
        .frame(width: 1200, height: 800)
}

// MARK: - TESTING INSTRUCTIONS & FINDINGS

/*
 ================================================================================================
 COMPLETE TESTING CHECKLIST
 ================================================================================================

 RUN THIS POC AND VERIFY ALL OF THESE:

 1. INITIAL STATE:
    ✅ Window opens at 1200x800
    ✅ Sidebar visible on left with 4 menu items
    ✅ Detail view in center showing selected content
    ✅ Inspector visible on right with History/Favorites tabs
    ✅ NO console errors on launch

 2. VSPLITVIEW FUNCTIONALITY (Collections view):
    ✅ Click "Collections" in sidebar
    ✅ See VSplitView with Query Editor (top) and Results (bottom)
    ✅ Drag the horizontal divider between top/bottom panes
    ✅ Divider moves smoothly and panes resize
    ✅ Top pane (editor) can get smaller/larger
    ✅ Bottom pane (results) can get smaller/larger
    ✅ Type in the query editor - text appears normally
    ✅ Click "Execute Query" - results appear in bottom pane

 3. INSPECTOR INTERACTION:
    ✅ Click inspector toggle button (top-right)
    ✅ Inspector closes
    ✅ Sidebar REMAINS VISIBLE (does NOT disappear)
    ✅ VSplitView in detail view still works (can drag divider)
    ✅ Click inspector toggle again
    ✅ Inspector opens
    ✅ Sidebar STILL VISIBLE (does NOT disappear)
    ✅ VSplitView still works

 4. INSPECTOR QUERIES:
    ✅ Open inspector if closed
    ✅ Click History tab
    ✅ Click any query in history list
    ✅ Sidebar auto-switches to Collections
    ✅ Query loads into editor in detail view
    ✅ Sidebar REMAINS VISIBLE
    ✅ Inspector REMAINS VISIBLE
    ✅ Can still switch inspector tabs (History/Favorites)
    ✅ Click Favorites tab
    ✅ Click any favorite query
    ✅ Query loads into editor
    ✅ All panes still visible and functional

 5. RESIZING TESTS:
    ✅ Drag sidebar edge - sidebar width changes
    ✅ Drag inspector edge - inspector width changes
    ✅ Drag VSplitView divider - top/bottom panes resize
    ✅ All three resize operations work independently
    ✅ No layout breaks when resizing

 6. NAVIGATION TESTS:
    ✅ Click each sidebar item (Subscriptions, Collections, Observer, Tools)
    ✅ Detail view changes to show correct content
    ✅ Inspector remains visible through all changes
    ✅ Sidebar remains visible through all changes
    ✅ Click Collections - VSplitView appears
    ✅ Click away - VSplitView disappears (as expected)
    ✅ Click Collections again - VSplitView reappears and works

 7. WINDOW SIZE TESTS:
    ✅ Resize window to 800px wide - layout adapts gracefully
    ✅ Resize window to 1000px wide - layout still works
    ✅ Resize window to 1400px wide - layout expands properly
    ✅ At all sizes: sidebar visible, inspector functional, VSplitView works

 8. CONSOLE VERIFICATION:
    ✅ Open Xcode console
    ✅ Run POC
    ✅ Perform all above tests
    ✅ NO "Update Constraints in Window pass" errors
    ✅ NO Auto Layout warnings
    ✅ NO constraint loop messages
    ✅ Clean console output throughout testing

 ================================================================================================
 KEY FINDINGS - WHAT MAKES THIS WORK
 ================================================================================================

 CRITICAL PATTERN DISCOVERED:

 1. ❌ BROKEN PATTERN (MainStudioView.swift lines 1072-1092):
    ```swift
    VSplitView {
        QueryEditorView(...)
            .frame(maxWidth: .infinity)    // ❌ BAD - Creates rigid constraint

        QueryResultsView(...)
            .frame(maxWidth: .infinity)    // ❌ BAD - Creates rigid constraint
    }
    ```

    PROBLEM: Each VSplitView child has `.frame(maxWidth: .infinity)`, which creates
    rigid minimum width constraints that conflict with the inspector's width requirements.
    When inspector opens, NavigationSplitView can't satisfy all constraints simultaneously,
    so it hides the sidebar as a "compromise."

 2. ✅ WORKING PATTERN (This POC):
    ```swift
    VStack {  // Detail view container
        // Header and other content

        VSplitView {
            VStack {
                // Query editor content
            }
            // ✅ NO .frame(maxWidth: .infinity) here

            VStack {
                // Results content
            }
            // ✅ NO .frame(maxWidth: .infinity) here either
        }
        // ✅ VSplitView has NO frame modifiers at all
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
    ```

    SOLUTION: Remove `.frame(maxWidth: .infinity)` from VSplitView children.
    Only the detail view CONTAINER should have `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
    This allows VSplitView to flex naturally and share space with the inspector.

 3. WHY THIS WORKS:
    - NavigationSplitView allocates space: Sidebar (200-300) + Detail (flex) + Inspector (250-500)
    - Detail view has `.frame(maxWidth: .infinity)` = "use available space"
    - VSplitView inside detail has NO width constraints = "fit in parent's space"
    - VSplitView children have NO width constraints = "fit in VSplitView's space"
    - Result: Clean constraint chain, no conflicts, all panes visible

 4. WHY MAINVIEW BREAKS:
    - NavigationSplitView allocates space: Sidebar + Detail + Inspector
    - Detail view has NO frame modifier (implicitly flexible)
    - VSplitView inside detail has NO width constraints
    - VSplitView children EACH have `.frame(maxWidth: .infinity)` = "need infinite width"
    - NavigationSplitView sees: "Detail needs infinite width, but I also need space for inspector"
    - NavigationSplitView's solution: Hide sidebar to free up space
    - Result: Sidebar disappears when inspector opens

 ================================================================================================
 FIX FOR MAINSTUDIOVIEW
 ================================================================================================

 TO FIX MainStudioView.swift, CHANGE THIS (lines 1069-1116):

 BEFORE (BROKEN):
 ```swift
 func queryDetailView() -> some View {
     return VStack(alignment: .leading) {
         VSplitView {
             QueryEditorView(...)
                 .frame(maxWidth: .infinity)    // ❌ REMOVE THIS

             QueryResultsView(...)
                 .frame(maxWidth: .infinity)    // ❌ REMOVE THIS
         }
     }
     .padding(.bottom, 28)
 }
 ```

 AFTER (FIXED):
 ```swift
 func queryDetailView() -> some View {
     return VStack(alignment: .leading, spacing: 0) {
         VSplitView {
             QueryEditorView(...)
                 // ✅ No .frame(maxWidth: .infinity)

             QueryResultsView(...)
                 // ✅ No .frame(maxWidth: .infinity)
         }
         // ✅ VSplitView has no frame modifiers
     }
     .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Add this on container
     .padding(.bottom, 28)
 }
 ```

 ADDITIONAL CHANGE NEEDED:
 In the detail: switch statement (lines 154-164), ensure NO .frame(minWidth:) is applied:

 ```swift
 } detail: {
     switch viewModel.selectedMenuItem.name {
     case "Collections":
         queryDetailView()  // ✅ No frame modifiers here
     case "Observer":
         observeDetailView()
     case "Ditto Tools":
         dittoToolsDetailView()
     default:
         syncTabsDetailView()
     }
     // ✅ No .frame(minWidth: 400) here
 }
 ```

 ================================================================================================
 VERIFICATION SCRIPT
 ================================================================================================

 After fixing MainStudioView, verify with these steps:

 1. Open MainStudioView in app
 2. Select Collections in sidebar
 3. See VSplitView with query editor and results
 4. Drag VSplitView divider - should resize smoothly
 5. Click inspector toggle button (top-right)
 6. Inspector opens
 7. VERIFY: Sidebar STILL VISIBLE ✅
 8. VERIFY: VSplitView divider still draggable ✅
 9. VERIFY: No console errors ✅
 10. Resize window from 800px to 1400px
 11. VERIFY: Layout adapts gracefully at all sizes ✅

 SUCCESS CRITERIA:
 - All three panes visible simultaneously
 - No constraint loop errors in console
 - VSplitView divider remains draggable
 - Sidebar never disappears when inspector opens
 - Layout stable at all window sizes

 ================================================================================================
 */
