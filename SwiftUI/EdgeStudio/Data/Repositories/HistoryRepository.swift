import Foundation

/// Repository for managing query history, persisted in the local store
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own history in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to the local store
///
/// **Security:**
/// - **Not encrypted at rest.** The `SQLCipher*` names throughout this codebase are
///   historical: no SQLCipher library is linked, so `PRAGMA key` is a silent no-op on
///   Apple's system SQLite and the file on disk begins with `SQLite format 3`. See
///   `docs/CREDENTIAL_STORAGE.md` — this is a recorded, accepted decision, not an
///   oversight.
/// - Indexed for fast queries (databaseId, createdDate DESC)
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from SQLCipher
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to SQLCipher after every change
/// 4. Clear: Called when database closes → clears in-memory cache
actor HistoryRepository {
    static let shared = HistoryRepository()

    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedHistory: [DittoQueryHistory] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onHistoryUpdate: (@MainActor @Sendable ([DittoQueryHistory]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads query history for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of query history items (most recent first)
    /// - Throws: Error if load fails
    func loadHistory(for databaseId: String) async throws -> [DittoQueryHistory] {
        currentDatabaseId = databaseId

        // Load from SQLCipher (ordered by createdDate DESC)
        let rows = try await sqlCipher.getHistory(databaseId: databaseId, limit: 1000)

        // Convert SQLCipherService.HistoryRow to DittoQueryHistory
        let history = rows.map { row in
            DittoQueryHistory(
                id: row._id,
                query: row.query,
                createdDate: row.createdDate
            )
        }

        // Update in-memory cache
        cachedHistory = history

        return history
    }

    /// Saves a query to history (write-through to SQLCipher)
    /// - Parameters:
    ///   - history: Query history item to save
    ///   - databaseId: Database the query was executed against, captured by the
    ///     caller at user-action time. The write is refused when the session has
    ///     since switched to a different database — otherwise a slow query on
    ///     database A that completes after the user switched to database B would
    ///     land in B's history and corrupt B's in-memory cache.
    /// - Throws: Error if save fails, or `InvalidStateError` for a stale session
    func saveQueryHistory(_ history: DittoQueryHistory, databaseId: String) async throws {
        guard let currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadHistory() first")
        }
        guard currentDatabaseId == databaseId else {
            throw InvalidStateError(
                message: "Stale session - database switched from \(databaseId) before the save completed"
            )
        }

        do {
            // Dedup against the in-memory cache (authoritative for the session) —
            // avoids a full SQLCipher round-trip on every query execution. The
            // cache removal is deferred until after the post-await re-guard
            // below: while these awaits are suspended the session may switch,
            // and the shared cache then belongs to the NEW database.
            let existingMatch = cachedHistory.first(where: { $0.query == history.query })
            if let existingMatch {
                try await sqlCipher.deleteHistory(id: existingMatch.id)
            }

            // Insert with current timestamp
            let createdDate = Date.now.ISO8601Format()
            let row = SQLCipherService.HistoryRow(
                _id: history.id,
                databaseId: databaseId,
                query: history.query,
                createdDate: createdDate
            )
            try await sqlCipher.insertHistory(row)

            // The awaits above suspended the actor: a concurrent
            // `loadHistory(for:)` may have switched the session to a
            // different database. The persisted row is correctly keyed by the
            // explicit databaseId and may stay — but the shared cache and UI
            // now belong to the NEW session, so refuse to touch them.
            guard self.currentDatabaseId == databaseId else {
                throw InvalidStateError(
                    message: "Stale session - database switched from \(databaseId) before the save completed"
                )
            }

            // Maintain most-recent-first ordering in memory — no DB reload needed.
            if let existingMatch {
                cachedHistory.removeAll { $0.id == existingMatch.id }
            }
            cachedHistory.insert(
                DittoQueryHistory(id: history.id, query: history.query, createdDate: createdDate),
                at: 0
            )

            // Notify UI
            await notifyHistoryUpdate()

            Log.debug("Saved query history: \(history.query.prefix(50))...")
        } catch let error as InvalidStateError where error.isStaleSessionRefusal {
            // Expected race on database switch — the caller logs it. Don't
            // alert the user in the NEW session for a correctly refused write.
            Log.info("History save refused: \(error.message)")
            throw error
        } catch {
            Log.error("Failed to save query history: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Deletes a query from history
    /// - Parameter id: History item ID to delete
    /// - Throws: Error if delete fails
    func deleteQueryHistory(_ id: String) async throws {
        guard currentDatabaseId != nil else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Delete from SQLCipher
            try await sqlCipher.deleteHistory(id: id)

            // Remove from in-memory cache
            cachedHistory.removeAll { $0.id == id }

            // Notify UI
            await notifyHistoryUpdate()

            Log.debug("Deleted query history: \(id)")
        } catch {
            Log.error("Failed to delete query history: \(error)")
            await appState?.setError(error)
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
            // Delete all from SQLCipher
            try await sqlCipher.deleteAllHistory(databaseId: databaseId)

            // Clear in-memory cache
            cachedHistory = []

            // Notify UI
            await notifyHistoryUpdate()

            Log.info("Cleared all query history for database: \(databaseId)")
        } catch {
            Log.error("Failed to clear query history: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache (called when database closes)
    func clearCache() {
        cachedHistory = []
        currentDatabaseId = nil
        Log.debug("HistoryRepository cache cleared")
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnHistoryUpdate(_ callback: @escaping @MainActor @Sendable ([DittoQueryHistory]) -> Void) {
        onHistoryUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifyHistoryUpdate() async {
        await onHistoryUpdate?(cachedHistory)
    }
}

// MARK: - Protocol Conformance

extension HistoryRepository: HistoryRepositoryProtocol {}
