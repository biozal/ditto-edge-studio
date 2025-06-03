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
                SubscriptionsTabView(isMainStudioViewPresented: $isMainStudioViewPresented,
                                     dittoAppConfig: viewModel.selectedApp)
                    .tabItem {
                        Label(
                            "Subscriptions",
                            systemImage: "document.on.document"
                        )
                    }
                    .tag(0)
                    .environmentObject(appState)
                
                // Query Tab
                QueryTabView(isMainStudioViewPresented: $isMainStudioViewPresented,
                             dittoAppConfig: viewModel.selectedApp)
                    .tabItem {
                        Label(
                            "Query",
                            systemImage: "text.page.badge.magnifyingglass"
                        )
                    }
                .tag(1)
                .environmentObject(appState)
                
                // Query Tab
                ObservablesTabView(isMainStudioViewPresented: $isMainStudioViewPresented,
                             dittoAppConfig: viewModel.selectedApp)
                    .tabItem {
                        Label(
                            "Observables",
                            systemImage: "person.2.wave.2"
                        )
                    }
                .tag(2)
                .environmentObject(appState)
                
                // Import Data Tab
                ImportTabView(viewModel: $viewModel, isMainStudioViewPresented: $isMainStudioViewPresented)
                    .tabItem {
                        Label("Import", systemImage: "square.and.arrow.up")
                    }
                    .tag(3)
                    .environmentObject(appState)
                    
                // Swift Data Tools Menu
                DittoToolsTabView(isMainStudioViewPresented: $isMainStudioViewPresented,
                                  dittoAppConfig: viewModel.selectedApp)
                    .tabItem {
                        Label("Ditto Tools", systemImage: "hammer.circle")
                    }
                .tag(4)
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
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
        
        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}
