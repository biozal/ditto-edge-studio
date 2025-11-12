//
//  QueryContextMenu.swift
//  Edge Debug Helper
//
//  Context menu for queries with favorites support
//

import SwiftUI

struct QueryContextMenu: View {
    let query: String
    let appState: AppState
    var onAddToFavorites: (() async -> Void)?
    var onRemoveFromFavorites: (() async -> Void)?
    var additionalActions: (() -> AnyView)?

    @State private var isFavorited: Bool = false

    var body: some View {
        Group {
            if isFavorited {
                Button {
                    Task {
                        await onRemoveFromFavorites?()
                        isFavorited = false
                    }
                } label: {
                    Label("Remove from Favorites", systemImage: "star.slash")
                        .labelStyle(.titleAndIcon)
                }
            } else {
                Button {
                    Task {
                        await onAddToFavorites?()
                        isFavorited = true
                    }
                } label: {
                    Label("Add to Favorites", systemImage: "star")
                        .labelStyle(.titleAndIcon)
                }
            }

            // Additional actions provided by caller
            if let additionalActions = additionalActions {
                additionalActions()
            }
        }
        .onAppear {
            isFavorited = FavoritesService.shared.isFavorited(query)
        }
        .onChange(of: query) { _, _ in
            isFavorited = FavoritesService.shared.isFavorited(query)
        }
    }
}

// Convenience wrapper for history items
struct HistoryQueryContextMenu: View {
    let query: DittoQueryHistory
    let appState: AppState

    var body: some View {
        QueryContextMenu(
            query: query.query,
            appState: appState,
            onAddToFavorites: {
                do {
                    try await FavoritesRepository.shared.saveFavorite(query)
                    FavoritesService.shared.addToFavorites(query.query)
                } catch {
                    appState.setError(error)
                }
            },
            onRemoveFromFavorites: {
                do {
                    try await FavoritesRepository.shared.removeFavoriteByQuery(query: query.query)
                    FavoritesService.shared.removeFromFavorites(query.query)
                } catch {
                    appState.setError(error)
                }
            },
            additionalActions: {
                AnyView(
                    Button {
                        Task {
                            do {
                                try await HistoryRepository.shared.deleteQueryHistory(query.id)
                            } catch {
                                appState.setError(error)
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                )
            }
        )
    }
}

// Convenience wrapper for subscription items
struct SubscriptionQueryContextMenu: View {
    let subscription: DittoSubscription
    let appState: AppState
    let onDelete: () async throws -> Void

    var body: some View {
        QueryContextMenu(
            query: subscription.query,
            appState: appState,
            onAddToFavorites: {
                do {
                    let favorite = DittoQueryHistory(
                        id: UUID().uuidString,
                        query: subscription.query,
                        createdDate: Date().ISO8601Format()
                    )
                    try await FavoritesRepository.shared.saveFavorite(favorite)
                    FavoritesService.shared.addToFavorites(subscription.query)
                } catch {
                    appState.setError(error)
                }
            },
            onRemoveFromFavorites: {
                do {
                    try await FavoritesRepository.shared.removeFavoriteByQuery(query: subscription.query)
                    FavoritesService.shared.removeFromFavorites(subscription.query)
                } catch {
                    appState.setError(error)
                }
            },
            additionalActions: {
                AnyView(
                    Button {
                        Task {
                            do {
                                try await onDelete()
                            } catch {
                                appState.setError(error)
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                )
            }
        )
    }
}

// Convenience wrapper for favorite items (remove only)
struct FavoriteQueryContextMenu: View {
    let query: DittoQueryHistory
    let appState: AppState

    var body: some View {
        Button {
            Task {
                do {
                    try await FavoritesRepository.shared.deleteFavorite(query.id)
                    FavoritesService.shared.removeFromFavorites(query.query)
                } catch {
                    appState.setError(error)
                }
            }
        } label: {
            Label("Remove from Favorites", systemImage: "star.slash")
                .labelStyle(.titleAndIcon)
        }
    }
}
