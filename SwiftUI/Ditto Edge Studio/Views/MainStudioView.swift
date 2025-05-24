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
            // Subscription Tab
            TabView(selection: $selectedTab) {
                SubscriptionsTabView(viewModel: $viewModel, isMainStudioViewPresented: $isMainStudioViewPresented)
                    .tabItem {
                        Label(
                            "Subscriptions",
                            systemImage: "document.on.document"
                        )
                    }
                    .tag(0)
                    .environmentObject(appState)
                
                // Query Tab
                QueryTabView(viewModel: $viewModel, isMainStudioViewPresented: $isMainStudioViewPresented)
                    .tabItem {
                        Label(
                            "Query",
                            systemImage: "text.page.badge.magnifyingglass"
                        )
                    }
                .tag(1)
                .environmentObject(appState)

                
                // Swift Data Tools Menu
                DittoToolsTabView(viewModel: $viewModel, isMainStudioViewPresented: $isMainStudioViewPresented)
                    .tabItem {
                        Label("Ditto Tools", systemImage: "hammer.circle")
                    }
                .tag(2)
                .environmentObject(appState)
                
                .navigationTitle(viewModel.selectedApp.name)
            }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                HStack {
                    Image(systemName: "app")
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            }
            #endif
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
        
        // Health Metrics State
        var dittoToolsFeatures = ["Presence Viewer", "Permissions Health", "Presence Degration", "Disk Usage"]
        var selectedDataTool: String?
        var selectedMetric: String?
        
        // Query Editor
        var selectedQuery: String
        var jsonResults: String
        var resultsMode: String
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedQuery = ""
            self.jsonResults = "{}"
            self.resultsMode = "json"
            self.selectedApp = dittoAppConfig
            Task {
                subscriptions = await DittoManager.shared.dittoSubscriptions
                selectedQuery = subscriptions.first?.query ?? ""
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
