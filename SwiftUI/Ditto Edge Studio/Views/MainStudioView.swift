//
//  MainStudioView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
import Combine
import SwiftUI

struct MainStudioView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MainStudioView.ViewModel
    @State private var selectedTab = 0
    
    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                SubscriptionsTabView(viewModel: $viewModel)
                    .tabItem {
                        Label(
                            "Subscriptions",
                            systemImage: "document.on.document"
                        )
                    }
                    .tag(0)
                    .environmentObject(appState)
                
                // Peers List Tab
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
                .tabItem {
                    Label(
                        "Query",
                        systemImage: "text.page.badge.magnifyingglass"
                    )
                }
                .tag(1)
                
                // Swift Data Tools Menu
                NavigationSplitView {
                    // First Column - Listing of Data Tools
                    List(viewModel.dittoToolsFeatures, id: \.self) { tool in
                        Text(tool)
                            .onTapGesture {
                                viewModel.selectedDataTool = tool
                            }
                    }
                    .navigationTitle("Tools")
                } detail: {
                    // Second Column - Metrics in Category
                    if let tool = viewModel.selectedDataTool {
                        Text(tool)
                    } else {
                        ContentUnavailableView(
                            "Select Tool",
                            systemImage: "exclamationmark.triangle.fill",
                            description: Text(
                                "Select a tool from the list on the left."
                            )
                        )
                    }
                }
                .tabItem {
                    Label("Tools", systemImage: "hammer.circle")
                }
                .tag(2)
                .navigationTitle(viewModel.selectedApp.name)
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await viewModel.closeSelectedApp()
                                isMainStudioViewPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
#else
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
    }
}
#Preview {
    MainStudioView(
        isMainStudioViewPresented: Binding<Bool>.constant(false),
        dittoAppConfig: DittoAppConfig.new()
    )
}

extension MainStudioView {
    @Observable
    @MainActor
    class ViewModel {
        var isLoading = false
        var selectedApp: DittoAppConfig
        
        // Subscriptions State
        var subscriptions: [DittoSubscription] = []
        var selectedSubscription: DittoSubscription?
        
        // Peers List State
        var queryHistory: [String] = []
        var queryFavorites: [String] = []
        var selectedQuery: String?
        
        // Health Metrics State
        var dittoToolsFeatures = ["Presence Viewer", "Peers List", "Presence Degration", "Hearbeat", "Disk Usage"]
        var metrics = ["metric1", "metric2", "metric3"]
        var selectedDataTool: String?
        var selectedMetric: String?
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            Task {
                subscriptions = await DittoManager.shared.dittoSubscriptions
            }
        }
        
        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
        
        func saveSubscription(name: String, query: String, args: String?, appState: DittoApp)
        {
            if var subscription = selectedSubscription {
                subscription.name = name
                subscription.query = query
                if let argsString = args {
                    do {
                        if let jsonData = argsString.data(using: .utf8),
                           let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            subscription.args = jsonDict
                        } else {
                            appState.setError(AppError.error(message: "Failed to parse subscription arguments"))
                        }
                    } catch {
                        appState.setError(AppError.error(message: "Invalid JSON format in subscription arguments: \(error.localizedDescription)"))
                    }
                } else {
                    subscription.args = nil
                }
                Task {
                    do {
                        try await DittoManager.shared.addDittoSubscription(subscription)
                        subscriptions = await DittoManager.shared.dittoSubscriptions
                    } catch {
                        appState.setError(error)
                    }
                    selectedSubscription = nil
                }
            }
        }
        
        func cancelSubscription() {
            selectedSubscription = nil
        }
    }
}
