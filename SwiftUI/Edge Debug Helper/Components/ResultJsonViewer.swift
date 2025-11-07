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

    @State private var currentPage = 1
    @State private var pageSize = 10
    @State private var isExporting = false

    private var pageSizes: [Int] {
        switch resultCount {
        case 0...10: return [10]
        case 11...25: return [25]
        case 26...50: return [25, 50]
        case 51...100: return [25, 50, 100]
        case 101...200: return [25, 50, 100, 200]
        case 201...250: return [25, 50, 100, 200, 250]
        default: return [10, 25, 50, 100, 200, 250]
        }
    }
    private var resultCount: Int {
        resultText.count
    }

    init(resultText: Binding<[String]>) {
        self._resultText = resultText
    }

    // Convenience initializer for static arrays
    init(resultText: [String]) {
        self._resultText = .constant(resultText)
    }
    
    private var pageCount: Int {
        max(1, Int(ceil(Double(resultText.count) / Double(pageSize))))
    }

    private var pagedItems: [String] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, resultText.count)
        return Array(resultText[start..<end])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultsList(items: pagedItems)
            Spacer()
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
        .onChange(of: pageSize) { _, _ in
            currentPage = max(1, min(currentPage, pageCount))
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    ResultItem(jsonString: items[index])
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
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
        resultText: .constant([
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
        ])
    )
    .frame(width: 400, height: 300)
}
