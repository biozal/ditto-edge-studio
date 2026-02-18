import DittoSwift
import Foundation

/// Repository for managing subscription metadata with secure encrypted storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own subscriptions in SQLCipher)
/// - In-memory cache during session
/// - Write-through persistence to encrypted database
/// - **Note**: Live DittoSyncSubscription instances are NOT persisted (only metadata)
///
/// **Security:**
/// - All subscription metadata encrypted at rest with AES-256 (SQLCipher)
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
    private let sqlCipher = SQLCipherService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedSubscriptions: [DittoSubscription] = []
    private var currentDatabaseId: String?

    /// Callback for UI updates
    private var onSubscriptionsUpdate: (([DittoSubscription]) -> Void)?

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

        // Convert SQLCipherService.SubscriptionRow to DittoSubscription
        let subscriptions = rows.map { row in
            var subscription = DittoSubscription(id: row._id)
            subscription.name = row.name
            subscription.query = row.query
            subscription.args = row.args
            // Note: syncSubscription is NOT restored (must be re-registered by caller)
            return subscription
        }

        // Update in-memory cache
        cachedSubscriptions = subscriptions

        return subscriptions
    }

    /// Saves a subscription (write-through to SQLCipher) and registers it with Ditto sync
    /// - Parameter subscription: Subscription to save
    /// - Throws: Error if save fails
    func saveDittoSubscription(_ subscription: DittoSubscription) async throws {
        guard let databaseId = currentDatabaseId else {
            throw InvalidStateError(message: "No database selected - call loadSubscriptions() first")
        }

        do {
            // Register the subscription with Ditto sync
            var sub = subscription
            let syncSub = try await dittoManager.dittoSelectedApp?.sync
                .registerSubscription(query: subscription.query)
            sub.syncSubscription = syncSub

            // Check if already exists
            let existing = try await sqlCipher.getSubscriptions(databaseId: databaseId)

            if existing.contains(where: { $0._id == subscription.id }) {
                // Already exists, just update the in-memory cache
                if let existingIndex = cachedSubscriptions.firstIndex(where: { $0.id == subscription.id }) {
                    cachedSubscriptions[existingIndex] = sub
                }
            } else {
                // Insert into SQLCipher
                let row = SQLCipherService.SubscriptionRow(
                    _id: subscription.id,
                    databaseId: databaseId,
                    name: subscription.name,
                    query: subscription.query,
                    args: subscription.args
                )
                try await sqlCipher.insertSubscription(row)

                // Add to in-memory cache
                cachedSubscriptions.append(sub)
            }

            // Notify UI
            notifySubscriptionsUpdate()

            Log.debug("Saved subscription: \(subscription.name)")
        } catch {
            Log.error("Failed to save subscription: \(error)")
            appState?.setError(error)
            throw error
        }
    }

    /// Removes a subscription
    /// - Parameter subscription: Subscription to remove
    /// - Throws: Error if remove fails
    func removeDittoSubscription(_ subscription: DittoSubscription) async throws {
        guard let databaseId = currentDatabaseId else {
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
            notifySubscriptionsUpdate()

            Log.debug("Removed subscription: \(subscription.name)")
        } catch {
            Log.error("Failed to remove subscription: \(error)")
            appState?.setError(error)
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

    /// Cancels all active subscriptions (legacy method for backward compatibility)
    func cancelAllSubscriptions() {
        // Use Task to ensure cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performSubscriptionCleanup()
        }
    }

    // MARK: - State Management

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnSubscriptionsUpdate(_ callback: @escaping ([DittoSubscription]) -> Void) {
        onSubscriptionsUpdate = callback
    }

    // MARK: - Private Helpers

    private func notifySubscriptionsUpdate() {
        onSubscriptionsUpdate?(cachedSubscriptions)
    }

    private func performSubscriptionCleanup() {
        // Cancel all subscriptions
        for subscription in cachedSubscriptions {
            subscription.syncSubscription?.cancel()
        }

        // Notify UI that subscriptions list is now empty
        onSubscriptionsUpdate?([])
    }
}
