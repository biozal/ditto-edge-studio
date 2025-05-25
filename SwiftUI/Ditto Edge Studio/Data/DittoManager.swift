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
import ObjectiveC

// MARK: - DittoService
actor DittoManager: ObservableObject {
    var isStoreInitialized: Bool = false

    // MARK: local cache
    var dittoApp: DittoApp?
    var dittoLocal: Ditto?
    var localAppConfigSubscription: DittoSyncSubscription?

    var localObserver: DittoStoreObserver?
    @Published var dittoAppConfigs: [DittoAppConfig] = []

    // MARK: Selected App
    var dittoSelectedAppConfig: DittoAppConfig?
    var dittoSelectedApp: Ditto?
    @Published var dittoSubscriptions: [DittoSubscription] = []

    private init() {}

    static var shared = DittoManager()

    func initializeStore(dittoApp: DittoApp) async throws {
        do {
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
                if !FileManager.default.fileExists(
                    atPath: localDirectoryPath.path
                ) {
                    try FileManager.default.createDirectory(
                        at: localDirectoryPath,
                        withIntermediateDirectories: true
                    )
                }

                //validate that the dittoConfig.plist file is valid
                if dittoApp.appConfig.appId.isEmpty
                    || dittoApp.appConfig.appId == "put appId here"
                {
                    let error = AppError.error(
                        message: "dittoConfig.plist error - App ID is empty"
                    )
                    throw error
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
        } catch {
            self.dittoApp?.setError(error)
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
            self.localAppConfigSubscription = try ditto.sync
                .registerSubscription(
                    query: """
                        SELECT *
                        FROM dittoappconfigs 
                        """
                )
            Task(priority: .background) {
                try ditto.startSync()
            }
        }
    }

    func stopLocalSubscription() {
        if let subscriptionInstance = localAppConfigSubscription {
            subscriptionInstance.cancel()
            dittoLocal?.stopSync()
        }
    }
}

// MARK: Register Observer - Live Query
extension DittoManager {

    func registerLocalObserver() throws {
        if let ditto = dittoLocal {
            let dittoAppRef = self.dittoApp  // Capture reference before closure
            localObserver = try ditto.store.registerObserver(
                query: """
                    SELECT *
                    FROM dittoappconfigs
                    ORDER BY name
                    """
            ) { [weak self] results in
                guard let self else { return }
                let decoder = JSONDecoder()
                // Create new DittoAppConfig instances and update the published property
                let configs = results.items.compactMap { item in
                    do {
                        return try decoder.decode(
                            DittoAppConfig.self,
                            from: item.jsonData()
                        )
                    } catch {
                        // Use Task to access actor-isolated properties
                        if let app = dittoAppRef {
                            app.setError(error)
                        }
                        return nil
                    }
                }
                // need to update in a task with async so that this will
                // be published to the UI thread
                Task { [weak self] in
                    await self?.setDittoAppConfigs(configs)
                }

            }
        }
    }

    private func setDittoAppConfigs(_ configs: [DittoAppConfig]) async {
        self.dittoAppConfigs = configs
    }
}

// MARK: Ditto App Config Operations
extension DittoManager {

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
                        "mode": appConfig.mode,
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
    
    func deleteDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
         if let ditto = dittoLocal {
             let query = "DELETE FROM dittoappconfigs WHERE _id = :id"
             let argument = ["id": appConfig._id]
             try await ditto.store.execute( query: query, arguments: argument )
         }
     }
    
    func updateDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                let query =
                    "UPDATE dittoappconfigs SET name = :name, appId = :appId, authToken = :authToken, authUrl = :authUrl, websocketUrl = :websocketUrl, httpApiUrl = :httpApiUrl, httpApiKey = :httpApiKey, mode = :mode WHERE _id = :_id"
                let arguments = [
                    "_id": appConfig._id,
                    "name": appConfig.name,
                    "appId": appConfig.appId,
                    "authToken": appConfig.authToken,
                    "authUrl": appConfig.authUrl,
                    "websocketUrl": appConfig.websocketUrl,
                    "httpApiUrl": appConfig.httpApiUrl,
                    "httpApiKey": appConfig.httpApiKey,
                    "mode": appConfig.mode,
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

    func closeDittoSelectedApp() {
        //if an app was already selected, cancel the subscription, observations, and remove the app
        if let ditto = dittoSelectedApp {
            ditto.stopSync()
            self.dittoSubscriptions.forEach { subscription in
                if let dittoSub = subscription.syncSubscription {
                    dittoSub.cancel()
                }
            }
            dittoSubscriptions.removeAll()
        }
        dittoSelectedApp = nil
    }

    func hydrateDittoSelectedApp(_ appConfig: DittoAppConfig) async throws
        -> Bool
    {
        var isSuccess: Bool = false
        do {
            closeDittoSelectedApp()

            // setup the new selected app
            // need to calculate the directory path so each app has it's own
            // unique directory
            let dbname = appConfig.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            let localDirectoryPath = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(dbname + "-")

            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: localDirectoryPath.path)
            {
                try FileManager.default.createDirectory(
                    at: localDirectoryPath,
                    withIntermediateDirectories: true
                )
            }
            
            // Validate inputs before trying to create Ditto
            guard !appConfig.appId.isEmpty, !appConfig.authToken.isEmpty else {
                throw AppError.error(message: "Invalid app configuration - missing appId or token")
            }
            
            //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
            dittoSelectedApp = Ditto(
                identity: .onlinePlayground(
                    appID: appConfig.appId,
                    token: appConfig.authToken,
                    enableDittoCloudSync: false,
                    customAuthURL: URL(
                        string: appConfig.authUrl
                    )
                ),
                persistenceDirectory: localDirectoryPath)
            
            dittoSelectedApp?.updateTransportConfig(block: { config in
                config.connect.webSocketURLs.insert(
                    appConfig.websocketUrl
                )
                config.enableAllPeerToPeer()
            })
                

            try dittoSelectedApp?.disableSyncWithV3()

            self.dittoSelectedAppConfig = appConfig

            // hydrate the subscriptions from the local database
            try await hydrateDittoSubscriptions()

            // TODO hydrate the observers from the database

            isSuccess = true
        } catch {
            self.dittoApp?.setError(error)
        }
        return isSuccess
    }

    func hydrateDittoSubscriptions() async throws {
        if let ditto = dittoLocal,
            let id = dittoSelectedAppConfig?._id
        {
            let query =
                "SELECT * FROM dittosubscriptions WHERE selectedApp_id = :selectedAppId"
            let arguments = ["selectedAppId": id]
            let results = try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            let subscriptions = results.items.compactMap {
                DittoSubscription($0.value)
            }
            try subscriptions.forEach { subscription in
                var sub = subscription
                sub.syncSubscription = try dittoSelectedApp?.sync
                    .registerSubscription(query: subscription.query)
                self.dittoSubscriptions.append(sub)
            }
        }
    }
}

