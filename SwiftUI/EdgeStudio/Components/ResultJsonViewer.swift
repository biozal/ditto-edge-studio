import CodeEditor
import SwiftUI

struct ResultJsonViewer: View {
    @Binding var resultText: [String]

    // Internal state (used if no external bindings provided)
    @State private var internalCurrentPage = 1
    @State private var internalPageSize = 10
    @State private var isExporting = false

    // Optional external state for shared pagination
    var externalCurrentPage: Binding<Int>?
    var externalPageSize: Binding<Int>?
    var showPaginationControls = true
    var showExportButton = true

    /// Callback for JSON selection (opens in inspector)
    var onJsonSelected: ((String) -> Void)?

    /// Callback for adding an attachment to a document
    var onAddAttachment: ((String) -> Void)?

    /// Callback for deleting attachment field(s) from a document
    var onDeleteAttachment: ((String) -> Void)?

    /// Use external or internal state
    private var currentPage: Binding<Int> {
        externalCurrentPage ?? $internalCurrentPage
    }

    private var pageSize: Binding<Int> {
        externalPageSize ?? $internalPageSize
    }

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
        resultText.count
    }

    init(
        resultText: Binding<[String]>,
        externalCurrentPage: Binding<Int>? = nil,
        externalPageSize: Binding<Int>? = nil,
        showPaginationControls: Bool = true,
        showExportButton: Bool = true,
        onJsonSelected: ((String) -> Void)? = nil,
        onAddAttachment: ((String) -> Void)? = nil,
        onDeleteAttachment: ((String) -> Void)? = nil
    ) {
        _resultText = resultText
        self.externalCurrentPage = externalCurrentPage
        self.externalPageSize = externalPageSize
        self.showPaginationControls = showPaginationControls
        self.showExportButton = showExportButton
        self.onJsonSelected = onJsonSelected
        self.onAddAttachment = onAddAttachment
        self.onDeleteAttachment = onDeleteAttachment
    }

    /// Convenience initializer for static arrays
    init(resultText: [String]) {
        _resultText = .constant(resultText)
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(resultText.count) / Double(pageSize.wrappedValue))))
    }

    private var pagedItems: [String] {
        let start = (currentPage.wrappedValue - 1) * pageSize.wrappedValue
        let end = min(start + pageSize.wrappedValue, resultText.count)
        guard start < resultText.count else { return [] }
        return Array(resultText[start ..< end])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultsList(items: pagedItems, onJsonSelected: onJsonSelected, onAddAttachment: onAddAttachment, onDeleteAttachment: onDeleteAttachment)
            Spacer()

            if showPaginationControls || showExportButton {
                HStack {
                    Spacer()

                    if showPaginationControls {
                        PaginationControls(
                            totalCount: resultCount,
                            currentPage: currentPage,
                            pageCount: pageCount,
                            pageSize: pageSize,
                            pageSizes: pageSizes,
                            onPageChange: { newPage in
                                currentPage.wrappedValue = max(1, min(newPage, pageCount))
                            },
                            onPageSizeChange: { newSize in
                                pageSize.wrappedValue = newSize
                                currentPage.wrappedValue = 1
                            }
                        )
                        Spacer()
                    }

                    if showExportButton {
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
                            document: QueryResultsDocument(jsonData: flattenJsonResults()),
                            contentType: .json,
                            defaultFilename: "query_results"
                        ) { _ in }
                    }
                }
                .padding(.bottom, 10)
                .padding(.trailing, 20)
            }
        }
        .onChange(of: pageSize.wrappedValue) { _, _ in
            currentPage.wrappedValue = max(1, min(currentPage.wrappedValue, pageCount))
        }
        .onChange(of: resultText) { _, _ in
            currentPage.wrappedValue = 1
            if !pageSizes.contains(pageSize.wrappedValue) {
                pageSize.wrappedValue = pageSizes.first ?? 25
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

/// Separate component for the header
struct ResultsHeader: View {
    let count: Int

    var body: some View {
        Text("Results: \(count) items")
            .font(.headline)
            .padding(.horizontal)
    }
}

/// Separate component for the list
struct ResultsList: View {
    let items: [String]
    var onJsonSelected: ((String) -> Void)?
    var onAddAttachment: ((String) -> Void)?
    var onDeleteAttachment: ((String) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, jsonString in
                    ResultItem(
                        jsonString: jsonString,
                        onJsonSelected: onJsonSelected,
                        onAddAttachment: onAddAttachment,
                        onDeleteAttachment: onDeleteAttachment
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct ResultItem: View {
    let jsonString: String
    var onJsonSelected: ((String) -> Void)?
    var onAddAttachment: ((String) -> Void)?
    var onDeleteAttachment: ((String) -> Void)?
    @State private var isCopied = false
    @State private var attachments: [AttachmentInfo] = []
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(jsonString)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if isCopied {
                    FontAwesomeText(icon: StatusIcon.circleCheck, size: 14, color: .green)
                        .transition(.opacity)
                }
            }
            Divider()
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard()
            onJsonSelected?(jsonString)
        }
        .contextMenu {
            Button {
                copyToClipboard()
            } label: {
                Label("Copy Document", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                onAddAttachment?(jsonString)
            } label: {
                Label("Add Attachment...", systemImage: "paperclip")
            }
            Button {
                onDeleteAttachment?(jsonString)
            } label: {
                Label("Delete Attachment...", systemImage: "trash")
            }
            .disabled(attachments.isEmpty)
        }
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.05))
            .opacity(isCopied ? 1.0 : 0.0))
        .animation(.easeInOut(duration: 0.3), value: isCopied)
        .task(id: jsonString) {
            let detected = await Task.detached(priority: .utility) {
                AttachmentInfo.detectTokens(in: jsonString)
            }.value
            guard !Task.isCancelled else { return }
            attachments = detected
        }
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
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

        // Reset after delay — cancel any prior pending reset so a fresh copy
        // doesn't get cleared early by a stale timer.
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    ResultJsonViewer(resultText: .constant([
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
        "{\n  \"id\": 28,\n  \"name\": \"Omega\"\n}"
    ]))
    .frame(width: 400, height: 300)
}
