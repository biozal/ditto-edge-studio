import DittoSwift
import Foundation

/// Repository for managing subscription metadata, persisted in the local store
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own subscriptions in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to the local store
/// - **Note**: Live DittoSyncSubscription instances are NOT persisted (only metadata)
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
/// 4. Clear: Called when database closes → clears in-memory cache and cancels subscriptions
actor SubscriptionsRepository {
    static let shared = SubscriptionsRepository()

    private let dittoManager = DittoManager.shared
    private var sqlCipher: SQLCipherService {
        SQLCipherContext.current
    }

    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedSubscriptions: [DittoSubscription] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onSubscriptionsUpdate: (@MainActor @Sendable ([DittoSubscription]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads subscription metadata for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of subscription metadata (without live sync subscriptions)
    /// - Throws: Error if load fails
    func loadSubscriptions(for databaseId: String) async throws -> [DittoSubscription] {
        currentDatabaseId = databaseId

        // Load from SQLCipher
        let rows = try await sqlCipher.getSubscriptions(databaseId: databaseId)

        // Re-register each subscription with the Ditto sync engine so data flows
        // immediately on app load. Without this, subscriptions appear in the UI but
        // the sync engine has no active handles and won't pull documents from peers.
        let ditto = await dittoManager.dittoSelectedApp
        var subscriptions: [DittoSubscription] = []
        for row in rows {
            var subscription = DittoSubscription(id: row._id)
            subscription.name = row.name
            subscription.query = row.query
            subscription.syncSubscription = try? ditto?.sync.registerSubscription(query: row.query)
            subscriptions.append(subscription)
        }

        // Update in-memory cache
        cachedSubscriptions = subscriptions

        return subscriptions
    }

    /// Saves a subscription (write-through to SQLCipher) and registers it with Ditto sync
    /// - Parameters:
    ///   - subscription: Subscription to save
    ///   - databaseId: Database the subscription belongs to, captured by the
    ///     caller at user-action time. The save is refused when the session has
    ///     since switched to a different database — otherwise a stale save would
    ///     persist under the wrong database AND register the subscription on the
    ///     newly selected database's live Ditto instance.
    /// - Throws: Error if save fails, or `InvalidStateError` for a stale session
    func saveDittoSubscription(_ subscription: DittoSubscription, databaseId: String) async throws {
        guard let currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadSubscriptions() first")
        }
        // Check BEFORE touching the sync engine: a stale save must not register
        // on the newly selected database's live Ditto instance.
        guard currentDatabaseId == databaseId else {
            throw InvalidStateError(
                message: "Stale session - database switched from \(databaseId) before the save completed"
            )
        }

        do {
            // Register the subscription with Ditto sync
            var sub = subscription
            let syncSub = try await dittoManager.dittoSelectedApp?.sync
                .registerSubscription(query: subscription.query)
            sub.syncSubscription = syncSub

            // Check the in-memory cache (authoritative for the session) instead of
            // issuing a full SQLCipher read on every save.
            let existingIndex = cachedSubscriptions.firstIndex(where: { $0.id == subscription.id })
            let row = SQLCipherService.SubscriptionRow(
                _id: subscription.id,
                databaseId: databaseId,
                name: subscription.name,
                query: subscription.query
            )
            do {
                if existingIndex != nil {
                    // Already exists — persist the updated name/query to SQLCipher
                    try await sqlCipher.updateSubscription(row)
                } else {
                    // Insert into SQLCipher
                    try await sqlCipher.insertSubscription(row)
                }
            } catch {
                // Persist failed — cancel the just-registered sync
                // subscription so the live registration doesn't leak (it
                // was never inserted into cachedSubscriptions, so
                // clearCache would never cancel it).
                syncSub?.cancel()
                throw error
            }

            // The awaits above suspended the actor: a concurrent session
            // switch re-stamps currentDatabaseId AND swaps dittoSelectedApp,
            // so the registration may have landed on the NEW database's live
            // sync engine. Cancel the just-registered subscription and refuse
            // before touching the shared cache or notifying the UI. (The
            // persisted row is correctly keyed by the explicit databaseId and
            // may stay.)
            guard self.currentDatabaseId == databaseId else {
                syncSub?.cancel()
                throw InvalidStateError(
                    message: "Stale session - database switched from \(databaseId) before the save completed"
                )
            }

            if let existingIndex {
                // Cancel the previous registration before swapping in the new
                // one — otherwise the replaced DittoSyncSubscription stays
                // live in the sync engine with no remaining reference.
                cachedSubscriptions[existingIndex].syncSubscription?.cancel()
                cachedSubscriptions[existingIndex] = sub
            } else {
                // Add to in-memory cache
                cachedSubscriptions.append(sub)
            }

            // Notify UI
            await notifySubscriptionsUpdate()

            Log.debug("Saved subscription: \(subscription.name)")
        } catch let error as InvalidStateError where error.isStaleSessionRefusal {
            // Expected race on database switch — the caller logs it. Don't
            // alert the user in the NEW session for a correctly refused write.
            Log.info("Subscription save refused: \(error.message)")
            throw error
        } catch {
            Log.error("Failed to save subscription: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Removes a subscription
    /// - Parameter subscription: Subscription to remove
    /// - Throws: Error if remove fails
    func removeDittoSubscription(_ subscription: DittoSubscription) async throws {
        guard currentDatabaseId != nil else {
            throw InvalidStateError(message: "No database selected")
        }

        do {
            // Cancel live sync subscription if present
            subscription.syncSubscription?.cancel()

            // Delete from SQLCipher
            try await sqlCipher.deleteSubscription(id: subscription.id)

            // Remove from in-memory cache
            cachedSubscriptions.removeAll { $0.id == subscription.id }

            // Notify UI
            await notifySubscriptionsUpdate()

            Log.debug("Removed subscription: \(subscription.name)")
        } catch {
            Log.error("Failed to remove subscription: \(error)")
            await appState?.setError(error)
            throw error
        }
    }

    /// Clears in-memory cache and cancels all subscriptions (called when database closes)
    func clearCache() {
        // Cancel all live sync subscriptions
        for subscription in cachedSubscriptions {
            subscription.syncSubscription?.cancel()
        }

        cachedSubscriptions = []
        currentDatabaseId = nil
        Log.debug("SubscriptionsRepository cache cleared")
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnSubscriptionsUpdate(_ callback: @escaping @MainActor @Sendable ([DittoSubscription]) -> Void) {
        onSubscriptionsUpdate = callback
    }

    /// Returns the current in-memory subscription cache without modifying it.
    /// Use after `saveDittoSubscription` calls to read the updated state on @MainActor.
    func getCachedSubscriptions() -> [DittoSubscription] {
        cachedSubscriptions
    }

    // MARK: - Private Helpers

    private func notifySubscriptionsUpdate() async {
        await onSubscriptionsUpdate?(cachedSubscriptions)
    }
}

// MARK: - Protocol Conformance

extension SubscriptionsRepository: SubscriptionsRepositoryProtocol {}
