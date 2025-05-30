//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @State var viewModel: QueryTabView.ViewModel
    
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
                    //query button
                    Button {
                        Task {

                        }
                    } label: {
                        Image(systemName: "info.square")
                    }.disabled(true)
                    Button {
                        Task {

                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }.padding(.trailing, 8)
                        .disabled(true)
                }
                
                // Results view using full width
                if viewModel.resultsMode == "json" {
#if os(macOS)
                    ResultJsonTableView(items: $viewModel.jsonResults)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
                    ResultJsonViewer(resultText: $viewModel.jsonResults)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
                } else {
                    Text("TODO - Table Viewer")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
}

#Preview {
    QueryResultsView(viewModel: QueryTabView.ViewModel(DittoAppConfig.new()))
        
}
