import Foundation
import DittoSwift

/// Repository for managing observable subscriptions with secure storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own observers file)
/// - In-memory cache during session
/// - Write-through persistence to JSON cache files
/// - **Note**: Live DittoStoreObserver instances are NOT persisted (only metadata)
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from {databaseId}_observers.json
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to disk after every change
/// 4. Clear: Called when database closes → clears in-memory cache and cancels observers
actor ObservableRepository {
    static let shared = ObservableRepository()

    private let cacheService = SecureCacheService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedObservables: [DittoObservable] = []
    private var currentDatabaseId: String?

    // Callback for UI updates
    private var onObservablesUpdate: (([DittoObservable]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads observer metadata for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of observable metadata (without live observers)
    /// - Throws: Error if load fails
    func loadObservers(for databaseId: String) async throws -> [DittoObservable] {
        currentDatabaseId = databaseId

        // Load from cache file
        let cacheItems = try await cacheService.loadDatabaseObservers(databaseId)

        // Convert SecureCacheService.ObservableMetadata to DittoObservable
        let observables = cacheItems.map { item in
            var observable = DittoObservable(id: item._id)
            observable.name = item.name
            observable.query = item.query
            observable.args = item.args
            observable.isActive = item.isActive
            observable.lastUpdated = item.lastUpdated
            // Note: storeObserver is NOT restored (must be re-registered by caller)
            return observable
        }

        // Update in-memory cache
        cachedObservables = observables

        return observables
    }

    /// Saves an observable subscription (write-through to disk)
    /// - Parameter observable: Observable to save
    /// - Throws: Error if save fails
    func saveDittoObservable(_ observable: DittoObservable) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadObservers() first")
        }

        do {
            // Update or add to in-memory cache
            if let existingIndex = cachedObservables.firstIndex(where: { $0.id == observable.id }) {
                cachedObservables[existingIndex] = observable
            } else {
                cachedObservables.append(observable)
            }

            // Persist to disk
            try await persistObservables(databaseId: databaseId)

            // Notify UI
            notifyObservablesUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Removes an observable subscription
    /// - Parameter observable: Observable to remove
    /// - Throws: Error if remove fails
    func removeDittoObservable(_ observable: DittoObservable) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Cancel live observer if present
            observable.storeObserver?.cancel()

            // Remove from in-memory cache
            cachedObservables.removeAll { $0.id == observable.id }

            // Persist to disk
            try await persistObservables(databaseId: databaseId)

            // Notify UI
            notifyObservablesUpdate()

        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache and cancels all observers (called when database closes)
    func clearCache() {
        // Cancel all live observers
        for observable in cachedObservables {
            observable.storeObserver?.cancel()
        }

        cachedObservables = []
        currentDatabaseId = nil
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnObservablesUpdate(_ callback: @escaping ([DittoObservable]) -> Void) {
        self.onObservablesUpdate = callback
    }

    // MARK: - Private Helpers

    /// Persists current in-memory cache to disk (without live observers)
    private func persistObservables(databaseId: String) async throws {
        // Convert DittoObservable to SecureCacheService.ObservableMetadata
        // Note: storeObserver is NOT persisted
        let cacheItems = cachedObservables.map { observable in
            SecureCacheService.ObservableMetadata(
                _id: observable.id,
                name: observable.name,
                query: observable.query,
                args: observable.args,
                isActive: observable.isActive,
                lastUpdated: observable.lastUpdated ?? Date().ISO8601Format()
            )
        }

        try await cacheService.saveDatabaseObservers(databaseId, observers: cacheItems)
    }

    private func notifyObservablesUpdate() {
        onObservablesUpdate?(cachedObservables)
    }
}
