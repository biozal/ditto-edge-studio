//
//  MainStudioView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

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
                // Subscriptions Tab
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
                            onCancel: viewModel.cancelSubscription
                        )
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
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.selectedSubscription = DittoSubscription.new()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .tabItem {
                    Label("Subscriptions", systemImage: "document.on.document")
                }
                .tag(0)

                // Peers List Tab
                NavigationSplitView {
                    // First Column - Peer Groups
                    List(viewModel.peerGroups, id: \.self) { group in
                        Text(group)
                            .onTapGesture {
                                viewModel.selectedPeerGroup = group
                            }
                    }
                    .navigationTitle("Query")
                } content: {
                    // Second Column - Peers in Group
                    if let group = viewModel.selectedPeerGroup {
                        List(viewModel.peers, id: \.self) { peer in
                            Text(peer)
                                .onTapGesture {
                                    viewModel.selectedPeer = peer
                                }
                        }
                        .navigationTitle(group)
                    } else {
                        Text("Select a peer group")
                    }
                } detail: {
                    // Third Column - Peer Details
                    if let peer = viewModel.selectedPeer {
                        VStack {
                            Text("Peer Details")
                                .font(.title)
                            Text(peer)
                                .padding()
                        }
                    } else {
                        Text("Select a peer")
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
                            isMainStudioViewPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                #else
                    ToolbarItem(placement: .automatic) {
                        Button {
                            isMainStudioViewPresented = false
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
        var peerGroups = ["Connected", "Disconnected", "Pending"]
        var peers = ["peer1", "peer2", "peer3"]
        var selectedPeerGroup: String?
        var selectedPeer: String?

        // Health Metrics State
        var metricCategories = ["Sync", "Storage", "Network"]
        var metrics = ["metric1", "metric2", "metric3"]
        var selectedMetricCategory: String?
        var selectedMetric: String?

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
        
        func saveSubscription(name: String, query: String, args: String?, isActive: Bool) {
            // TODO: Save to database
            selectedSubscription = nil
        }
        
        func cancelSubscription() {
            selectedSubscription = nil
        }
    }
}
