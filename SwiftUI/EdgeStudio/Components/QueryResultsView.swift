import SwiftUI

/// Enum representing different view modes for query results
enum ResultViewTab: String, CaseIterable {
    case raw = "Raw"
    case table = "Table"
    case profile = "Profile"

    var icon: String {
        switch self {
        case .raw: return "doc.plaintext"
        case .table: return "tablecells"
        // Tree-list glyph signals "execution plan" without leaning on
        // a database-specific symbol. The Profile tab content swaps
        // this icon at the Card vs Plan sub-picker in Slice 3.
        case .profile: return "list.bullet.indent"
        }
    }
}

struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    var onJsonSelected: ((String) -> Void)?
    var onAddAttachment: ((String) -> Void)?
    var onDeleteAttachment: ((String) -> Void)?

    /// Execution-plan profile captured for the most recent Local run.
    /// Nil when metrics are off, the query isn't a SELECT, the run
    /// went through HTTP, or no query has been run yet. The Profile
    /// tab uses this plus `lastQueryText` + `metricsEnabled` below
    /// to pick which of its four states to render.
    var profile: QueryProfile?
    /// Last query the user submitted. Used by the Profile tab's
    /// empty states to differentiate "no query yet" from "non-SELECT
    /// query" — `profile` being nil isn't sufficient to tell them
    /// apart on its own.
    var lastQueryText = ""

    @State private var selectedTab: ResultViewTab = .raw
    @Binding var currentPage: Int
    @Binding var pageSize: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Mirrors the global "Collect Metrics" setting so the Profile
    /// tab can render the "Profiling is turned off" empty state with
    /// a one-tap "Open Settings…" CTA when it's false.
    @AppStorage("metricsEnabled") private var metricsEnabled = true

    private var pageSizes: [Int] {
        switch resultCount {
        case 0 ... 10: return [10]
        case 11 ... 25: return [10, 25]
        case 26 ... 50: return [10, 25, 50]
        case 51 ... 100: return [10, 25, 50, 100]
        case 101 ... 200: return [10, 25, 50, 100, 200]
        case 201 ... 250: return [10, 25, 50, 100, 200, 250]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }

    private var resultCount: Int {
        jsonResults.count
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(jsonResults.count) / Double(pageSize))))
    }

    init(
        jsonResults: Binding<[String]>,
        currentPage: Binding<Int>,
        pageSize: Binding<Int>,
        profile: QueryProfile? = nil,
        lastQueryText: String = "",
        onJsonSelected: ((String) -> Void)? = nil,
        onAddAttachment: ((String) -> Void)? = nil,
        onDeleteAttachment: ((String) -> Void)? = nil
    ) {
        _jsonResults = jsonResults
        _currentPage = currentPage
        _pageSize = pageSize
        self.profile = profile
        self.lastQueryText = lastQueryText
        self.onJsonSelected = onJsonSelected
        self.onAddAttachment = onAddAttachment
        self.onDeleteAttachment = onDeleteAttachment
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Result View", selection: $selectedTab) {
                ForEach(ResultViewTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(horizontalSizeClass == .compact ? .regular : .large)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityIdentifier("ResultsViewModeToggle")

            Group {
                switch selectedTab {
                case .raw:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        externalCurrentPage: $currentPage,
                        externalPageSize: $pageSize,
                        showPaginationControls: false,
                        showExportButton: false,
                        onJsonSelected: onJsonSelected,
                        onAddAttachment: onAddAttachment,
                        onDeleteAttachment: onDeleteAttachment
                    )
                case .table:
                    ResultTableViewer(
                        resultText: $jsonResults,
                        currentPage: $currentPage,
                        pageSize: $pageSize,
                        onJsonSelected: onJsonSelected,
                        onAddAttachment: onAddAttachment,
                        onDeleteAttachment: onDeleteAttachment
                    )
                case .profile:
                    ProfileViewerView(
                        profile: profile,
                        metricsEnabled: metricsEnabled,
                        lastQueryText: lastQueryText
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .background(.regularMaterial)
        #endif
        // Stable container identifier so XCUITest can assert the results pane is
        // present after a query runs.
        .accessibilityIdentifier("QueryResultsView")
        .accessibilityElement(children: .contain)
        .onChange(of: pageSize) { _, _ in
            currentPage = max(1, min(currentPage, pageCount))
        }
        .onChange(of: jsonResults) { _, _ in
            currentPage = 1
            if !pageSizes.contains(pageSize) {
                pageSize = pageSizes.first ?? 25
            }
        }
    }
}

#Preview {
    QueryResultsView(
        jsonResults: .constant([
            "{\"_id\": \"1\", \"name\": \"John Doe\", \"age\": 30, \"city\": \"New York\"}",
            "{\"_id\": \"2\", \"name\": \"Jane Smith\", \"age\": 25, \"city\": \"Los Angeles\"}",
            "{\"_id\": \"3\", \"name\": \"Bob Johnson\", \"age\": 35}"
        ]),
        currentPage: .constant(1),
        pageSize: .constant(10)
    )
    .frame(width: 800, height: 600)
}
