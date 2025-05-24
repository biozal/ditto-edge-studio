//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @State var viewModel: MainStudioView.ViewModel
    
    var body: some View {
            VStack {
                // Picker centered with specific width
                HStack {
                    Spacer()
                    Picker("", selection: $viewModel.resultsMode) {
                        Text("JSON").tag("json")
                        Text("Table").tag("table")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Spacer()
                }
                
                // Results view using full width
                if viewModel.resultsMode == "json" {
                    ResultJsonViewer(resultText: $viewModel.jsonResults)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("TODO - Table Viewer")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
}

#Preview {
    QueryResultsView(viewModel: MainStudioView.ViewModel(DittoAppConfig.new()))
        
}
