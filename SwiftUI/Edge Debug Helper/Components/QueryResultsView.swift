import SwiftUI

/// Enum representing different view modes for query results
enum ResultViewTab: String, CaseIterable {
    case raw = "Raw"
    case table = "Table"
    case map = "Map"

    var icon: String {
        switch self {
        case .raw: return "doc.plaintext"
        case .table: return "tablecells"
        case .map: return "map"
        }
    }
}

struct QueryResultsView: View {
    @Binding var jsonResults: [String]

    @State private var selectedTab: ResultViewTab = .raw
    @State private var currentPage = 1
    @State private var pageSize = 10
    @State private var isExporting = false

    private var pageSizes: [Int] {
        switch resultCount {
        case 0...10: return [10]
        case 11...25: return [10, 25]
        case 26...50: return [10, 25, 50]
        case 51...100: return [10, 25, 50, 100]
        case 101...200: return [10, 25, 50, 100, 200]
        case 201...250: return [10, 25, 50, 100, 200, 250]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }

    private var resultCount: Int {
        jsonResults.count
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(jsonResults.count) / Double(pageSize))))
    }

    init(jsonResults: Binding<[String]>) {
        _jsonResults = jsonResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Content with standard TabView
            TabView(selection: $selectedTab) {
                // Raw JSON View
                ResultJsonViewer(
                    resultText: $jsonResults,
                    externalCurrentPage: $currentPage,
                    externalPageSize: $pageSize,
                    showPaginationControls: false,
                    showExportButton: false
                )
                .tabItem {
                    Label("Raw", systemImage: "doc.plaintext")
                }
                .tag(ResultViewTab.raw)

                // Table View
                ResultTableViewer(
                    resultText: $jsonResults,
                    currentPage: $currentPage,
                    pageSize: $pageSize
                )
                .tabItem {
                    Label("Table", systemImage: "tablecells")
                }
                .tag(ResultViewTab.table)

                // Map View Placeholder
                mapPlaceholder
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                    .tag(ResultViewTab.map)
            }
            #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
            #endif

            Divider()

            Spacer()
                .frame(height: 8)

            // Shared Pagination Footer
            paginationFooter
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

    // MARK: - Pagination Footer

    private var paginationFooter: some View {
        HStack {
            Spacer()

            PaginationControls(
                totalCount: resultCount,
                currentPage: $currentPage,
                pageCount: pageCount,
                pageSize: $pageSize,
                pageSizes: pageSizes,
                onPageChange: { newPage in
                    currentPage = max(1, min(newPage, pageCount))
                },
                onPageSizeChange: { newSize in
                    pageSize = newSize
                    currentPage = 1
                }
            )

            Spacer()

            Button {
                isExporting = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Export query results to JSON file")
            .padding(.trailing, 8)
            .disabled(resultCount == 0)
            .fileExporter(
                isPresented: $isExporting,
                document: QueryResultsDocument(
                    jsonData: flattenJsonResults()
                ),
                contentType: .json,
                defaultFilename: "query_results"
            ) { _ in }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Map Placeholder

    private var mapPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Map View")
                .font(.headline)
            Text("Coming Soon")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Methods

    private func flattenJsonResults() -> String {
        // If it's a single JSON object, just return it as is
        if jsonResults.count == 1 {
            return jsonResults.first ?? "[]"
        }
        // If it's multiple objects, wrap them in an array
        return "[\n" + jsonResults.joined(separator: ",\n") + "\n]"
    }
}

#Preview {
    QueryResultsView(jsonResults: .constant([
        "{\"_id\": \"1\", \"name\": \"John Doe\", \"age\": 30, \"city\": \"New York\"}",
        "{\"_id\": \"2\", \"name\": \"Jane Smith\", \"age\": 25, \"city\": \"Los Angeles\"}",
        "{\"_id\": \"3\", \"name\": \"Bob Johnson\", \"age\": 35}"
    ]))
    .frame(width: 800, height: 600)
}