// MARK: Ditto Selected App - Subscription Operations
extension DittoManager {

    func addDittoSubscription(_ subscription: DittoSubscription) async throws {
        if let ditto = dittoLocal,
            let selectedAppConfig = dittoSelectedAppConfig
        {
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
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )

            //handle edge case where subscription exists in the cache
            removeDittoSubscriptionFromCache(subscription)

            //setup the subscription now - need to make it mutable, regiser the subscription
            var sub = subscription
            sub.syncSubscription = try dittoSelectedApp?.sync
                .registerSubscription(
                    query: subscription.query,
                    arguments: subscription.args
                )

            //add to the local cache of observable objects to show in the UI
            dittoSubscriptions.append(sub)
        }
    }

    func removeDittoSubscription(_ subscription: DittoSubscription) async throws
    {
        if let ditto = dittoLocal {
            let query = "DELETE FROM dittosubscriptions WHERE _id = :id"
            let argument = ["id": subscription.id]
            try await ditto.store.execute(
                query: query,
                arguments: argument
            )
            removeDittoSubscriptionFromCache(subscription)
        }
    }

    private func removeDittoSubscriptionFromCache(
        _ subscription: DittoSubscription
    ) {

        //handle edge case where this is an add but it already exists
        if let sub = dittoSubscriptions.first(where: {
            $0.id == subscription.id
        }) {
            if let dittoSub = sub.syncSubscription {
                dittoSub.cancel()
            }
            dittoSubscriptions.removeAll { $0.id == subscription.id }
        }
    }
}

// MARK: Ditto Execute Query
extension DittoManager {
    func executeSelectedAppQuery(query: String) async throws -> [DittoSwift.DittoQueryResultItem]? {
        if let ditto = dittoSelectedApp {
            let results = try await ditto.store.execute(query: query)
            return results.items
        }
        return nil
    }
}
