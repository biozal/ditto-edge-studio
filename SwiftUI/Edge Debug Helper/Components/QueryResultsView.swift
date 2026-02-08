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
    var onGetLastQuery: (() -> String)? = nil
    var onInsertQuery: ((String) -> Void)? = nil

    @State private var selectedTab: ResultViewTab = .raw
    @State private var currentPage = 1
    @State private var pageSize = 10
    @State private var isExporting = false
    @State private var copiedDQLNotification: String? = nil

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

    init(jsonResults: Binding<[String]>, onGetLastQuery: (() -> String)? = nil, onInsertQuery: ((String) -> Void)? = nil) {
        _jsonResults = jsonResults
        self.onGetLastQuery = onGetLastQuery
        self.onInsertQuery = onInsertQuery
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
            }
            #if os(macOS)
            .background(.regularMaterial)
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
        .overlay(alignment: .top) {
            if let message = copiedDQLNotification {
                Text(message)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .subtleShadow()
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
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

            // Generate DQL Button
            generateDQLButton

            Button {
                isExporting = true
            } label: {
                FontAwesomeText(icon: ActionIcon.download, size: 14)
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
        .padding(.vertical, 8)      // Reduced from 12pt to 8pt for more compact footer
        .padding(.horizontal, 20)
        .padding(.bottom, 4)        // Reduced from 8pt to 4pt for tighter spacing
        .liquidGlassToolbar()
    }

    // MARK: - Generate DQL Button

    private var generateDQLButton: some View {
        Menu {
            Button("SELECT with all fields") { generateAndInsert(.select) }
            Button("INSERT template") { generateAndInsert(.insert) }
            Button("UPDATE template") { generateAndInsert(.update) }
            Button("DELETE template") { generateAndInsert(.delete) }
            Button("EVICT template") { generateAndInsert(.evict) }
        } label: {
            FontAwesomeText(icon: DataIcon.code, size: 14)
        }
        .disabled(jsonResults.isEmpty)
        .help("Generate DQL statement templates based on query results")
        .padding(.trailing, 8)
    }

    // MARK: - DQL Generation

    private enum DQLStatementType {
        case select, insert, update, delete, evict
    }

    private func generateAndInsert(_ type: DQLStatementType) {
        // 1. Get last executed query
        guard let lastQuery = onGetLastQuery?() else {
            showNotification("No query available")
            return
        }

        // 2. Extract collection name
        let queryInfo = QueryInfo(query: lastQuery)
        guard let collectionName = queryInfo.collectionName else {
            showNotification("Could not extract collection name from query")
            return
        }

        // 3. Get field names from first JSON result
        let fieldNames = extractFieldNamesFromJSON()

        // 4. Generate DQL
        let dql: String
        switch type {
        case .select:
            dql = DQLGenerator.generateSelect(collection: collectionName, fields: fieldNames)
        case .insert:
            dql = DQLGenerator.generateInsert(collection: collectionName, fields: fieldNames)
        case .update:
            dql = DQLGenerator.generateUpdate(collection: collectionName, fields: fieldNames)
        case .delete:
            dql = DQLGenerator.generateDelete(collection: collectionName)
        case .evict:
            dql = DQLGenerator.generateEvict(collection: collectionName)
        }

        // 5. Insert into editor
        onInsertQuery?(dql)
    }

    private func extractFieldNamesFromJSON() -> [String] {
        guard let firstResult = jsonResults.first,
              let jsonData = firstResult.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return []
        }

        // Sort: _id first, then alphabetically
        var keys = Array(jsonObject.keys).sorted()
        if let idIndex = keys.firstIndex(of: "_id") {
            keys.remove(at: idIndex)
            keys.insert("_id", at: 0)
        }
        return keys
    }

    private func showNotification(_ message: String) {
        copiedDQLNotification = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                copiedDQLNotification = nil
            }
        }
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
