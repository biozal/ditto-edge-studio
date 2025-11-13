import Foundation

/// Service to track favorites in memory for quick lookups
@MainActor
class FavoritesService: ObservableObject {
    static let shared = FavoritesService()

    @Published private(set) var favoritedQueries: Set<String> = []

    private init() {}

    /// Check if a query is currently favorited
    func isFavorited(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favoritedQueries.contains(trimmedQuery)
    }

    /// Add a query to the favorites set
    func addToFavorites(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        favoritedQueries.insert(trimmedQuery)
    }

    /// Remove a query from the favorites set
    func removeFromFavorites(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        favoritedQueries.remove(trimmedQuery)
    }

    /// Load all favorites from repository into memory
    func loadFavorites(_ favorites: [DittoQueryHistory]) {
        favoritedQueries = Set(favorites.map { $0.query.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// Clear all favorites from memory
    func clear() {
        favoritedQueries.removeAll()
    }
}
