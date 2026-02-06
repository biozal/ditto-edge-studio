import SwiftUI

struct ResultTableViewer: View {
    @Binding var resultText: [String]
    @Binding var currentPage: Int
    @Binding var pageSize: Int

    @State private var tableData: TableResultsData?
    @State private var isLoading = false
    @State private var selectedRowId: UUID?
    @State private var copiedRowId: UUID?
    
    private let defaultColumnWidth: CGFloat = 200

    private var pagedItems: [String] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, resultText.count)
        guard start < resultText.count else { return [] }
        return Array(resultText[start..<end])
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingView
            } else if let data = tableData, !data.rows.isEmpty {
                #if os(macOS)
                macOSTableView(data: data)
                #else
                iPadOSTableView(data: data)
                #endif
            } else {
                emptyStateView
            }
        }
        .task(id: pagedItems.count) {
            await loadTableData()
        }
        .task(id: currentPage) {
            await loadTableData()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Parsing results...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Results")
                .font(.headline)
            Text("Execute a query to see results in table format")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - macOS Table View

    #if os(macOS)
    private func macOSTableView(data: TableResultsData) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Data rows
                        ForEach(data.rows) { row in
                            HStack(spacing: 0) {
                                // Row number
                                Text("\(row.rowIndex + 1)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 50, alignment: .center)
                                    .padding(.vertical, 8)
                                    .background(copiedRowId == row.id ? Color.green.opacity(0.2) : Color.clear)

                                // Data cells
                                ForEach(data.columns, id: \.self) { columnName in
                                    Divider()

                                    if let cellValue = row.cells[columnName] {
                                        Text(cellValue.displayValue)
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(3)
                                            .truncationMode(.tail)
                                            .textSelection(.enabled)
                                            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 8)
                                    } else {
                                        Text("")
                                            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 8)
                                    }
                                }

                                Divider()
                            }
                            .frame(minWidth: geometry.size.width)
                            .background(
                                (row.rowIndex % 2 == 0 ? Color(NSColor.textBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.3))
                            )
                            .onTapGesture(count: 2) {
                                copyRowToClipboard(row)
                            }
                        }
                    } header: {
                        // Sticky header with resizable columns
                        HStack(spacing: 0) {
                            // Row number header
                            Text("#")
                                .font(.system(.headline, design: .monospaced))
                                .frame(width: 50, alignment: .center)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))

                            // Column headers
                            ForEach(data.columns, id: \.self) { columnName in
                                Divider()

                                Text(columnName)
                                    .font(.system(.headline, design: .monospaced))
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.windowBackgroundColor))
                            }

                            Divider()
                        }
                        .frame(minWidth: geometry.size.width)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - iPadOS Table View

    #if os(iOS)
    private func iPadOSTableView(data: TableResultsData) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // Data rows
                    ForEach(data.rows) { row in
                        HStack(spacing: 0) {
                            // Row number
                            Text("\(row.rowIndex + 1)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .center)
                                .padding(.vertical, 8)
                                .background(copiedRowId == row.id ? Color.green.opacity(0.2) : Color.clear)

                            // Data cells with fixed column widths
                            ForEach(data.columns, id: \.self) { columnName in
                                Divider()

                                if let cellValue = row.cells[columnName] {
                                    Text(cellValue.displayValue)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(3)
                                        .truncationMode(.tail)
                                        .textSelection(.enabled)
                                        .frame(width: defaultColumnWidth, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                } else {
                                    Text("")
                                        .frame(width: defaultColumnWidth, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                            }

                            Divider()
                        }
                        .background(
                            (row.rowIndex % 2 == 0 ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground).opacity(0.3))
                        )
                        .onTapGesture(count: 2) {
                            copyRowToClipboard(row)
                        }
                    }
                } header: {
                    // Sticky header
                    HStack(spacing: 0) {
                        // Row number header
                        Text("#")
                            .font(.system(.headline, design: .monospaced))
                            .frame(width: 50, alignment: .center)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.systemBackground))

                        // Column headers
                        ForEach(data.columns, id: \.self) { columnName in
                            Divider()

                            Text(columnName)
                                .font(.system(.headline, design: .monospaced))
                                .frame(width: defaultColumnWidth, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.systemBackground))
                        }

                        Divider()
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Data Loading

    private func loadTableData() async {
        isLoading = true

        let data = await TableResultsParser.shared.parseResults(pagedItems)
        tableData = data

        isLoading = false
    }

    // MARK: - Clipboard Actions

    private func copyRowToClipboard(_ row: TableResultRow) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.originalJson, forType: .string)
        #else
        UIPasteboard.general.string = row.originalJson
        #endif

        // Visual feedback
        withAnimation {
            copiedRowId = row.id
        }

        // Reset after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            await MainActor.run {
                withAnimation {
                    copiedRowId = nil
                }
            }
        }
    }
}

// MARK: - Table Cell View

private struct TableCellView: View {
    let value: TableCellValue?
    let isCopied: Bool

    var body: some View {
        Group {
            if let value = value {
                Text(value.displayValue)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            } else {
                Text("")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCopied ? Color.green.opacity(0.2) : Color.clear)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var results = [
            "{\"_id\": \"1\", \"name\": \"John Doe\", \"age\": 30, \"city\": \"New York\"}",
            "{\"_id\": \"2\", \"name\": \"Jane Smith\", \"age\": 25, \"city\": \"Los Angeles\"}",
            "{\"_id\": \"3\", \"name\": \"Bob Johnson\", \"age\": 35}"
        ]
        @State private var currentPage = 1
        @State private var pageSize = 10

        var body: some View {
            ResultTableViewer(
                resultText: $results,
                currentPage: $currentPage,
                pageSize: $pageSize
            )
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    return PreviewWrapper()
}
