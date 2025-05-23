//
//  QueryTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/22/25.
//

import SwiftUI

struct QueryTabView: View {
    @Binding var viewModel: MainStudioView.ViewModel
    @Binding var isMainStudioViewPresented: Bool
    @EnvironmentObject private var appState: DittoApp

    var body: some View {
        NavigationSplitView {
            // First Column - history and favorites
            if viewModel.queryHistory.isEmpty
                && viewModel.queryFavorites.isEmpty
            {
                ContentUnavailableView(
                    "No Queries Available",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No queries have been ran or saved as favorites yet.  Create a query and run it to see history.  Mark a query as a favorite to save it for later."
                    )
                )

            } else {
                List(viewModel.queryHistory, id: \.self) { query in
                    Text(query)
                        .onTapGesture {
                            viewModel.selectedQuery = query
                        }
                }
                .navigationTitle("Query")
                #if os(macOS)
                    .navigationSplitViewColumnWidth(200)
                #endif
            }
        } detail: {
            // Second Column - Query History/Favorites
            // TODO switch this out for a list of queries
            if let query = viewModel.selectedQuery {
                VStack {
                    Text("Query Editor")
                        .font(.title)
                    Text(query)
                        .padding()
                }
            } else {
                ContentUnavailableView(
                    "TODO - create editor",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "I'm too lazy to create the query editor and query results view right now.  This is a placeholder."
                    )
                )
            }
        }
        .toolbar {
            #if os(iPadOS)
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            #endif
            #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            await viewModel.closeSelectedApp()
                            isMainStudioViewPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            #endif
        }
    }

}
