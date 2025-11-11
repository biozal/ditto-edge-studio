//
//  ResultJsonViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import CodeEditor
import SwiftUI

struct ResultJsonViewer: View {
    @Binding var resultText: [String]
    let parsedItems: [[String: Any]]   // Pre-parsed from parent
    let allKeys: [String]               // Pre-computed from parent
    let viewMode: QueryResultViewMode
    let attachmentFields: [String]
    var collectionName: String?
    var onDelete: ((String, String) -> Void)?
    var hasExecutedQuery: Bool = false
    var autoFetchAttachments: Bool = false

    // Pagination state - can be provided as bindings or use default state
    @Binding var currentPage: Int
    @Binding var pageSize: Int

    @State private var isExporting = false

    private var pageSizes: [Int] {
        switch resultCount {
        case 0...10: return [10]
        case 11...25: return [10, 25]
        case 26...50: return [10, 25, 50]
        case 51...100: return [10, 25, 50, 100]
        case 101...250: return [10, 25, 50, 100, 250]
        default: return [10, 25, 50, 100, 250]
        }
    }
    private var resultCount: Int {
        resultText.count
    }

    init(
        resultText: Binding<[String]>,
        parsedItems: [[String: Any]],
        allKeys: [String],
        currentPage: Binding<Int>,
        pageSize: Binding<Int>,
        viewMode: QueryResultViewMode = .raw,
        attachmentFields: [String] = [],
        collectionName: String? = nil,
        onDelete: ((String, String) -> Void)? = nil,
        hasExecutedQuery: Bool = false,
        autoFetchAttachments: Bool = false
    ) {
        self._resultText = resultText
        self.parsedItems = parsedItems
        self.allKeys = allKeys
        self._currentPage = currentPage
        self._pageSize = pageSize
        self.viewMode = viewMode
        self.attachmentFields = attachmentFields
        self.collectionName = collectionName
        self.onDelete = onDelete
        self.hasExecutedQuery = hasExecutedQuery
        self.autoFetchAttachments = autoFetchAttachments
    }

    // Convenience initializer for static arrays (e.g., previews)
    init(resultText: [String], viewMode: QueryResultViewMode = .raw, attachmentFields: [String] = []) {
        self._resultText = .constant(resultText)
        self.parsedItems = []
        self.allKeys = []
        self._currentPage = .constant(1)
        self._pageSize = .constant(10)
        self.viewMode = viewMode
        self.attachmentFields = attachmentFields
        self.collectionName = nil
        self.onDelete = nil
        self.autoFetchAttachments = false
    }
    
    private var pageCount: Int {
        max(1, Int(ceil(Double(resultText.count) / Double(pageSize))))
    }

    private var pagedItems: [String] {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !resultText.isEmpty else { return [] }
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, resultText.count)
        guard start < end && start < resultText.count else { return [] }

        let result = Array(resultText[start..<end])

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 10 {
            print("⚠️ PERFORMANCE: pagedItems took \(String(format: "%.1f", elapsed))ms for page size \(pageSize)")
        }

