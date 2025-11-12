//
//  SubscriptionsView.swift
//  Edge Studio
//
//  Modular view component for managing and displaying subscriptions
//

import SwiftUI

// MARK: - Subscriptions Sidebar View

struct SubscriptionsSidebarView: View {
    @Binding var subscriptions: [DittoSubscription]
    @Binding var isLoading: Bool
    @EnvironmentObject var appState: AppState

    var onEdit: (DittoSubscription) -> Void
    var onDelete: (DittoSubscription) async throws -> Void

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                Spacer()
                ProgressView("Loading Subscriptions...")
                    .progressViewStyle(.circular)
                Spacer()
            } else if subscriptions.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No apps have been added yet. Click the plus button in the bottom left corner to add your first subscription."
                    )
                )
                Spacer()
            } else {
                SubscriptionList(
                    subscriptions: $subscriptions,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    appState: appState
                )
            }
        }
    }
}
