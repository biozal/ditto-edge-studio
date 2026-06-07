import SwiftUI

struct ResultTableViewer: View {
    @Binding var resultText: [String]
    @Binding var currentPage: Int
    @Binding var pageSize: Int

    @State private var tableData: TableResultsData?
    @State private var isLoading = false
    @State private var selectedRowId: UUID?
    @State private var copiedRowId: UUID?
    @State private var copyResetTask: Task<Void, Never>?

    /// Callback for JSON selection (opens in inspector)
    var onJsonSelected: ((String) -> Void)?

    /// Callback for adding an attachment to a document
    var onAddAttachment: ((String) -> Void)?

    /// Callback for deleting attachment field(s) from a document
    var onDeleteAttachment: ((String) -> Void)?

    private var pagedItems: [String] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, resultText.count)
        guard start < resultText.count else { return [] }
        return Array(resultText[start ..< end])
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: pagedItems) {
            await loadTableData()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Parsing results...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            FontAwesomeText(icon: DataIcon.table, size: 48, color: .secondary)
            Text("No Results")
                .font(.headline)
            Text("Execute a query to see results in table format")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared sizing constants

    /// Width of the fixed left-edge row-number column (`#`). Shared by
    /// macOS and iPadOS — same on both since it just holds an integer.
    private static let rowNumberColumnWidth: CGFloat = 50

    /// Color for the horizontal divider drawn at the bottom of each
    /// data row and below the sticky header. The default SwiftUI
    /// `Divider()` and the `NSColor.separatorColor` are too subtle to
    /// distinguish rows when the alternating background opacities are
    /// also low-contrast (dark mode in particular). A semi-opaque
    /// secondary color is uniformly visible in both light and dark.
    private static let rowDividerColor: Color = .secondary.opacity(0.35)
    private static let rowDividerHeight: CGFloat = 1

    // MARK: - macOS Table View

    #if os(macOS)
    /// Minimum width for a data column when horizontal scrolling kicks
    /// in. Headers + cells use `.frame(width:)` with this value or larger,
    /// never `.frame(maxWidth: .infinity)`, because inside a ScrollView
    /// with horizontal scrolling enabled, `maxWidth: .infinity` has no
    /// upper bound to expand against — the LazyVStack sizes to intrinsic
    /// content and the table renders as a tiny floating island.
    private static let macOSMinColumnWidth: CGFloat = 150

    private func macOSTableView(data: TableResultsData) -> some View {
        GeometryReader { geo in
            let columnCount = max(1, data.columns.count)
            let availableForColumns = max(0, geo.size.width - Self.rowNumberColumnWidth)
            let minTotalColumnWidth = CGFloat(columnCount) * Self.macOSMinColumnWidth
            // Two modes:
            //  - Fits: distribute the available viewport width evenly so
            //    the table fills the pane and no horizontal scroll appears.
            //  - Overflows: fall back to the minimum width per column and
            //    let the ScrollView scroll horizontally.
            let cellWidth = availableForColumns >= minTotalColumnWidth
                ? availableForColumns / CGFloat(columnCount)
                : Self.macOSMinColumnWidth
            let totalWidth = Self.rowNumberColumnWidth + CGFloat(columnCount) * cellWidth

            ScrollView([.horizontal, .vertical]) {
                // Outer VStack + trailing Spacer with `minHeight: viewport`
                // anchors short tables to the top. Without this, SwiftUI's
                // ScrollView centres content vertically when content height
                // < viewport height with both scroll axes enabled — the
                // exact symptom users see on the final page of a paginated
                // result set (which has fewer rows than the page size).
                // When rows DO fill the viewport, the Spacer collapses to
                // zero height and normal vertical scrolling resumes.
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(data.rows) { row in
                                macOSRowView(row: row, columns: data.columns, cellWidth: cellWidth)
                            }
                        } header: {
                            macOSHeaderView(columns: data.columns, cellWidth: cellWidth)
                        }
                    }
                    .frame(width: totalWidth, alignment: .leading)
                    // Background painted on the LazyVStack (the table
                    // content) rather than the outer ScrollView so it
                    // stops at the last row; the area below shows the
                    // parent pane's material via the Spacer below.
                    .background(Color(NSColor.textBackgroundColor))

                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Tie ScrollView identity to the current page so SwiftUI tears
            // it down and rebuilds it on each page switch. Without this,
            // the ScrollView preserves its prior scroll offset and the
            // pinned-section-header retains layout state computed against
            // the old (larger) row set — the new page's rows then render
            // pushed down inside a scroll-offset-stale ScrollView and look
            // like they're floating in the middle of the pane. Recreating
            // is cheap (page size capped at 250 rows) and only happens
            // on user-initiated page changes.
            .id(currentPage)
        }
    }

    private func macOSRowView(row: TableResultRow, columns: [String], cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("\(row.rowIndex + 1)")
                .font(.system(.body, design: .monospaced))
                .frame(width: Self.rowNumberColumnWidth, alignment: .center)
                .padding(.vertical, 8)
                .background(copiedRowId == row.id ? Color.green.opacity(0.2) : Color.clear)

            ForEach(columns, id: \.self) { columnName in
                Divider()

                Group {
                    if let cellValue = row.cells[columnName] {
                        // NOTE: do NOT add `.textSelection(.enabled)`.
                        // It hosts an NSTextView that swallows right-click
                        // and breaks the row's context menu on every data
                        // column. See QueryResultRowMenu.swift for context.
                        Text(cellValue.displayValue)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(width: cellWidth, alignment: .leading)
            }

            Divider()
        }
        .background(row.rowIndex % 2 == 0
            ? Color(NSColor.textBackgroundColor)
            : Color(NSColor.controlBackgroundColor).opacity(0.3))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Self.rowDividerColor)
                .frame(height: Self.rowDividerHeight)
        }
        .onTapGesture(count: 2) {
            copyRowToClipboard(row)
        }
        .contextMenu {
            queryResultRowMenu(
                hasAttachments: row.hasAttachments,
                onCopyDocument: { copyRowToClipboard(row) },
                onCopyId: { copyIdToClipboard(row) },
                onAddAttachment: { onAddAttachment?(row.originalJson) },
                onDeleteAttachment: { onDeleteAttachment?(row.originalJson) }
            )
        }
    }

    private func macOSHeaderView(columns: [String], cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(.headline, design: .monospaced))
                .frame(width: Self.rowNumberColumnWidth, alignment: .center)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            ForEach(columns, id: \.self) { columnName in
                Divider()

                Text(columnName)
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(width: cellWidth, alignment: .leading)
                    .background(Color(NSColor.windowBackgroundColor))
            }

            Divider()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            // Same divider style as data rows so the table reads as a
            // single grid rather than a floating header + isolated rows.
            Rectangle()
                .fill(Self.rowDividerColor)
                .frame(height: Self.rowDividerHeight)
        }
    }
    #endif

    // MARK: - iPadOS Table View

    #if os(iOS)
    /// Touch-friendly minimum column width on iPad. Larger than the
    /// macOS minimum so columns don't shrink below comfortable tap
    /// targets on a wide-but-still-finger-driven canvas.
    private static let iPadMinColumnWidth: CGFloat = 200

    private func iPadOSTableView(data: TableResultsData) -> some View {
        GeometryReader { geo in
            let columnCount = max(1, data.columns.count)
            let availableForColumns = max(0, geo.size.width - Self.rowNumberColumnWidth)
            let minTotalColumnWidth = CGFloat(columnCount) * Self.iPadMinColumnWidth
            // Fits → distribute evenly. Overflows → fall back to fixed
            // minimum width and let horizontal scroll handle it.
            let cellWidth = availableForColumns >= minTotalColumnWidth
                ? availableForColumns / CGFloat(columnCount)
                : Self.iPadMinColumnWidth
            let totalWidth = Self.rowNumberColumnWidth + CGFloat(columnCount) * cellWidth

            ScrollView([.horizontal, .vertical]) {
                // See macOS branch — VStack + trailing Spacer + minHeight
                // pins short tables to the top instead of letting SwiftUI
                // centre them vertically inside the viewport.
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(data.rows) { row in
                                iPadRowView(row: row, columns: data.columns, cellWidth: cellWidth)
                            }
                        } header: {
                            iPadHeaderView(columns: data.columns, cellWidth: cellWidth)
                        }
                    }
                    .frame(width: totalWidth, alignment: .leading)
                    .background(Color(UIColor.systemBackground))

                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // See macOS branch for the rationale — recreate the ScrollView
            // per page so stale scroll offsets and pinned-header layout
            // state from the previous page don't push the new page's
            // rows down inside the viewport.
            .id(currentPage)
        }
    }

    private func iPadRowView(row: TableResultRow, columns: [String], cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("\(row.rowIndex + 1)")
                .font(.system(.body, design: .monospaced))
                .frame(width: Self.rowNumberColumnWidth, alignment: .center)
                .padding(.vertical, 8)
                .background(copiedRowId == row.id ? Color.green.opacity(0.2) : Color.clear)

            ForEach(columns, id: \.self) { columnName in
                Divider()

                Group {
                    if let cellValue = row.cells[columnName] {
                        // NOTE: do NOT add `.textSelection(.enabled)`.
                        // It hosts a UITextView that swallows long-press
                        // and breaks the row's context menu on every data
                        // column. See QueryResultRowMenu.swift for context.
                        Text(cellValue.displayValue)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(width: cellWidth, alignment: .leading)
            }

            Divider()
        }
        .background(row.rowIndex % 2 == 0
            ? Color(UIColor.systemBackground)
            : Color(UIColor.secondarySystemBackground).opacity(0.3))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Self.rowDividerColor)
                .frame(height: Self.rowDividerHeight)
        }
        .onTapGesture(count: 2) {
            copyRowToClipboard(row)
        }
        .contextMenu {
            queryResultRowMenu(
                hasAttachments: row.hasAttachments,
                onCopyDocument: { copyRowToClipboard(row) },
                onCopyId: { copyIdToClipboard(row) },
                onAddAttachment: { onAddAttachment?(row.originalJson) },
                onDeleteAttachment: { onDeleteAttachment?(row.originalJson) }
            )
        }
    }

    private func iPadHeaderView(columns: [String], cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(.headline, design: .monospaced))
                .frame(width: Self.rowNumberColumnWidth, alignment: .center)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))

            ForEach(columns, id: \.self) { columnName in
                Divider()

                Text(columnName)
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(width: cellWidth, alignment: .leading)
                    .background(Color(UIColor.systemBackground))
            }

            Divider()
        }
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .bottom) {
            // Same divider style as data rows so the table reads as a
            // single grid rather than a floating header + isolated rows.
            Rectangle()
                .fill(Self.rowDividerColor)
                .frame(height: Self.rowDividerHeight)
        }
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
        setClipboardString(row.originalJson)
        // Trigger inspector callback — only on whole-document copy so
        // the Inspector content matches what just landed on the
        // clipboard. Copy _id intentionally skips this.
        onJsonSelected?(row.originalJson)
        flashCopiedIndicator(rowId: row.id)
    }

    private func copyIdToClipboard(_ row: TableResultRow) {
        // Falls back to the full document if `_id` is missing or the
        // JSON doesn't parse — better than a silent no-op when the
        // user explicitly chose Copy _id.
        let value = extractIdString(fromJSON: row.originalJson) ?? row.originalJson
        setClipboardString(value)
        flashCopiedIndicator(rowId: row.id)
    }

    /// Plays the green row-highlight confirmation. Shared between Copy
    /// Document and Copy _id so both actions feel the same.
    private func flashCopiedIndicator(rowId: UUID) {
        withAnimation {
            copiedRowId = rowId
        }
        // Cancel any prior pending reset so a fresh copy doesn't get
        // cleared early by a stale timer.
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation {
                copiedRowId = nil
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
            if let value {
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
