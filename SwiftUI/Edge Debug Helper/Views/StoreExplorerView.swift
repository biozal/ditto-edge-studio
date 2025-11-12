//
//  StoreExplorerContextMenuView.swift
//  Edge Studio
//

import SwiftUI

struct StoreExplorerContextMenuView: View {
    @Binding var subscriptions: [DittoSubscription]
    @Binding var observers: [DittoObservable]
    @Binding var collections: [DittoCollectionModel]
    @Binding var selectedItem: SelectedItem
    @State private var isSubscriptionsExpanded = true
    @State private var isObserversExpanded = true
    @State private var isCollectionsExpanded = true

    // Callbacks for actions
    var onSelectNetwork: () -> Void
    var onSelectSubscription: (DittoSubscription) -> Void
    var onEditSubscription: (DittoSubscription) async -> Void
    var onDeleteSubscription: (DittoSubscription) async throws -> Void
    var onAddSubscription: () -> Void
    var onEditObserver: (DittoObservable) async -> Void
    var onDeleteObserver: (DittoObservable) async throws -> Void
    var onStartObserver: (DittoObservable) async throws -> Void
    var onStopObserver: (DittoObservable) async throws -> Void
    var onSelectObserver: (DittoObservable) -> Void
    var onAddObserver: () -> Void
    var onSelectCollection: (DittoCollectionModel) -> Void
    var onRegisterCollection: () -> Void

    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Home Section
                homeItem

                Divider()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                // Action Buttons
                actionButtonsSection

                // Collections Section
                CollapsibleSection(
                    title: "Collections",
                    count: collections.count,
                    isExpanded: $isCollectionsExpanded
                ) {
                    collectionsContent
                } contextMenu: {
                    Button("Register Collection", systemImage: "folder.badge.plus") {
                        onRegisterCollection()
                    }
                }
                .padding(.bottom, isCollectionsExpanded ? 8 : 2)

                // Subscriptions Section
                CollapsibleSection(
                    title: "Subscriptions",
                    count: subscriptions.count,
                    isExpanded: $isSubscriptionsExpanded
                ) {
                    subscriptionsContent
                } contextMenu: {
                    Button("Add Subscription", systemImage: "arrow.trianglehead.2.clockwise") {
                        onAddSubscription()
                    }
                }
                .padding(.bottom, isSubscriptionsExpanded ? 8 : 2)

                // Observers Section
                CollapsibleSection(
                    title: "Observers",
                    count: observers.count,
                    isExpanded: $isObserversExpanded
                ) {
                    observersContent
                } contextMenu: {
                    Button("Add Observer", systemImage: "eye") {
                        onAddObserver()
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var subscriptionsContent: some View {
        if subscriptions.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Subscriptions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add subscriptions to sync data between peers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(subscriptions, id: \.id) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        isSelected: selectedItem == .subscription(subscription.id)
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectSubscription(subscription)
                        }
                        .contextMenu {
                            Button("Edit") {
                                Task {
                                    await onEditSubscription(subscription)
                                }
                            }
                            Button("Delete", role: .destructive) {
                                Task {
                                    do {
                                        try await onDeleteSubscription(subscription)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var observersContent: some View {
        if observers.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Observers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add observers to watch real-time data changes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(observers, id: \.id) { observer in
                    ObserverCard(
                        observer: observer,
                        isSelected: selectedItem == .observer(observer.id)
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectObserver(observer)
                        }
                        .contextMenu {
                            Button("Edit") {
                                Task {
                                    await onEditObserver(observer)
                                }
                            }

                            if observer.storeObserver == nil {
                                Button("Start Observing") {
                                    Task {
                                        do {
                                            try await onStartObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            } else {
                                Button("Stop Observing") {
                                    Task {
                                        do {
                                            try await onStopObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                Task {
                                    do {
                                        try await onDeleteObserver(observer)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var collectionsContent: some View {
        if collections.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "square.stack.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Collections")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Collections will appear when data is stored")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(collections, id: \.name) { collection in
                    CollectionCard(
                        collection: collection,
                        isSelected: selectedItem == .collection(collection.name)
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectCollection(collection)
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var homeItem: some View {
        HStack {
            // Home icon - aligned with CollapsibleSection chevrons
            Image(systemName: "house")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16)
                .foregroundColor(.secondary)

            // Content - aligned with CollapsibleSection titles
            Text("Home")
                .font(.system(.headline, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectNetwork()
        }
    }

    // MARK: - Action Buttons
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack {
            Button(action: toggleAllSections) {
                HStack(spacing: 4) {
                    Image(systemName: allSectionsCollapsed ? "plus.circle" : "minus.circle")
                        .font(.system(size: 12))
                    Text(allSectionsCollapsed ? "Expand All" : "Collapse All")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Computed Properties
    private var allSectionsCollapsed: Bool {
        !isCollectionsExpanded && !isSubscriptionsExpanded && !isObserversExpanded
    }

    // MARK: - Action Methods
    private func toggleAllSections() {
        let shouldExpand = allSectionsCollapsed
        withAnimation(.easeInOut(duration: 0.2)) {
            isCollectionsExpanded = shouldExpand
            isSubscriptionsExpanded = shouldExpand
            isObserversExpanded = shouldExpand
        }
    }
}

// MARK: - Collection Card Component
struct CollectionCard: View {
    let collection: DittoCollectionModel
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Collection icon - indented to align slightly left of header text
            Image(systemName: "square.stack.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14)
                .padding(.leading, 14)

            // Content
            Text(collection.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .hoverableCard(isSelected: isSelected)
    }
}

// MARK: - Observer Card Component
struct ObserverCard: View {
    let observer: DittoObservable
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status icon - indented to align slightly left of header text
            Image(systemName: observer.storeObserver != nil ? "eye.fill" : "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(observer.storeObserver != nil ? .green : .secondary)
                .frame(width: 14)
                .padding(.leading, 14)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(observer.name.isEmpty ? "Unnamed Observer" : observer.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if !observer.query.isEmpty {
                    Text(observer.query)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator
            if observer.isLoading == true {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Circle()
                    .fill(observer.storeObserver != nil ? .green : .secondary)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .hoverableCard(isSelected: isSelected)
    }
}

#Preview {
    StoreExplorerContextMenuView(
        subscriptions: .constant([]),
        observers: .constant([]),
        collections: .constant([]),
        selectedItem: .constant(.none),
        onSelectNetwork: { },
        onSelectSubscription: { _ in },
        onEditSubscription: { _ in },
        onDeleteSubscription: { _ in },
        onAddSubscription: { },
        onEditObserver: { _ in },
        onDeleteObserver: { _ in },
        onStartObserver: { _ in },
        onStopObserver: { _ in },
        onSelectObserver: { _ in },
        onAddObserver: { },
        onSelectCollection: { _ in },
        onRegisterCollection: { },
        appState: AppState()
    )
}