        return result
    }

    private var pagedParsedItems: [[String: Any]] {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !parsedItems.isEmpty else { return [] }
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, parsedItems.count)
        guard start < end && start < parsedItems.count else { return [] }

        let result = Array(parsedItems[start..<end])

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 10 {
            print("⚠️ PERFORMANCE: pagedParsedItems took \(String(format: "%.1f", elapsed))ms for page size \(pageSize)")
        }

        return result
    }

    private var globalRowOffset: Int {
        (currentPage - 1) * pageSize
    }

    var body: some View {
        let bodyStartTime = CFAbsoluteTimeGetCurrent()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let pagedItemsComputed = pagedItems
        let pagedParsedItemsComputed = pagedParsedItems

        let elapsed = (CFAbsoluteTimeGetCurrent() - bodyStartTime) * 1000
        print("[\(timestamp)] 📊 ResultJsonViewer.body START - pagedItems computed in \(String(format: "%.1f", elapsed))ms - items: \(pagedItemsComputed.count)")

        return VStack(alignment: .leading, spacing: 0) {
            // Main content area based on view mode
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        switch viewMode {
                        case .table:
                            ResultTableView(
                                items: pagedItemsComputed,
                                parsedItems: pagedParsedItemsComputed,
                                allKeys: allKeys,
                                attachmentFields: attachmentFields,
                                onDelete: collectionName != nil && onDelete != nil ? { docId, _ in
                                    onDelete?(docId, collectionName!)
                                } : nil,
                                hasExecutedQuery: hasExecutedQuery,
                                autoFetchAttachments: autoFetchAttachments,
                                globalRowOffset: globalRowOffset
                            )
                            .id("\(currentPage)-\(pageSize)")  // Force view recreation only when pagination changes
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        case .raw:
                            ResultsList(items: pagedItemsComputed, hasExecutedQuery: hasExecutedQuery)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        case .map:
                            EmptyView() // Map view is handled by MapResultView in QueryResultsView
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        }
                    }
                }
            }

            // Footer with pagination and export
            HStack {
                Spacer()
                PaginationControls(
                    totalCount: resultCount,
                    currentPage: $currentPage,
                    pageCount: pageCount,
                    pageSize: $pageSize,
                    pageSizes: pageSizes,
                    onPageChange: { newPage in
                        self.currentPage = max(1, min(newPage, pageCount))
                    },
                    onPageSizeChange: { newSize in
                        self.pageSize = newSize
                        self.currentPage = 1
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
            .padding(.bottom, 10)
            .padding(.trailing, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: pageSize) { oldValue, newValue in
            let startTime = CFAbsoluteTimeGetCurrent()
            print("🔄 Page size changed from \(oldValue) to \(newValue)")

            currentPage = max(1, min(currentPage, pageCount))

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("⏱️ Page size change handler took \(String(format: "%.1f", elapsed))ms")
        }
        .onChange(of: resultText) { _, _ in
            currentPage = 1
            if !pageSizes.contains(pageSize) {
                pageSize = pageSizes.first ?? 25
            }
        }
    }
    
    private func flattenJsonResults() -> String {
        // If it's a single JSON object, just return it as is
        if resultText.count == 1 {
            return resultText.first ?? "[]"
        }
        // If it's multiple objects, wrap them in an array
        return "[\n" + resultText.joined(separator: ",\n") + "\n]"
    }
}

// Separate component for the header
struct ResultsHeader: View {
    let count: Int

    var body: some View {
        Text("Results: \(count) items")
            .font(.headline)
            .padding(.horizontal)
    }
}

// Separate component for the list
struct ResultsList: View {
    let items: [String]
    var hasExecutedQuery: Bool = false

    var body: some View {
        let bodyStartTime = CFAbsoluteTimeGetCurrent()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] 🏁 ResultsList.body START - building string for \(items.count) items, hasExecutedQuery: \(hasExecutedQuery)")

        // Handle empty state properly
        if items.isEmpty {
            if !hasExecutedQuery {
                // No query executed yet
                return AnyView(
                    Text("Run a query for results")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
            } else {
                // Query executed but no results - show empty brackets
                return AnyView(
                    Text("[]")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
            }
        }

        // Check if this is a single scalar value (like COUNT result)
        // Don't wrap in brackets
        if items.count == 1 {
            let item = items[0].trimmingCharacters(in: .whitespacesAndNewlines)
            // Check if it's just a number or simple scalar (not JSON object/array)
            if !item.hasPrefix("{") && !item.hasPrefix("[") {
                let textView = Text(item)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                let elapsed = (CFAbsoluteTimeGetCurrent() - bodyStartTime) * 1000
                let endTimestamp = ISO8601DateFormatter().string(from: Date())
                print("[\(endTimestamp)] 🏁 ResultsList.body END (scalar) - total: \(String(format: "%.1f", elapsed))ms")

                return AnyView(textView)
            }
        }

        // Build the entire JSON string as one text block for proper text selection
        let jsonString = buildJsonString()

        let stringBuilt = CFAbsoluteTimeGetCurrent()
        print("[\(timestamp)] 📊 ResultsList string built - \(jsonString.count) chars")

        let textView = Text(jsonString)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        let elapsed = (CFAbsoluteTimeGetCurrent() - bodyStartTime) * 1000
        let endTimestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(endTimestamp)] 🏁 ResultsList.body END - total: \(String(format: "%.1f", elapsed))ms")

        return AnyView(textView)
    }

    private func buildJsonString() -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if items.isEmpty {
            return "[]"
        }

        // PERFORMANCE: Pre-allocate capacity for better string building performance
        // Estimate ~500 chars per item on average
        var result = ""
        result.reserveCapacity(items.count * 500)

        result.append("[\n")
        for (index, item) in items.enumerated() {
            // Indent each item
            let lines = item.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                result.append("  ")
                result.append(String(line))
                result.append("\n")
            }
            if index < items.count - 1 {
                // Remove last newline and add comma
                result.removeLast()
                result.append(",\n")
            }
        }
        result.append("]")

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[\(timestamp)] ⚠️ buildJsonString took \(String(format: "%.1f", elapsed))ms for \(items.count) items, \(result.count) chars")

        return result
    }
}

