//
//  FavoriteButton.swift
//  Edge Debug Helper
//
//  Reusable favorite star button
//

import SwiftUI

struct FavoriteButton: View {
    let query: String
    let onAddToFavorites: () async -> Void
    let onRemoveFromFavorites: () async -> Void

    @StateObject private var favoritesService = FavoritesService.shared

    private var isFavorited: Bool {
        favoritesService.isFavorited(query)
    }

    var body: some View {
        Button {
            Task {
                if isFavorited {
                    await onRemoveFromFavorites()
                } else {
                    await onAddToFavorites()
                }
            }
        } label: {
            Image(systemName: isFavorited ? "star.fill" : "star")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help(isFavorited ? "Remove from favorites" : "Add current query to favorites")
    }
}

#Preview {
    FavoriteButton(
        query: "SELECT * FROM users",
        onAddToFavorites: { },
        onRemoveFromFavorites: { }
    )
}
