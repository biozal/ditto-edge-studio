//
//  StoreExplorerContextMenuView.swift
//  Edge Studio
//

import SwiftUI

struct StoreExplorerContextMenuView: View {
    @Binding var collections: [DittoCollectionModel]
    @Binding var favorites: [DittoQueryHistory]
    @Binding var history: [DittoQueryHistory]
    @Binding var isHistoryExpanded: Bool
    @Binding var isFavoritesExpanded: Bool
    @Binding var selectedItem: SelectedItem
    @Binding var isLoading: Bool
    @State private var isCollectionsExpanded = true

    // Callbacks for actions
    var onSelectCollection: (DittoCollectionModel) -> Void
    var onSelectQuery: (String, String) -> Void  // query, uniqueID

    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Collections Section
                CollapsibleSection(
                    title: "Collections",
                    count: collections.count,
                    isExpanded: $isCollectionsExpanded
                ) {
                    collectionsContent
                }
                .padding(.bottom, isCollectionsExpanded ? 8 : 2)

                // Favorites Section
                CollapsibleSection(
                    title: "Favorites",
                    count: favorites.count,
                    isExpanded: $isFavoritesExpanded
                ) {
                    favoritesContent
                }
                .padding(.bottom, isFavoritesExpanded ? 8 : 2)

                // History Section
                CollapsibleSection(
                    title: "History",
                    count: history.count,
                    isExpanded: $isHistoryExpanded
                ) {
                    historyContent
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
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
    private var favoritesContent: some View {
        if favorites.isEmpty {
            Text("No favorites")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(favorites) { query in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(query.query)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .hoverableCard(isSelected: false)
                    .padding(.horizontal, 4)
                    .onTapGesture {
                        onSelectQuery(query.query, query.id)
                    }
                    #if os(macOS)
                        .contextMenu {
                            FavoriteQueryContextMenu(query: query, appState: appState)
                        }
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if isLoading {
            ProgressView("Loading...")
                .font(.system(size: 12))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        } else if history.isEmpty {
            Text("No history")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(history) { query in
                    HistoryCard(
                        query: query,
                        appState: appState,
                        onTap: {
                            onSelectQuery(query.query, query.id)
                        }
                    )
                }
            }
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
        collections: .constant([]),
        favorites: .constant([]),
        history: .constant([]),
        isHistoryExpanded: .constant(true),
        isFavoritesExpanded: .constant(true),
        selectedItem: .constant(.none),
        isLoading: .constant(false),
        onSelectCollection: { _ in },
        onSelectQuery: { _, _ in },
        appState: AppState()
    )
}