struct ResultItem: View {
    let jsonString: String
    @State private var isCopied = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(jsonString)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
            Divider()
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard()
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
                .opacity(isCopied ? 1.0 : 0.0)
        )
        .animation(.easeInOut(duration: 0.3), value: isCopied)
    }

    private func copyToClipboard() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
        #else
            UIPasteboard.general.string = jsonString
        #endif

        // Show feedback
        withAnimation {
            isCopied = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    ResultJsonViewer(
        resultText: [
            "{\n  \"id\": 1,\n  \"name\": \"Test\"\n}",
            "{\n  \"id\": 2,\n  \"name\": \"Sample\"\n}",
            "{\n  \"id\": 3,\n  \"name\": \"Example\"\n}",
            "{\n  \"id\": 4,\n  \"name\": \"Demo\"\n}",
            "{\n  \"id\": 5,\n  \"name\": \"Alpha\"\n}",
            "{\n  \"id\": 6,\n  \"name\": \"Beta\"\n}",
            "{\n  \"id\": 7,\n  \"name\": \"Gamma\"\n}",
            "{\n  \"id\": 8,\n  \"name\": \"Delta\"\n}",
            "{\n  \"id\": 9,\n  \"name\": \"Epsilon\"\n}",
            "{\n  \"id\": 10,\n  \"name\": \"Zeta\"\n}",
            "{\n  \"id\": 11,\n  \"name\": \"Eta\"\n}",
            "{\n  \"id\": 12,\n  \"name\": \"Theta\"\n}",
            "{\n  \"id\": 13,\n  \"name\": \"Iota\"\n}",
            "{\n  \"id\": 14,\n  \"name\": \"Kappa\"\n}",
            "{\n  \"id\": 15,\n  \"name\": \"Lambda\"\n}",
            "{\n  \"id\": 16,\n  \"name\": \"Mu\"\n}",
            "{\n  \"id\": 17,\n  \"name\": \"Nu\"\n}",
            "{\n  \"id\": 18,\n  \"name\": \"Xi\"\n}",
            "{\n  \"id\": 19,\n  \"name\": \"Omicron\"\n}",
            "{\n  \"id\": 20,\n  \"name\": \"Pi\"\n}",
            "{\n  \"id\": 21,\n  \"name\": \"Rho\"\n}",
            "{\n  \"id\": 22,\n  \"name\": \"Sigma\"\n}",
            "{\n  \"id\": 23,\n  \"name\": \"Tau\"\n}",
            "{\n  \"id\": 24,\n  \"name\": \"Upsilon\"\n}",
            "{\n  \"id\": 25,\n  \"name\": \"Phi\"\n}",
            "{\n  \"id\": 26,\n  \"name\": \"Chi\"\n}",
            "{\n  \"id\": 27,\n  \"name\": \"Psi\"\n}",
            "{\n  \"id\": 28,\n  \"name\": \"Omega\"\n}",
        ]
    )
    .frame(width: 400, height: 300)
}
