//
//  DittoManager.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import Combine
import DittoSwift
import Foundation
import SwiftUI

// MARK: - DittoService
@MainActor class DittoManager: ObservableObject {
    var isStoreInitialized: Bool = false
    
    // MARK: local cache
    var dittoApp: DittoApp?
    var dittoLocal: Ditto?
    var localSubscription: DittoSyncSubscription?
    var localObserver: DittoStoreObserver?
    
    @Published var dittoAppConfigs: [DittoAppConfig] = []
    @Published var dittoSubscriptions: [DittoSubscription] = []
    
    // MARK: Selected App
    var dittoSelectedAppConfig: DittoAppConfig?
    var dittoSelectedApp: Ditto?
    
    private init() {}
    
    static var shared = DittoManager()
    
    func initializeStore(dittoApp: DittoApp) async throws {
        if !isStoreInitialized {
            // setup logging
            DittoLogger.enabled = true
            DittoLogger.minimumLogLevel = .debug
            
            //cache state for future use
            self.dittoApp = dittoApp
            
            // Create directory for local database
            let localDirectoryPath = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appendingPathComponent("ditto_appconfig")
            
            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: localDirectoryPath.path)
            {
                try FileManager.default.createDirectory(
                    at: localDirectoryPath,
                    withIntermediateDirectories: true
                )
            }
            
            //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
            dittoLocal = Ditto(
                identity: .onlinePlayground(
                    appID: dittoApp.appConfig.appId,
                    token: dittoApp.appConfig.authToken,
                    enableDittoCloudSync: false,
                    customAuthURL: URL(
                        string: dittoApp.appConfig.authUrl
                    )
                ),
                persistenceDirectory: localDirectoryPath
            )
            
            dittoLocal?.updateTransportConfig(block: { config in
                config.connect.webSocketURLs.insert(
                    dittoApp.appConfig.websocketUrl
                )
            })
            
            try dittoLocal?.disableSyncWithV3()
            try await setupLocalSubscription()
            try registerLocalObserver()
        }
    }
}

// MARK: Subscriptions
extension DittoManager {
    
    func setupLocalSubscription() async throws {
        if let ditto = dittoLocal {
            //set collection to only sync to local
            let syncScopes = [
                "dittoappconfigs": "LocalPeerOnly"
            ]
            try await ditto.store.execute(
                query:
                    "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
                arguments: ["syncScopes": syncScopes]
            )
            //setup subscription
            self.localSubscription = try ditto.sync.registerSubscription(
                query: """
                    SELECT *
                    FROM dittoappconfigs 
                    """
            )
            try ditto.startSync()
        }
    }
    
    func stopLocalSubscription() {
        if let subscriptionInstance = localSubscription {
            subscriptionInstance.cancel()
            dittoLocal?.stopSync()
        }
    }
}

// MARK: Register Observer - Live Query
extension DittoManager {
    
    func registerLocalObserver() throws {
        if let ditto = dittoLocal {
            localObserver = try ditto.store.registerObserver(
                query: """
                    SELECT *
                    FROM dittoappconfigs
                    ORDER BY name
                    """
            ) { [weak self] results in
                Task { @MainActor in
                    // Create new DittoAppConfig instances and update the published property
                    self?.dittoAppConfigs = results.items.compactMap {
                        DittoAppConfig(value: $0.value)
                    }
                }
            }
        }
    }
}

// MARK: Ditto App Config Operations
extension DittoManager {
    func updateDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                let query = "UPDATE dittoappconfigs SET name = :name, appId = :appId, authToken = :authToken, authUrl = :authUrl, websocketUrl = :websocketUrl, httpApiUrl = :httpApiUrl, httpApiKey = :httpApiKey WHERE _id = :_id"
                let arguments = [
                    "_id": appConfig._id,
                    "name": appConfig.name,
                    "appId": appConfig.appId,
                    "authToken": appConfig.authToken,
                    "authUrl": appConfig.authUrl,
                    "websocketUrl": appConfig.websocketUrl,
                    "httpApiUrl": appConfig.httpApiUrl,
                    "httpApiKey": appConfig.httpApiKey,
                ]
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments)
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
    
    func addDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                let query =
                "INSERT INTO dittoappconfigs INITIAL DOCUMENTS (:newConfig)"
                let arguments = [
                    "newConfig": [
                        "_id": appConfig._id,
                        "name": appConfig.name,
                        "appId": appConfig.appId,
                        "authToken": appConfig.authToken,
                        "authUrl": appConfig.authUrl,
                        "websocketUrl": appConfig.websocketUrl,
                        "httpApiUrl": appConfig.httpApiUrl,
                        "httpApiKey": appConfig.httpApiKey,
                    ]
                ]
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments
                )
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
}
// MARK: Ditto Selected App - Hydration
extension DittoManager {
    func hydrateDittoSelectedApp(_ appConfig: DittoAppConfig) async throws {
    
    }
        
}

// MARK: Ditto Selected App - Subscription Operations
extension DittoManager {
    func updateDittoSubscription(_ subscription: DittoSubscription) async throws {
        do {
            if let ditto = dittoLocal {
                var query = "UPDATE dittosubscriptions SET name = :name, query = :query, isActive = :isActive"
                var arguments: [String: Any] = [
                    "id": subscription.id,
                    "name": subscription.name,
                    "query": subscription.query,
                    "isActive": subscription.isActive
                ]
                
                if let args = subscription.args {
                    query += ", args = :args"
                    arguments["args"] = args
                }
                
                query += " WHERE _id = :id"
                
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments)
                
                removeDittoSubscription(subscription)
                try addDittoSubscriptionToCache(subscription)
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
    
    func addDittoSubscription(_ subscription: DittoSubscription) async throws {
        do {
            if let ditto = dittoLocal {
                let query = "INSERT INTO dittosubscriptions INITIAL DOCUMENTS (:newSubscription)"
                var arguments = [
                    "newSubscription": [
                        "_id": subscription.id,
                        "name": subscription.name,
                        "query": subscription.query,
                        "isActive": subscription.isActive,
                    ]
                ]
                if (subscription.args != nil) {
                    arguments["newSubscription"]?["args"] = subscription.args
                }
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments
                )
                //handle edge case where subscription exists in the cache
                removeDittoSubscription(subscription)
                try addDittoSubscriptionToCache(subscription)
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
    
    private func addDittoSubscriptionToCache(_ subscription: DittoSubscription) throws {
        if subscription.isActive {
            if let ditto = dittoSelectedApp {
                let syncSubscription = try ditto.sync.registerSubscription(
                    query: subscription.query,
                    arguments: subscription.args
                )
                // You might want to store this subscription somewhere or update your model
                var updatedSubscription = subscription
                updatedSubscription.syncSubscription = syncSubscription
                dittoSubscriptions.append(updatedSubscription)
            }
        } else {
            dittoSubscriptions.append(subscription)
        }
    }
        
    private func removeDittoSubscription(_ subscription: DittoSubscription) {
        //handle edge case where this is an add but it already exists
        if let sub = dittoSubscriptions.first(where: { $0.id == subscription.id }){
            if let dittoSub = sub.syncSubscription {
                dittoSub.cancel()
            }
            dittoSubscriptions.removeAll { $0.id == subscription.id }
        }
    }
        
}
