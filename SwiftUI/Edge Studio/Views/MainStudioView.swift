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
                SubscriptionsTabView(
                    isMainStudioViewPresented: $isMainStudioViewPresented,
                    dittoAppConfig: viewModel.selectedApp
                )
                .tabItem {
                    Label(
                        "Subscriptions",
                        systemImage: "arrow.trianglehead.2.clockwise"
                    )
                }
                .tag(0)
                .environmentObject(appState)
                // Data Store Tab
                ObserversTabView(
                    isMainStudioViewPresented: $isMainStudioViewPresented,
                    dittoAppConfig: viewModel.selectedApp
                )
                .tabItem {
                    Label(
                        "Observers",
                        systemImage: "eye"
                    )
                }
                .tag(1)
                .environmentObject(appState)
                
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                await viewModel.closeSelectedApp()
                                isMainStudioViewPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.large) // Make the button larger on iOS
                        }
                    }
                }
                #endif

                // Query Tab
                QueryTabView(
                    isMainStudioViewPresented: $isMainStudioViewPresented,
                    dittoAppConfig: viewModel.selectedApp
                )
                .tabItem {
                    Label(
                        "Query",
                        systemImage: "text.page.badge.magnifyingglass"
                    )
                }
                .tag(2)
                .environmentObject(appState)
                
                // Swift Data Tools Menu
                DittoToolsTabView(
                    isMainStudioViewPresented: $isMainStudioViewPresented,
                    dittoAppConfig: viewModel.selectedApp
                )
                .tabItem {
                    Label("Ditto Tools", systemImage: "hammer.circle")
                }
                .tag(3)
                .environmentObject(appState)
                .navigationTitle(viewModel.selectedApp.name)

                if viewModel.isMongoDBConnected {
                    // Swift Data Tools Menu
                    MongoTabView(
                        isMainStudioViewPresented: $isMainStudioViewPresented,
                        dittoAppConfig: viewModel.selectedApp
                    )
                    .tabItem {
                        Label("MongoDB", systemImage: "leaf")
                    }
                    .tag(4)
                    .environmentObject(appState)
                    .navigationTitle(viewModel.selectedApp.name)
                }
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
            ToolbarItem(id: "closeButton", placement: .primaryAction) {
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
        var isMongoDBConnected: Bool = false

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            Task {
                self.isMongoDBConnected = await MongoManager.shared.isConnected
            }
        }

        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}
