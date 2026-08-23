import DittoSwift
import Foundation

/// Repository for managing observable subscriptions, persisted in the local store
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own observers in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to the local store
/// - **Note**: Live DittoStoreObserver instances are NOT persisted (only metadata)
///
/// **Security:**
/// - **Not encrypted at rest.** The `SQLCipher*` names throughout this codebase are
///   historical: no SQLCipher library is linked, so `PRAGMA key` is a silent no-op on
///   Apple's system SQLite and the file on disk begins with `SQLite format 3`. See
///   `docs/CREDENTIAL_STORAGE.md` — this is a recorded, accepted decision, not an
///   oversight.
/// - Indexed for fast queries by databaseId
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from SQLCipher
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to SQLCipher after every change
/// 4. Clear: Called when database closes → clears in-memory cache and cancels observers
actor ObservableRepository {
    static let shared = ObservableRepository()

    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedObservables: [DittoObservable] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onObservablesUpdate: (@MainActor @Sendable ([DittoObservable]) -> Void)?

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
            observable.isActive = row.isActive
            observable.lastUpdated = row.lastUpdated
            // Note: storeObserver is NOT restored (must be re-registered by caller)
            return observable
        }

        // Update in-memory cache and notify UI
        cachedObservables = observables
        await notifyObservablesUpdate()

        return observables
    }

    /// Saves an observable subscription (write-through to SQLCipher)
    /// - Parameters:
    ///   - observable: Observable to save
    ///   - databaseId: Database the observable belongs to, captured by the
    ///     caller at user-action time. The save is refused when the session has
    ///     since switched to a different database — otherwise a stale save
    ///     would persist under the wrong database and corrupt the newly
    ///     selected database's in-memory cache.
    /// - Throws: Error if save fails, or `InvalidStateError` for a stale session
    func saveDittoObservable(_ observable: DittoObservable, databaseId: String) async throws {
        guard let currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadObservers() first")
        }
        guard currentDatabaseId == databaseId else {
            throw InvalidStateError(
                message: "Stale session - database switched from \(databaseId) before the save completed"
            )
        }

        do {
            // Check the in-memory cache (authoritative for the session) instead of
            // issuing a full SQLCipher read on every save.
            let existingIndex = cachedObservables.firstIndex(where: { $0.id == observable.id })
            let row = SQLCipherService.ObservableRow(
                _id: observable.id,
                databaseId: databaseId,
                name: observable.name,
                query: observable.query,
                isActive: observable.isActive,
                lastUpdated: observable.lastUpdated ?? Date.now.ISO8601Format()
            )
            if existingIndex != nil {
                // Update existing observable
                try await sqlCipher.updateObservable(row)
            } else {
                // Insert new observable
                try await sqlCipher.insertObservable(row)
            }

            // The awaits above suspended the actor: a concurrent
            // `loadObservers(for:)` may have switched the session to a
            // different database. The persisted row is correctly keyed by the
            // explicit databaseId and may stay — but the shared cache and UI
            // now belong to the NEW session, so refuse to touch them.
            guard self.currentDatabaseId == databaseId else {
                throw InvalidStateError(
                    message: "Stale session - database switched from \(databaseId) before the save completed"
                )
            }

            if let existingIndex {
                // Update in-memory cache
                cachedObservables[existingIndex] = observable
            } else {
                // Add to in-memory cache
                cachedObservables.append(observable)
            }

            // Notify UI
            await notifyObservablesUpdate()

            Log.debug("Saved observable: \(observable.name)")
        } catch let error as InvalidStateError where error.isStaleSessionRefusal {
            // Expected race on database switch — the caller logs it. Don't
            // alert the user in the NEW session for a correctly refused write.
            Log.info("Observable save refused: \(error.message)")
            throw error
        } catch {
            Log.error("Failed to save observable: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Removes an observable subscription
    /// - Parameter observable: Observable to remove
    /// - Throws: Error if remove fails
    func removeDittoObservable(_ observable: DittoObservable) async throws {
        guard currentDatabaseId != nil else {
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
            await notifyObservablesUpdate()

            Log.debug("Removed observable: \(observable.name)")
        } catch {
            Log.error("Failed to remove observable: \(error)")
            await appState?.setError(error)
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

    func setOnObservablesUpdate(_ callback: @escaping @MainActor @Sendable ([DittoObservable]) -> Void) {
        onObservablesUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyObservablesUpdate() async {
        await onObservablesUpdate?(cachedObservables)
    }
}

// MARK: - Protocol Conformance

extension ObservableRepository: ObservableRepositoryProtocol {}
