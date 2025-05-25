//
//  QueryTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/22/25.
//

import SwiftUI

struct QueryTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: QueryTabView.ViewModel
    
    init(isMainStudioViewPresented: Binding<Bool>,
         dittoAppConfig: DittoAppConfig) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
        
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
            #if os(macOS)
            // Second Column - Query History/Favorites
            // TODO switch this out for a list of queries
            VSplitView {
                //top half
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isLoading,
                    onExecuteQuery: executeQuery)
                        
                //bottom half
                QueryResultsView(viewModel: viewModel)
            }
            #else
            #endif

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
    
    func executeQuery() async {
        await viewModel.executeQuery(appState: appState)
    }
}

extension QueryTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false
        
        var queryHistory: [String] = []
        var queryFavorites: [String] = []
        
        var selectedQuery: String
        var jsonResults: String
        var resultsMode: String
        var executeModes: [String]
        var selectedExecuteMode: String
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedQuery = ""
            self.jsonResults = "{}"
            self.resultsMode = "json"
            self.selectedApp = dittoAppConfig
            
            //handle selectedExecuteMode
            self.selectedExecuteMode = "Local"
            if (dittoAppConfig.httpApiUrl == "" || dittoAppConfig.httpApiKey == "") {
                self.executeModes = ["Local"]

            } else {
                self.executeModes = ["Local", "HTTP"]
            }
            Task {
                let subscriptions = await DittoManager.shared.dittoSubscriptions
                selectedQuery = subscriptions.first?.query ?? ""
            }
        }
        
        func executeQuery(appState: DittoApp) async {
           isLoading = true
            do {
                if (selectedExecuteMode == "Local"){
                    if let dittoResults = try await DittoManager.shared.executeSelectedAppQuery(
                        query: selectedQuery){
                        if resultsMode == "json" {
                            let jsonData = try JSONSerialization.data(withJSONObject: dittoResults, options: [.prettyPrinted, .fragmentsAllowed])
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                jsonResults = jsonString
                            } else {
                                jsonResults = "{}"
                            }
                        } else {
                            //todo put results into a table
                        }
                    } else {
                        jsonResults = "{ message: \"No results\" }"
                    }
                } else {
                    //run the query over http
                }
            } catch {
                appState.setError(error)
            }
           isLoading = false
        }
        
        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}

#Preview {
    QueryTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
    .environmentObject(DittoApp())
}
