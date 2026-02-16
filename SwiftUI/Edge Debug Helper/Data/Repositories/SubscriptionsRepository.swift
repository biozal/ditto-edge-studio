import DittoSwift
import Foundation

/// Repository for managing subscription metadata with secure storage
///
/// **Storage Strategy:**
/// - Per-database isolation (each database has its own subscriptions file)
/// - In-memory cache during session
/// - Write-through persistence to JSON cache files
/// - **Note**: Live DittoSyncSubscription instances are NOT persisted (only metadata)
///
/// **Lifecycle:**
/// 1. Load: Called when database opens → loads from {databaseId}_subscriptions.json
/// 2. Cache: All operations update in-memory cache first
/// 3. Persist: Write-through to disk after every change
/// 4. Clear: Called when database closes → clears in-memory cache and cancels subscriptions
actor SubscriptionsRepository {
    static let shared = SubscriptionsRepository()

    private let dittoManager = DittoManager.shared
    private let cacheService = SecureCacheService.shared
    private var appState: AppState?

    // In-memory cache for current database session
    private var cachedSubscriptions: [DittoSubscription] = []
    private var currentDatabaseId: String?

    // Callback for UI updates
    private var onSubscriptionsUpdate: (([DittoSubscription]) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Loads subscription metadata for a specific database into memory
    /// - Parameter databaseId: Database identifier
    /// - Returns: Array of subscription metadata (without live sync subscriptions)
    /// - Throws: Error if load fails
    func loadSubscriptions(for databaseId: String) async throws -> [DittoSubscription] {
        currentDatabaseId = databaseId

        // Load from cache file
        let cacheItems = try await cacheService.loadDatabaseSubscriptions(databaseId)

        // Convert SecureCacheService.SubscriptionMetadata to DittoSubscription
        let subscriptions = cacheItems.map { item in
            var subscription = DittoSubscription(id: item._id)
            subscription.name = item.name
            subscription.query = item.query
            subscription.args = item.args
            // Note: syncSubscription is NOT restored (must be re-registered by caller)
            return subscription
        }

        // Update in-memory cache
        cachedSubscriptions = subscriptions

        return subscriptions
    }

    /// Saves a subscription (write-through to disk) and registers it with Ditto sync
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

            // Update or add to in-memory cache
            if let existingIndex = cachedSubscriptions.firstIndex(where: { $0.id == subscription.id }) {
                cachedSubscriptions[existingIndex] = sub
            } else {
                cachedSubscriptions.append(sub)
            }

            // Persist to disk
            try await persistSubscriptions(databaseId: databaseId)

            // Notify UI
            notifySubscriptionsUpdate()

        } catch {
            self.appState?.setError(error)
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

            // Remove from in-memory cache
            cachedSubscriptions.removeAll { $0.id == subscription.id }

            // Persist to disk
            try await persistSubscriptions(databaseId: databaseId)

            // Notify UI
            notifySubscriptionsUpdate()

        } catch {
            self.appState?.setError(error)
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
        self.onSubscriptionsUpdate = callback
    }

    // MARK: - Private Helpers

    /// Persists current in-memory cache to disk (without live sync subscriptions)
    private func persistSubscriptions(databaseId: String) async throws {
        // Convert DittoSubscription to SecureCacheService.SubscriptionMetadata
        // Note: syncSubscription is NOT persisted
        let cacheItems = cachedSubscriptions.map { subscription in
            SecureCacheService.SubscriptionMetadata(
                _id: subscription.id,
                name: subscription.name,
                query: subscription.query,
                args: subscription.args
            )
        }

        try await cacheService.saveDatabaseSubscriptions(databaseId, subscriptions: cacheItems)
    }

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
