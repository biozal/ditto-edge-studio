import Foundation

/// Repository for managing favorite queries, persisted in the local store
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own favorites in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to the local store
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
/// 4. Clear: Called when database closes → clears in-memory cache
actor FavoritesRepository {
    static let shared = FavoritesRepository()

    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedFavorites: [DittoQueryHistory] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onFavoritesUpdate: (@MainActor @Sendable ([DittoQueryHistory]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads favorite queries for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of favorite query items (most recent first)
    /// - Throws: Error if load fails
    func loadFavorites(for databaseId: String) async throws -> [DittoQueryHistory] {
        currentDatabaseId = databaseId

        // Load from SQLCipher (ordered by createdDate DESC)
        let favorites = try await fetchFavorites(for: databaseId)

        // Update in-memory cache
        cachedFavorites = favorites

        return favorites
    }

    /// Reads favorites for a database WITHOUT stamping the shared session:
    /// `currentDatabaseId`, `cachedFavorites` and the UI callback are all
    /// left untouched. Use for databases that are NOT the active session —
    /// e.g. the QR-code display path, where stamping the shared session
    /// would break the active window's favorite saves (refused as stale) and
    /// push the wrong list into its UI.
    /// - Parameter databaseId: Database identifier to read favorites for
    /// - Returns: Array of favorite query items (most recent first)
    /// - Throws: Error if the read fails
    func favorites(for databaseId: String) async throws -> [DittoQueryHistory] {
        try await fetchFavorites(for: databaseId)
    }

    /// Saves a favorite into a database that is NOT the active session
    /// (QR-code import path). The write is keyed by the explicit
    /// `databaseId` and deliberately skips the stale-session guard, which
    /// exists to protect the ACTIVE session — this path never touches
    /// `currentDatabaseId`, `cachedFavorites` or the UI callback.
    /// - Parameters:
    ///   - favorite: Favorite query item to import
    ///   - databaseId: Database the favorite belongs to
    /// - Throws: Error if the write fails, or `InvalidStateError` when the
    ///   query is already a favorite (same duplicate policy as `saveFavorite`)
    func importFavorite(_ favorite: DittoQueryHistory, for databaseId: String) async throws {
        // Match saveFavorite's duplicate policy (by query content).
        let existing = try await sqlCipher.getFavorites(databaseId: databaseId)
        if existing.contains(where: { $0.query == favorite.query }) {
            throw InvalidStateError(message: "Query already exists in favorites")
        }

        let row = SQLCipherService.FavoriteRow(
            _id: favorite.id,
            databaseId: databaseId,
            query: favorite.query,
            createdDate: Date.now.ISO8601Format()
        )
        try await sqlCipher.insertFavorite(row)
        Log.debug("Imported favorite query: \(favorite.query.prefix(50))...")
    }

    /// Saves a query to favorites (write-through to SQLCipher)
    /// - Parameters:
    ///   - favorite: Favorite query item to save
    ///   - databaseId: Database the favorite belongs to, captured by the
    ///     caller at user-action time. The save is refused when the session has
    ///     since switched to a different database — otherwise a stale save
    ///     would persist under the wrong database and corrupt the newly
    ///     selected database's in-memory cache.
    /// - Throws: Error if save fails, or `InvalidStateError` for a stale session
    func saveFavorite(_ favorite: DittoQueryHistory, databaseId: String) async throws {
        guard let currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadFavorites() first")
        }
        // Capture BEFORE any await — and before the cache reload below, which
        // must go through `fetchFavorites` (NOT the public `loadFavorites`)
        // so it can't re-stamp `currentDatabaseId` back to the stale id.
        guard currentDatabaseId == databaseId else {
            throw InvalidStateError(
                message: "Stale session - database switched from \(databaseId) before the save completed"
            )
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
                createdDate: Date.now.ISO8601Format()
            )
            try await sqlCipher.insertFavorite(row)

            // The awaits above suspended the actor: a concurrent
            // `loadFavorites(for:)` may have switched the session to a
            // different database. Refuse to touch the shared cache or notify
            // the UI in that case (the insert above still landed in the
            // CORRECT database — it is keyed by the explicit parameter).
            guard self.currentDatabaseId == databaseId else {
                throw InvalidStateError(
                    message: "Stale session - database switched from \(databaseId) before the save completed"
                )
            }

            // Reload from SQLCipher (to maintain proper ordering) into a local
            // first: this fetch suspends too, and a session switch landing
            // inside it would otherwise assign the OLD database's list into
            // the cache the NEW session now owns, then notify its UI.
            let reloaded = try await fetchFavorites(for: databaseId)
            guard self.currentDatabaseId == databaseId else {
                throw InvalidStateError(
                    message: "Stale session - database switched from \(databaseId) before the save completed"
                )
            }
            cachedFavorites = reloaded

            // Notify UI
            await notifyFavoritesUpdate()

            Log.debug("Saved favorite query: \(favorite.query.prefix(50))...")
        } catch let error as InvalidStateError where error.isStaleSessionRefusal {
            // Expected race on database switch — the caller logs it. Don't
            // alert the user in the NEW session for a correctly refused write.
            Log.info("Favorite save refused: \(error.message)")
            throw error
        } catch {
            Log.error("Failed to save favorite: \(error)")
            await appState?.setError(error)
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
            await notifyFavoritesUpdate()

            Log.debug("Deleted favorite: \(id)")
        } catch {
            Log.error("Failed to delete favorite: \(error)")
            await appState?.setError(error)
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

    func setOnFavoritesUpdate(_ callback: @escaping @MainActor @Sendable ([DittoQueryHistory]) -> Void) {
        onFavoritesUpdate = callback
    }

    // MARK: - Private Helpers

    /// Reads favorites from SQLCipher WITHOUT stamping `currentDatabaseId`.
    /// `saveFavorite` uses this for its post-insert reload so a session switch
    /// that happened while the save was suspended can't be stamped back to the
    /// stale database id (which the public `loadFavorites(for:)` would do).
    private func fetchFavorites(for databaseId: String) async throws -> [DittoQueryHistory] {
        let rows = try await sqlCipher.getFavorites(databaseId: databaseId)
        return rows.map { row in
            DittoQueryHistory(
                id: row._id,
                query: row.query,
                createdDate: row.createdDate
            )
        }
    }

    private func notifyFavoritesUpdate() async {
        await onFavoritesUpdate?(cachedFavorites)
    }
}

// MARK: - Protocol Conformance

extension FavoritesRepository: FavoritesRepositoryProtocol {}

extension InvalidStateError {
    /// True for the stale-session refusal thrown by the repository save guards
    /// (`saveQueryHistory` / `saveFavorite` / `saveDittoObservable` /
    /// `saveDittoSubscription`) when a write completes after the user switched
    /// databases. That is an expected, correctly-handled race: callers should
    /// log it, not show an error alert in the NEW session.
    var isStaleSessionRefusal: Bool {
        message.hasPrefix("Stale session")
    }
}
