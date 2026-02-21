import SwiftUI

/// Enum representing different view modes for query results
enum ResultViewTab: String, CaseIterable {
    case raw = "Raw"
    case table = "Table"

    var icon: String {
        switch self {
        case .raw: return "doc.plaintext"
        case .table: return "tablecells"
        }
    }
}

struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    var onJsonSelected: ((String) -> Void)?

    @State private var selectedTab: ResultViewTab = .raw
    @Binding var currentPage: Int
    @Binding var pageSize: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        onJsonSelected: ((String) -> Void)? = nil
    ) {
        _jsonResults = jsonResults
        _currentPage = currentPage
        _pageSize = pageSize
        self.onJsonSelected = onJsonSelected
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                tabLayout
            }
        }
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

    private var compactLayout: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(ResultViewTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Group {
                switch selectedTab {
                case .raw:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        externalCurrentPage: $currentPage,
                        externalPageSize: $pageSize,
                        showPaginationControls: false,
                        showExportButton: false,
                        onJsonSelected: onJsonSelected
                    )
                case .table:
                    ResultTableViewer(
                        resultText: $jsonResults,
                        currentPage: $currentPage,
                        pageSize: $pageSize,
                        onJsonSelected: onJsonSelected
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabLayout: some View {
        TabView(selection: $selectedTab) {
            ResultJsonViewer(
                resultText: $jsonResults,
                externalCurrentPage: $currentPage,
                externalPageSize: $pageSize,
                showPaginationControls: false,
                showExportButton: false,
                onJsonSelected: onJsonSelected
            )
            .tabItem { Label("Raw", systemImage: "doc.plaintext") }
            .tag(ResultViewTab.raw)

            ResultTableViewer(
                resultText: $jsonResults,
                currentPage: $currentPage,
                pageSize: $pageSize,
                onJsonSelected: onJsonSelected
            )
            .tabItem { Label("Table", systemImage: "tablecells") }
            .tag(ResultViewTab.table)
        }
        #if os(macOS)
        .background(.regularMaterial)
        #endif
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
