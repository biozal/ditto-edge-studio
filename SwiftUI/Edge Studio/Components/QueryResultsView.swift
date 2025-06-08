//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @Binding var resultsCount: Int
    @Binding var jsonResults: [String]
    @State private var isExporting = false

    var body: some View {
        VStack {
            // Picker centered with specific width
            HStack {
                Spacer()
                Button {
                    isExporting = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Export query results to JSON file")
                .padding(.trailing, 8)
                .padding(.top, 8)
                .disabled(resultsCount == 0)
                .fileExporter(
                    isPresented: $isExporting,
                    document: QueryResultsDocument(
                        jsonData: flattenJsonResults()
                    ),
                    contentType: .json,
                    defaultFilename: "query_results"
                ) { result in
                    switch result {
                    case .success(let url):
                        print("Saved to \(url)")
                    case .failure(let error):
                        print(
                            "Error saving file: \(error.localizedDescription)"
                        )
                    }
                }
            }

            ResultJsonViewer(
                resultText: $jsonResults,
                resultsCount: $resultsCount
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    QueryResultsView(
        resultsCount: .constant(0),
        jsonResults: .constant(["{\"key\": \"value\"}"])
    )
}
