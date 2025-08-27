import DittoSwift
import Foundation

actor SubscriptionsRepository {
    static let shared = SubscriptionsRepository()
    
    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    
    // Store the callback inside the actor
    private var onSubscriptionsUpdate: (([DittoSubscription]) -> Void)?
    
    private init() { }
    
    func saveDittoSubscription(_ subscription: DittoSubscription) async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        let query =
        "INSERT INTO dittosubscriptions DOCUMENTS (:newSubscription) ON ID CONFLICT DO UPDATE"
        var arguments: [String: Any] = [
            "newSubscription": [
                "_id": subscription.id,
                "name": subscription.name,
                "query": subscription.query,
                "selectedApp_id": selectedAppConfig._id,
                "args": "",
            ]
        ]
        if let args = subscription.args {
            if var newSub = arguments["newSubscription"] as? [String: Any] {
                newSub["args"] = args
                arguments["newSubscription"] = newSub
            }
        }
        
        do {
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            
            // Setup the subscription now - need to make it mutable, register the subscription
            var sub = subscription
            sub.syncSubscription = try await dittoManager.dittoSelectedApp?.sync
                .registerSubscription(query: subscription.query)
            
            // Refresh subscriptions list after save
            try await refreshSubscriptions()
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func removeDittoSubscription(_ subscription: DittoSubscription) async throws {
        guard let ditto = await dittoManager.dittoLocal else {
            throw InvalidStateError(message: "No Ditto local database available")
        }
        
        let query = "DELETE FROM dittosubscriptions WHERE _id = :id"
        let argument = ["id": subscription.id]
        
        do {
            try await ditto.store.execute(
                query: query,
                arguments: argument
            )
            
            // Cancel the subscription if it exists
            if let syncSubscription = subscription.syncSubscription {
                syncSubscription.cancel()
            }
            
            // Refresh subscriptions list after removal
            try await refreshSubscriptions()
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func hydrateDittoSubscriptions() async throws -> [DittoSubscription] {
        guard let ditto = await dittoManager.dittoLocal,
              let id = await dittoManager.dittoSelectedAppConfig?._id else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        let query = "SELECT * FROM dittosubscriptions WHERE selectedApp_id = :selectedAppId"
        let arguments = ["selectedAppId": id]
        
        do {
            let results = try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            let subscriptions = results.items.compactMap {
                DittoSubscription($0.value)
            }
            
            // Register each subscription with Ditto sync
            var activeSubscriptions: [DittoSubscription] = []
            for subscription in subscriptions {
                var sub = subscription
                sub.syncSubscription = try await dittoManager.dittoSelectedApp?.sync
                    .registerSubscription(query: subscription.query)
                activeSubscriptions.append(sub)
            }
            
            // Call callback to update ViewModel
            onSubscriptionsUpdate?(activeSubscriptions)
            
            return activeSubscriptions
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    private func refreshSubscriptions() async throws {
        _ = try await hydrateDittoSubscriptions()
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func setOnSubscriptionsUpdate(_ callback: @escaping ([DittoSubscription]) -> Void) {
        self.onSubscriptionsUpdate = callback
    }
    
    func cancelAllSubscriptions() {
        // This will be called when closing the app to clean up subscriptions
        // Use Task to ensure cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performSubscriptionCleanup()
        }
    }
    
    private func performSubscriptionCleanup() {
        // The actual subscriptions will be cancelled by DittoManager when it stops sync
        onSubscriptionsUpdate?([])
    }
}
