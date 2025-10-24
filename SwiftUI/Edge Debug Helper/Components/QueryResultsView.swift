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
    @AppStorage("autoFetchAttachments") private var autoFetchAttachments = false

    private var attachmentFields: [String] {
        AttachmentQueryParser.extractAttachmentFields(from: queryText)
    }

    private var collectionName: String? {
        print("[QueryResultsView] Extracting collection name from query: \(queryText)")
        let extracted = DQLQueryParser.extractCollectionName(from: queryText)
        if let extracted = extracted {
            print("[QueryResultsView] Extracted collection name: \(extracted)")
        } else {
            print("[QueryResultsView] Failed to extract collection name from query")
        }
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

    private func handleDeleteAll() {
        guard let collection = collectionName else {
            print("[QueryResultsView] Cannot delete all: no collection name found")
            return
        }

        Task {
            do {
                // Extract all document IDs from results
                let documentIds = extractAllDocumentIds()
                guard !documentIds.isEmpty else {
                    print("[QueryResultsView] No document IDs found to delete")
                    return
                }

                print("[QueryResultsView] Deleting \(documentIds.count) documents from collection: \(collection)")

                // Create DELETE query with WHERE _id IN clause
                try await QueryService.shared.deleteDocuments(documentIds: documentIds, collection: collection)

                // Clear results after successful deletion
                jsonResults = []
            } catch {
                print("[QueryResultsView] ERROR deleting all documents: \(error)")
            }
        }
    }

    private func extractAllDocumentIds() -> [String] {
        var ids: [String] = []
        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["_id"] as? String else {
                continue
            }
            ids.append(id)
        }
        return ids
    }

    init(jsonResults: Binding<[String]>, queryText: String = "", hasExecutedQuery: Bool = false) {
        _jsonResults = jsonResults
        self.queryText = queryText
        self.hasExecutedQuery = hasExecutedQuery
        resultsCount = _jsonResults.wrappedValue.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with view mode picker and action buttons
            HStack {
                ViewModePicker(selectedMode: $viewMode)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)

                Spacer()

                // Delete All button
                Button {
                    handleDeleteAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Delete All")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(jsonResults.isEmpty || collectionName == nil)
                .help("Delete all documents in results from the database")

                // Clear button
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
                        hasExecutedQuery: hasExecutedQuery,
                        autoFetchAttachments: autoFetchAttachments
                    )
                case .raw:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        viewMode: .raw,
                        attachmentFields: attachmentFields,
                        hasExecutedQuery: hasExecutedQuery,
                        autoFetchAttachments: autoFetchAttachments
                    )
                case .map:
                    MapResultView(
                        jsonResults: $jsonResults,
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
