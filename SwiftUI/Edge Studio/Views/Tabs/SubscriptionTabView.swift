//
//  SubscriptionTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/19/25.

import SwiftUI

struct SubscriptionsTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: SubscriptionsTabView.ViewModel
    
    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig){
            self._isMainStudioViewPresented = isMainStudioViewPresented
            self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    
    var body: some View {
        NavigationSplitView {
            if viewModel.subscriptions.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No subscriptions have been added yet. Click the plus button in the upper right corner to add your first subscription."
                    )
                )
                .navigationTitle("Subscriptions")
            } else {
                List {
                    #if os(macOS)
                        Section(
                            header:
                                Text("Subscriptions")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
                                .padding(.top, 10)
                        ) {
                            ForEach(viewModel.subscriptions, id: \.id) {
                                subscription in
                                Text(subscription.name)
                                    .onTapGesture {
                                        viewModel.selectedSubscription =
                                            subscription
                                    }
                                    .font(.headline)
                            }
                        }
                    #else
                        ForEach(viewModel.subscriptions, id: \.id) {
                            subscription in
                            Text(subscription.name)
                                .onTapGesture {
                                    viewModel.selectedSubscription =
                                        subscription
                                }
                        }
                    #endif

                }
                .navigationTitle("Subscriptions")
            }
        } detail: {
            if let subscription = viewModel.selectedSubscription {
                SubscriptionEditorView(
                    subscription,
                    onSave: viewModel.saveSubscription,
                    onCancel: viewModel.cancelSubscription
                )
                .environmentObject(appState)
                .navigationTitle(subscription.name)

            } else {
                ContentUnavailableView(
                    "No Subscription Selected",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No subscription selected to edit.  Select an existing subscription or click the plus button in the upper right corner to add your first subscription."
                    )
                )
                .navigationTitle("Subscription Details")
            }
        }
        #if os(iOS)
            .navigationSplitViewColumnWidth(300)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.selectedSubscription = DittoSubscription.new()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        #else
            .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.closeSelectedApp()
                            isMainStudioViewPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.selectedSubscription = DittoSubscription.new()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        #endif
    }
}

extension SubscriptionsTabView {
    @Observable
    class ViewModel {
        let selectedApp: DittoAppConfig
        
        // Subscriptions State
        var subscriptions: [DittoSubscription] = []
        var selectedSubscription: DittoSubscription?
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            
            Task {
                subscriptions = await DittoManager.shared.dittoSubscriptions
            }
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
        
        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
        
    }
}

#Preview {
    SubscriptionsTabView(isMainStudioViewPresented: .constant(true),
                         dittoAppConfig: DittoAppConfig.new())
    .environmentObject(DittoApp())
}
