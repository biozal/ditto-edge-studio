import DittoSwift
import Foundation

/// Repository for managing observable subscriptions with secure encrypted storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own observers in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to encrypted database
/// - **Note**: Live DittoStoreObserver instances are NOT persisted (only metadata)
///
/// **Security:**
/// - All observable metadata encrypted at rest with AES-256 (SQLCipher)
/// - Indexed for fast queries by databaseId
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from SQLCipher
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to SQLCipher after every change
/// 4. Clear: Called when database closes → clears in-memory cache and cancels observers
actor ObservableRepository {
    static let shared = ObservableRepository()

    private let sqlCipher = SQLCipherService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedObservables: [DittoObservable] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onObservablesUpdate: (([DittoObservable]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads observer metadata for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of observable metadata (without live observers)
    /// - Throws: Error if load fails
    func loadObservers(for databaseId: String) async throws -> [DittoObservable] {
        currentDatabaseId = databaseId

        // Load from SQLCipher
        let rows = try await sqlCipher.getObservables(databaseId: databaseId)

        // Convert SQLCipherService.ObservableRow to DittoObservable
        let observables = rows.map { row in
            var observable = DittoObservable(id: row._id)
            observable.name = row.name
            observable.query = row.query
            observable.args = row.args
            observable.isActive = row.isActive
            observable.lastUpdated = row.lastUpdated
            // Note: storeObserver is NOT restored (must be re-registered by caller)
            return observable
        }

        // Update in-memory cache
        cachedObservables = observables

        return observables
    }

    /// Saves an observable subscription (write-through to SQLCipher)
    /// - Parameter observable: Observable to save
    /// - Throws: Error if save fails
    func saveDittoObservable(_ observable: DittoObservable) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadObservers() first")
        }

        do {
            // Check if already exists
            let existing = try await sqlCipher.getObservables(databaseId: databaseId)

            if existing.contains(where: { $0._id == observable.id }) {
                // Update existing observable
                let row = SQLCipherService.ObservableRow(
                    _id: observable.id,
                    databaseId: databaseId,
                    name: observable.name,
                    query: observable.query,
                    args: observable.args,
                    isActive: observable.isActive,
                    lastUpdated: observable.lastUpdated ?? Date().ISO8601Format()
                )
                try await sqlCipher.updateObservable(row)

                // Update in-memory cache
                if let existingIndex = cachedObservables.firstIndex(where: { $0.id == observable.id }) {
                    cachedObservables[existingIndex] = observable
                }
            } else {
                // Insert new observable
                let row = SQLCipherService.ObservableRow(
                    _id: observable.id,
                    databaseId: databaseId,
                    name: observable.name,
                    query: observable.query,
                    args: observable.args,
                    isActive: observable.isActive,
                    lastUpdated: observable.lastUpdated ?? Date().ISO8601Format()
                )
                try await sqlCipher.insertObservable(row)

                // Add to in-memory cache
                cachedObservables.append(observable)
            }

            // Notify UI
            notifyObservablesUpdate()

            Log.debug("Saved observable: \(observable.name)")
        } catch {
            Log.error("Failed to save observable: \(error)")
            appState?.setError(error)
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

            // Delete from SQLCipher
            try await sqlCipher.deleteObservable(id: observable.id)

            // Remove from in-memory cache
            cachedObservables.removeAll { $0.id == observable.id }

            // Notify UI
            notifyObservablesUpdate()

            Log.debug("Removed observable: \(observable.name)")
        } catch {
            Log.error("Failed to remove observable: \(error)")
            appState?.setError(error)
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
        Log.debug("ObservableRepository cache cleared")
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnObservablesUpdate(_ callback: @escaping ([DittoObservable]) -> Void) {
        onObservablesUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyObservablesUpdate() {
        onObservablesUpdate?(cachedObservables)
    }
}
