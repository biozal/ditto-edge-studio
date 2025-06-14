//
//  SubscriptionsTabView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/11/25.
//

import SwiftUI

struct SubscriptionsTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: SubscriptionsTabView.ViewModel

    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                if viewModel.isLoading {
                    AnyView(
                        ProgressView("Loading Subscriptions...")
                            .progressViewStyle(.circular)
                    )
                } else if viewModel.subscriptions.isEmpty {
                    AnyView(
                        ContentUnavailableView(
                            "No Subscriptions",
                            systemImage:
                                "exclamationmark.triangle.fill",
                            description: Text(
                                "No apps have been added yet. Click the plus button above to add your first app."
                            )
                        )
                    )
                } else {
                    DittoSubscriptionList(
                        subscriptions: $viewModel.subscriptions,
                        onEdit: viewModel.showSubscriptionEditor,
                        onDelete: viewModel.deleteSubscription,
                        appState: appState
                    )
                }
            }
            .sheet(
                isPresented: $viewModel.isEditorPresented,
            ) {
                if let subscription = viewModel.selectedSubscription {
                    QueryArgumentEditor(
                        title: subscription.name.isEmpty
                        ? "New Subscription" : "Edit Subscription",
                        name: subscription.name,
                        query: subscription.query,
                        arguments: subscription.args ?? "",
                        onSave: viewModel.formSaveSubscription,
                        onCancel: viewModel.formCancel
                    )
                    .environmentObject(appState)
                }
            }
            Button(action: {
                viewModel.selectedSubscription = DittoSubscription.new()
                viewModel.isEditorPresented = true
            }) {
                Image(systemName: "plus")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .padding(4)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(24)
        }
    }
}

extension SubscriptionsTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false

        //used for editor
        var isEditorPresented = false

        // Subscriptions State
        var subscriptions: [DittoSubscription] = []
        var selectedSubscription: DittoSubscription?

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig

            Task {
                isLoading = true
                subscriptions = await DittoManager.shared.dittoSubscriptions
                isLoading = false
            }
        }

        func deleteSubscription(_ subscription: DittoSubscription) async throws
        {
            try await DittoManager.shared.removeDittoSubscription(subscription)
            subscriptions = await DittoManager.shared.dittoSubscriptions
        }

        func formCancel() {
            selectedSubscription = nil
            isEditorPresented = false
        }

        func formSaveSubscription(
            name: String,
            query: String,
            args: String?,
            appState: DittoApp
        ) {
            if var subscription = selectedSubscription {
                subscription.name = name
                subscription.query = query
                if let argsString = args {
                    subscription.args = argsString
                } else {
                    subscription.args = nil
                }
                Task {
                    do {
                        try await DittoManager.shared.saveDittoSubscription(
                            subscription
                        )
                        subscriptions = await DittoManager.shared
                            .dittoSubscriptions
                    } catch {
                        appState.setError(error)
                    }
                    selectedSubscription = nil
                }
            }
            isEditorPresented = false
        }

        func showSubscriptionEditor(_ subscription: DittoSubscription) {
            selectedSubscription = subscription
            isEditorPresented = true
        }
    }
}

#Preview {
    SubscriptionsTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    ).environmentObject(DittoApp())
}
