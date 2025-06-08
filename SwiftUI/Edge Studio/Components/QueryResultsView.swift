//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @State var viewModel: QueryTabView.ViewModel
    @State private var isExporting = false
    
    var body: some View {
            VStack {
                // Picker centered with specific width
                HStack {
                    Spacer()
                    Picker("", selection: $viewModel.resultsMode) {
                        Text("JSON").tag("json")
                        Text("Table").tag("table")
                    }
                    .padding(.top, 8)
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Spacer()
                    Button {
                        isExporting = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Export query results to JSON file")
                    .padding(.trailing, 8)
                    .disabled(viewModel.resultsCount == 0)
                    .fileExporter(
                        isPresented: $isExporting,
                        document: QueryResultsDocument(jsonData: flattenJsonResults()),
                        contentType: .json,
                        defaultFilename: "query_results"
                    ) { result in
                        switch result {
                            case .success(let url):
                                print("Saved to \(url)")
                            case .failure(let error):
                                print("Error saving file: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Results view using full width
                if viewModel.resultsMode == "json" {
                    ResultJsonViewer(
                        resultText: $viewModel.jsonResults,
                        resultsCount: $viewModel.resultsCount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("TODO - Table Viewer")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        
        private func flattenJsonResults() -> String {
            // If it's a single JSON object, just return it as is
            if viewModel.jsonResults.count == 1 {
                return viewModel.jsonResults.first ?? "[]"
            }
            
            // If it's multiple objects, wrap them in an array
            return "[\n" + viewModel.jsonResults.joined(separator: ",\n") + "\n]"
        }
}

#Preview {
    QueryResultsView(viewModel: QueryTabView.ViewModel(DittoAppConfig.new()))
        
}
