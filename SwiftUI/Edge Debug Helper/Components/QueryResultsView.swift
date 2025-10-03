//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    var queryText: String = ""
    var hasExecutedQuery: Bool = false
    @State private var viewMode: QueryResultViewMode = .table
    @State private var isExporting = false
    @State private var resultsCount: Int = 0

    private var attachmentFields: [String] {
        AttachmentQueryParser.extractAttachmentFields(from: queryText)
    }

    private var collectionName: String? {
        // Extract collection name from query like "SELECT * FROM collection_name"
        print("[QueryResultsView] Extracting collection name from query: \(queryText)")
        let pattern = #"FROM\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: queryText, range: NSRange(queryText.startIndex..., in: queryText)),
              let range = Range(match.range(at: 1), in: queryText) else {
            print("[QueryResultsView] Failed to extract collection name from query")
            return nil
        }
        let extracted = String(queryText[range])
        print("[QueryResultsView] Extracted collection name: \(extracted)")
        return extracted
    }

    private func handleDelete(documentId: String, collection: String) {
        Task {
            do {
                try await QueryService.shared.deleteDocument(documentId: documentId, collection: collection)
                // Refresh results by removing the deleted item
                jsonResults.removeAll { jsonString in
                    guard let data = jsonString.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = json["_id"] as? String else {
                        return false
                    }
                    return id == documentId
                }
            } catch {
                print("[QueryResultsView] ERROR deleting document: \(error)")
            }
        }
    }

    init(jsonResults: Binding<[String]>, queryText: String = "", hasExecutedQuery: Bool = false) {
        _jsonResults = jsonResults
        self.queryText = queryText
        self.hasExecutedQuery = hasExecutedQuery
        resultsCount = _jsonResults.wrappedValue.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with view mode picker and clear button
            HStack {
                ViewModePicker(selectedMode: $viewMode)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)

                Spacer()

                Button {
                    jsonResults = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(jsonResults.isEmpty)
                .padding(.trailing, 16)
                .help("Clear all query results")
            }
            .background(Color.primary.opacity(0.05))

            Divider()

            // Content based on selected view mode
            Group {
                switch viewMode {
                case .table:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        viewMode: .table,
                        attachmentFields: attachmentFields,
                        collectionName: collectionName,
                        onDelete: handleDelete,
                        hasExecutedQuery: hasExecutedQuery
                    )
                case .raw:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        viewMode: .raw,
                        attachmentFields: attachmentFields,
                        hasExecutedQuery: hasExecutedQuery
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

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
    QueryResultsView(jsonResults: .constant(["{\"key\": \"value\"}"]))
}
