//
//  QueryTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/22/25.
//

import SwiftUI
import Highlightr

struct QueryTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: QueryTabView.ViewModel
    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView {
            // First Column - collections, history, favorites
            QueryToolbarView(collections: $viewModel.collections,
                             favorites: $viewModel.favorites,
                             history: $viewModel.history,
                             toolbarMode: $viewModel.selectedToolbarMode,
                             selectedQuery: $viewModel.selectedQuery)
            #if os(macOS)
            .frame(minWidth: 250, idealWidth: 320, maxWidth: 400)
            #endif
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
                        onExecuteQuery: executeQuery
                    )

                    //bottom half
                    QueryResultsView(viewModel: viewModel)
                }
            #else
            VStack{
                //top half
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isLoading,
                    onExecuteQuery: executeQuery
              )
                .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)

                //bottom half
                QueryResultsView(viewModel: viewModel)
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedApp.name).font(.headline).bold()
            }
        }
        #endif
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

        //toolbar items
        var history: [DittoQueryHistory] = []
        var favorites: [DittoQueryHistory] = []
        var collections: [String] = []
        var selectedToolbarMode: String

        //query editor view
        var selectedQuery: String
        var executeModes: [String]
        var selectedExecuteMode: String

        //results view
        var resultsMode: String
        var jsonResults: [String]
        var resultsCount: Int
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            
            //sidebar section
            self.selectedToolbarMode = "collections"
            
            //query section
            self.selectedQuery = ""
            self.selectedExecuteMode = "Local"
            if dittoAppConfig.httpApiUrl == ""
                || dittoAppConfig.httpApiKey == ""
            {
                self.executeModes = ["Local"]

            } else {
                self.executeModes = ["Local", "HTTP"]
            }
            
            //query results section
            self.resultsCount = 0
            self.resultsMode = "json"
            self.jsonResults = ["{}"]
            
            //side bar data load
            Task {
                history = try await DittoManager.shared
                    .hydrateQueryHistory(updateHistory: {
                        self.history = $0
                    })
                
                collections  = try await DittoManager.shared
                    .hydrateCollections(updateCollections: {
                        self.collections = $0
                    })
                
                favorites = try await DittoManager.shared
                    .hydrateQueryFavorites(updateFavorites: {
                        self.favorites = $0
                    })
                        
                if collections.isEmpty {
                    let subscriptions = await DittoManager.shared.dittoSubscriptions
                    selectedQuery = subscriptions.first?.query ?? ""
                } else {
                    selectedQuery = "SELECT * FROM \(collections.first ?? "")"
                }
            }
        }

        func executeQuery(appState: DittoApp) async {
            isLoading = true
            do {
                if selectedExecuteMode == "Local" {
                    if let dittoResults = try await DittoManager.shared
                        .executeSelectedAppQuery(
                            query: selectedQuery
                        )
                    {
                        if resultsMode == "json" {
                            // Create an array of JSON strings from the results
                            let resultJsonStrings = dittoResults.compactMap {
                                item -> String? in
                                // Convert [String: Any?] to [String: Any] by removing nil values
                                let cleanedValue = item.value.compactMapValues {
                                    $0
                                }

                                do {
                                    let data = try JSONSerialization.data(
                                        withJSONObject: cleanedValue,
                                        options: [
                                                .prettyPrinted,
                                                .fragmentsAllowed,
                                                .sortedKeys,
                                                .withoutEscapingSlashes
                                        ]
                                     )
                                    return String(data: data, encoding: .utf8)
                                } catch {
                                    return nil
                                }
                            }

                            if !resultJsonStrings.isEmpty {
                                jsonResults = resultJsonStrings
                                resultsCount = resultJsonStrings.count
                            } else {
                                resultsCount = 0
                                jsonResults = ["No results"]
                            }
                        } else {
                            // TODO: put results into a table
                        }
                    } else {
                        resultsCount = 0
                        jsonResults = ["No results found"]
                    }
                } else {
                    jsonResults = try await DittoManager.shared
                        .executeSelectedAppQueryHttp(query: selectedQuery)
                    resultsCount = jsonResults.count
                }
                // Add query to history
                await addQueryToHistory(appState: appState)
            } catch {
                appState.setError(error)
            }
            isLoading = false
        }

        func addQueryToHistory(appState: DittoApp) async {
            if  !selectedQuery.isEmpty  && selectedQuery.count > 0 {
                let queryHistory = DittoQueryHistory(
                    id: UUID().uuidString,
                    query: selectedQuery,
                    createdDate: Date().ISO8601Format())
                do {
                    try await DittoManager.shared.saveQueryHistory(queryHistory)
                } catch{
                    appState.setError(error)
                }
            }
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
