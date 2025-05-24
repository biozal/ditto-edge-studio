//
//  SubscriptionTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/19/25.

import SwiftUI

struct SubscriptionsTabView: View {
    @Binding var viewModel: MainStudioView.ViewModel
    @Binding var isMainStudioViewPresented: Bool
    @EnvironmentObject private var appState: DittoApp
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
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
                        ) {
                            ForEach(viewModel.subscriptions, id: \.id) {
                                subscription in
                                Text(subscription.name)
                                    .onTapGesture {
                                        viewModel.selectedSubscription =
                                            subscription
                                    }
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
            .navigationSplitViewColumnWidth(250)
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
            .navigationSplitViewColumnWidth(300)
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

#Preview {
    SubscriptionsTabView(
        viewModel: .constant(
            MainStudioView.ViewModel(
                DittoAppConfig.new(),
            )
        ),
        isMainStudioViewPresented: .constant(true)
    )
    .environmentObject(DittoApp())
}
