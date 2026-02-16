import Foundation

/// Repository for managing query history with secure storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own history file)
/// - In-memory cache during session
/// - Write-through persistence to JSON cache files
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from {databaseId}_history.json
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to disk after every change
/// 4. Clear: Called when database closes → clears in-memory cache
actor HistoryRepository {
    static let shared = HistoryRepository()

    private let cacheService = SecureCacheService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedHistory: [DittoQueryHistory] = []
    private var currentDatabaseId: String?

    // Callback for UI updates
    private var onHistoryUpdate: (([DittoQueryHistory]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads query history for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of query history items
    /// - Throws: Error if load fails
    func loadHistory(for databaseId: String) async throws -> [DittoQueryHistory] {
        currentDatabaseId = databaseId

        // Load from cache file
        let cacheItems = try await cacheService.loadDatabaseHistory(databaseId)

        // Convert SecureCacheService.QueryHistoryItem to DittoQueryHistory
        let history = cacheItems.map { item in
            DittoQueryHistory(
                id: item._id,
                query: item.query,
                createdDate: item.createdDate
            )
        }

        // Update in-memory cache
        cachedHistory = history

        return history
    }

    /// Saves a query to history (write-through to disk)
    /// - Parameter history: Query history item to save
    /// - Throws: Error if save fails
    func saveQueryHistory(_ history: DittoQueryHistory) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadHistory() first")
        }

        do {
            // Check if query already exists in cache
            if let existingIndex = cachedHistory.firstIndex(where: { $0.query == history.query }) {
                // Update existing entry's date
                var updated = cachedHistory[existingIndex]
                updated.createdDate = Date().ISO8601Format()
                cachedHistory[existingIndex] = updated

                // Move to front (most recent)
                let item = cachedHistory.remove(at: existingIndex)
                cachedHistory.insert(item, at: 0)
            } else {
                // Add new entry at front
                cachedHistory.insert(history, at: 0)
            }

            // Persist to disk
            try await persistHistory(databaseId: databaseId)

            // Notify UI
            notifyHistoryUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Deletes a query from history
    /// - Parameter id: History item ID to delete
    /// - Throws: Error if delete fails
    func deleteQueryHistory(_ id: String) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Remove from in-memory cache
            cachedHistory.removeAll { $0.id == id }

            // Persist to disk
            try await persistHistory(databaseId: databaseId)

            // Notify UI
            notifyHistoryUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Clears all query history for current database
    /// - Throws: Error if clear fails
    func clearQueryHistory() async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Clear in-memory cache
            cachedHistory = []

            // Persist empty array to disk
            try await persistHistory(databaseId: databaseId)

            // Notify UI
            notifyHistoryUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache (called when database closes)
    func clearCache() {
        cachedHistory = []
        currentDatabaseId = nil
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnHistoryUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) {
        self.onHistoryUpdate = callback
    }

    // MARK: - Private Helpers
    /// Persists current in-memory cache to disk
    private func persistHistory(databaseId: String) async throws {
        // Convert DittoQueryHistory to SecureCacheService.QueryHistoryItem
        let cacheItems = cachedHistory.map { history in
            SecureCacheService.QueryHistoryItem(
                _id: history.id,
                query: history.query,
                createdDate: history.createdDate
            )
        }

        try await cacheService.saveDatabaseHistory(databaseId, history: cacheItems)
    }

    private func notifyHistoryUpdate() {
        onHistoryUpdate?(cachedHistory)
    }
}
