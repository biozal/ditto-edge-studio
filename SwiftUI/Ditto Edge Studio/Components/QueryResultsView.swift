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
        Picker("Results", selection: $viewModel.resultsMode) {
                                Text("JSON").tag("json")
                                Text("Table").tag("table")
                            }
                            .pickerStyle(.segmented)
        if viewModel.resultsMode == "json" {
            ResultJsonViewer(resultText: $viewModel.jsonResults)
        } else {
            Text("TODO - Table Viewer")
        }
    }
}

#Preview {
    QueryResultsView(viewModel: MainStudioView.ViewModel(DittoAppConfig.new()))
        
}
