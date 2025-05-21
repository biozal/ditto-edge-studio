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
                
                // Health Metrics Tab
                NavigationSplitView {
                    // First Column - Metric Categories
                    List(viewModel.metricCategories, id: \.self) { category in
                        Text(category)
                            .onTapGesture {
                                viewModel.selectedMetricCategory = category
                            }
                    }
                    .navigationTitle("Tools")
                } content: {
                    // Second Column - Metrics in Category
                    if let category = viewModel.selectedMetricCategory {
                        List(viewModel.metrics, id: \.self) { metric in
                            Text(metric)
                                .onTapGesture {
                                    viewModel.selectedMetric = metric
                                }
                        }
                        .navigationTitle(category)
                    } else {
                        Text("Select a category")
                    }
                } detail: {
                    // Third Column - Metric Details
                    if let metric = viewModel.selectedMetric {
                        VStack {
                            Text("Metric Details")
                                .font(.title)
                            Text(metric)
                                .padding()
                        }
                    } else {
                        Text("Select a metric")
                    }
                }
                .tabItem {
                    Label("Tools", systemImage: "hammer.circle")
                }
                .tag(2)
            }
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
        var metricCategories = ["Sync", "Storage", "Network"]
        var metrics = ["metric1", "metric2", "metric3"]
        var selectedMetricCategory: String?
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
                    
                }
                Task {
                    do {
                        try await DittoManager.shared.addDittoSubscription(subscription )
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
