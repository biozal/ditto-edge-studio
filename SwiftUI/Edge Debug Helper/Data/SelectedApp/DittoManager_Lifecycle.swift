//
//  DittoManager_Lifecycle.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import DittoSwift
import Foundation

// MARK: Ditto Selected App - Lifecycle Operations
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
            // remove the observers
            selectedAppHistoryObserver?.cancel()
            selectedAppHistoryObserver = nil
            
            selectedAppCollectionObserver?.cancel()
            selectedAppCollectionObserver = nil
            
            selectedAppFavoritesObserver?.cancel()
            selectedAppFavoritesObserver = nil
            
            dittoSubscriptions.removeAll()
            dittoSubscriptions = []
            
            //close any observers that were registered to show events
            dittoObservables.forEach { event in
                if let observer = event.storeObserver {
                    observer.cancel()
                }
            }
            dittoObservables.removeAll()
            dittoObservables = []
            
            dittoObservableEvents.removeAll()
            dittoObservableEvents = []
        }
        dittoSelectedApp = nil
    }
    
    func selectedAppStartSync() throws {
        do {
            try dittoSelectedApp?.startSync()
            self.selectedAppIsSyncEnabled = true
        } catch {
            self.app?.setError(error)
            self.selectedAppIsSyncEnabled = false
        }
    }
    
    func selectedAppStopSync() {
        dittoSelectedApp?.stopSync()
        self.selectedAppIsSyncEnabled = false
    }
}

// MARK: Ditto Selected App -  Hydration
extension DittoManager {
    
    func hydrateDittoSelectedApp(_ appConfig: DittoAppConfig) async throws
    -> Bool {
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
            
            guard let ditto = dittoSelectedApp else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            
            ditto.updateTransportConfig(block: { config in
                config.connect.webSocketURLs.insert(
                    appConfig.websocketUrl
                )
                config.enableAllPeerToPeer()
            })
            
            
            try ditto.disableSyncWithV3()
            
            // disable strict mode - allows for DQL with counters and objects as CRDT maps, must be called before startSync
            //
            try await ditto.store.execute(
                query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
            )
            
            self.dittoSelectedAppConfig = appConfig
            
            //start sync in the selected app
            try ditto.startSync()
            selectedAppIsSyncEnabled = true
            // hydrate the subscriptions from the local database
            try await hydrateDittoSubscriptions()
            
            isSuccess = true
        } catch {
            self.app?.setError(error)
            isSuccess = false
        }
        return isSuccess
    }
    
    func hydrateQueryFavorites(updateFavorites: @escaping ([DittoQueryHistory]) -> Void)
    async throws -> [DittoQueryHistory] {
        if let ditto = dittoLocal,
           let id = dittoSelectedAppConfig?._id,
           let dittoAppRef = app {
            let query = "SELECT * FROM dittoqueryfavorites WHERE selectedApp_id = :selectedAppId ORDER BY createdDate DESC"
            let arguments = ["selectedAppId": id]
            
            let decoder = JSONDecoder()
            
            //hydrate the initial data from the database
            let historyResults = try await ditto.store.execute(
                query: query, arguments: arguments)
            let historyItems = historyResults.items.compactMap { item in
                do {
                    return try decoder.decode(
                        DittoQueryHistory.self,
                        from: item.jsonData()
                    )
                } catch {
                    dittoAppRef.setError(error)
                    return nil
                }
            }
            
            //register for any changes in the database
            self.selectedAppFavoritesObserver = try ditto.store.registerObserver(
                query: query,
                arguments: arguments
            ) { [updateFavorites] results in
                let historyItems = results.items.compactMap { item in
                    do {
                        return try decoder.decode(
                            DittoQueryHistory.self,
                            from: item.jsonData()
                        )
                    } catch {
                        dittoAppRef.setError(error)
                        return nil
                    }
                }
                updateFavorites(historyItems)
            }
            return historyItems
        }
        return []
    }
    
    func hydrateQueryHistory(updateHistory: @escaping ([DittoQueryHistory]) -> Void)
        async throws -> [DittoQueryHistory] {
        if let ditto = dittoLocal,
           let id = dittoSelectedAppConfig?._id,
           let dittoAppRef = app {
            let query = "SELECT * FROM dittoqueryhistory WHERE selectedApp_id = :selectedAppId ORDER BY createdDate DESC"
            let arguments = ["selectedAppId": id]
            
            let decoder = JSONDecoder()
            
            //hydrate the initial data from the database
            let historyResults = try await ditto.store.execute(
                query: query, arguments: arguments)
            let historyItems = historyResults.items.compactMap { item in
                do {
                    return try decoder.decode(
                        DittoQueryHistory.self,
                        from: item.jsonData()
                    )
                } catch {
                    dittoAppRef.setError(error)
                    return nil
                }
            }
            
            //register for any changes in the database
            self.selectedAppHistoryObserver = try ditto.store.registerObserver(
                query: query,
                arguments: arguments
            ) { [updateHistory] results in
                    let historyItems = results.items.compactMap { item in
                        do {
                            return try decoder.decode(
                                DittoQueryHistory.self,
                                from: item.jsonData()
                            )
                        } catch {
                            dittoAppRef.setError(error)
                            return nil
                        }
                    }
                updateHistory(historyItems)
            }
            return historyItems
        }
        return []
     }
    
    func hydrateCollections(updateCollections: @escaping ([String]) -> Void)
    async throws -> [String] {
        if let ditto = dittoSelectedApp,
           let dittoAppRef = app {
            let query = "SELECT * FROM __collections"
            
            let decoder = JSONDecoder()
            
            //hydrate the initial data from the database
            let results = try await ditto.store.execute(query: query)
            let items = results.items.compactMap { item in
                do {
                    return try decoder.decode(
                        DittoCollection.self,
                        from: item.jsonData()
                    )
                } catch {
                    dittoAppRef.setError(error)
                    return nil
                }
            }.filter { !$0.name.hasPrefix("__") } // Filter out system collections
            
            //register for any changes in the database
            self.selectedAppCollectionObserver = try ditto.store.registerObserver(
                query: query,
            ) { [updateCollections] results in
                let items = results.items.compactMap { item in
                    do {
                        return try decoder.decode(
                            DittoCollection.self,
                            from: item.jsonData()
                        )
                    } catch {
                        dittoAppRef.setError(error)
                        return nil
                    }
                }.filter { !$0.name.hasPrefix("__") } // Filter out system collections
                updateCollections(items.map { $0.name })
            }
            return items.map { $0.name }
        }
        return []
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
