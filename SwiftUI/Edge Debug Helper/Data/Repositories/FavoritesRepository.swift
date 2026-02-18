import Foundation

/// Repository for managing favorite queries with secure encrypted storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own favorites in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to encrypted database
///
/// **Security:**
/// - All favorites encrypted at rest with AES-256 (SQLCipher)
/// - Indexed for fast queries by databaseId
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from SQLCipher
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to SQLCipher after every change
/// 4. Clear: Called when database closes → clears in-memory cache
actor FavoritesRepository {
    static let shared = FavoritesRepository()

    private let sqlCipher = SQLCipherService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedFavorites: [DittoQueryHistory] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onFavoritesUpdate: (([DittoQueryHistory]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads favorite queries for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of favorite query items (most recent first)
    /// - Throws: Error if load fails
    func loadFavorites(for databaseId: String) async throws -> [DittoQueryHistory] {
        currentDatabaseId = databaseId

        // Load from SQLCipher (ordered by createdDate DESC)
        let rows = try await sqlCipher.getFavorites(databaseId: databaseId)

        // Convert SQLCipherService.FavoriteRow to DittoQueryHistory
        let favorites = rows.map { row in
            DittoQueryHistory(
                id: row._id,
                query: row.query,
                createdDate: row.createdDate
            )
        }

        // Update in-memory cache
        cachedFavorites = favorites

        return favorites
    }

    /// Saves a query to favorites (write-through to SQLCipher)
    /// - Parameter favorite: Favorite query item to save
    /// - Throws: Error if save fails
    func saveFavorite(_ favorite: DittoQueryHistory) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadFavorites() first")
        }

        do {
            // Check if already exists (by query content)
            let existing = try await sqlCipher.getFavorites(databaseId: databaseId)

            if existing.contains(where: { $0.query == favorite.query }) {
                throw InvalidStateError(message: "Query already exists in favorites")
            }

            // Insert into SQLCipher
            let row = SQLCipherService.FavoriteRow(
                _id: favorite.id,
                databaseId: databaseId,
                query: favorite.query,
                createdDate: Date().ISO8601Format()
            )
            try await sqlCipher.insertFavorite(row)

            // Reload cache from SQLCipher (to maintain proper ordering)
            cachedFavorites = try await loadFavorites(for: databaseId)

            // Notify UI
            notifyFavoritesUpdate()

            Log.debug("Saved favorite query: \(favorite.query.prefix(50))...")
        } catch {
            Log.error("Failed to save favorite: \(error)")
            appState?.setError(error)
            throw error
        }
    }

    /// Deletes a favorite query
    /// - Parameter id: Favorite item ID to delete
    /// - Throws: Error if delete fails
    func deleteFavorite(_ id: String) async throws {
        guard currentDatabaseId != nil else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Delete from SQLCipher
            try await sqlCipher.deleteFavorite(id: id)

            // Remove from in-memory cache
            cachedFavorites.removeAll { $0.id == id }

            // Notify UI
            notifyFavoritesUpdate()

            Log.debug("Deleted favorite: \(id)")
        } catch {
            Log.error("Failed to delete favorite: \(error)")
            appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache (called when database closes)
    func clearCache() {
        cachedFavorites = []
        currentDatabaseId = nil
        Log.debug("FavoritesRepository cache cleared")
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnFavoritesUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) {
        onFavoritesUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyFavoritesUpdate() {
        onFavoritesUpdate?(cachedFavorites)
    }
}
