import Foundation

/// Repository for managing favorite queries with secure storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own favorites file)
/// - In-memory cache during session
/// - Write-through persistence to JSON cache files
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from {databaseId}_favorites.json
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to disk after every change
/// 4. Clear: Called when database closes → clears in-memory cache
actor FavoritesRepository {
    static let shared = FavoritesRepository()

    private let cacheService = SecureCacheService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedFavorites: [DittoQueryHistory] = []
    private var currentDatabaseId: String?

    // Callback for UI updates
    private var onFavoritesUpdate: (([DittoQueryHistory]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads favorite queries for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of favorite query items
    /// - Throws: Error if load fails
    func loadFavorites(for databaseId: String) async throws -> [DittoQueryHistory] {
        currentDatabaseId = databaseId

        // Load from cache file
        let cacheItems = try await cacheService.loadDatabaseFavorites(databaseId)

        // Convert SecureCacheService.QueryHistoryItem to DittoQueryHistory
        let favorites = cacheItems.map { item in
            DittoQueryHistory(
                id: item._id,
                query: item.query,
                createdDate: item.createdDate
            )
        }

        // Update in-memory cache
        cachedFavorites = favorites

        return favorites
    }

    /// Saves a query to favorites (write-through to disk)
    /// - Parameter favorite: Favorite query item to save
    /// - Throws: Error if save fails
    func saveFavorite(_ favorite: DittoQueryHistory) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadFavorites() first")
        }

        do {
            // Check if already exists (by query content)
            if cachedFavorites.contains(where: { $0.query == favorite.query }) {
                throw InvalidStateError(message: "Query already exists in favorites")
            }

            // Add to front of list
            cachedFavorites.insert(favorite, at: 0)

            // Persist to disk
            try await persistFavorites(databaseId: databaseId)

            // Notify UI
            notifyFavoritesUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Deletes a favorite query
    /// - Parameter id: Favorite item ID to delete
    /// - Throws: Error if delete fails
    func deleteFavorite(_ id: String) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Remove from in-memory cache
            cachedFavorites.removeAll { $0.id == id }

            // Persist to disk
            try await persistFavorites(databaseId: databaseId)

            // Notify UI
            notifyFavoritesUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache (called when database closes)
    func clearCache() {
        cachedFavorites = []
        currentDatabaseId = nil
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnFavoritesUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) {
        self.onFavoritesUpdate = callback
    }

    // MARK: - Private Helpers

    /// Persists current in-memory cache to disk
    private func persistFavorites(databaseId: String) async throws {
        // Convert DittoQueryHistory to SecureCacheService.QueryHistoryItem
        let cacheItems = cachedFavorites.map { favorite in
            SecureCacheService.QueryHistoryItem(
                _id: favorite.id,
                query: favorite.query,
                createdDate: favorite.createdDate
            )
        }

        try await cacheService.saveDatabaseFavorites(databaseId, favorites: cacheItems)
    }

    private func notifyFavoritesUpdate() {
        onFavoritesUpdate?(cachedFavorites)
    }
}
