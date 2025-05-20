//
//  SubscriptionTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/19/25.

import SwiftUI

struct SubscriptionsTabView: View {
  @Binding var viewModel: MainStudioView.ViewModel

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
      } else {
        List(viewModel.subscriptions, id: \.id) { subscription in
          Text(subscription.name)
            .onTapGesture {
              viewModel.selectedSubscription = subscription
            }
        }
        .navigationTitle("Subscriptions")
      }
    } detail: {
      if let subscription = viewModel.selectedSubscription {
        SubscriptionEditorView(
          subscription,
          onSave: viewModel.saveSubscription,
          onCancel: viewModel.cancelSubscription)
      } else {
        ContentUnavailableView(
          "No Subscription Selected",
          systemImage: "exclamationmark.triangle.fill",
          description: Text(
            "No subscription selected to edit, or a new subscription to create.  Click the plus button in the upper right corner to add your first subscription."
          )
        )
      }
    }
    #if os(iOS)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            viewModel.selectedSubscription = DittoSubscription.new()
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    #else
      .toolbar {
        ToolbarItem(placement: .automatic) {
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
