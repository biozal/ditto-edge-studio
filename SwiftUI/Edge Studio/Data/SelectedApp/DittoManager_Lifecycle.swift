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
            dittoSubscriptions.removeAll()
            
            // remove the observers
            selectedAppHistoryObserver?.cancel()
            selectedAppHistoryObserver = nil
        }
        dittoSelectedApp = nil
    }
    
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
            
            self.dittoSelectedAppConfig = appConfig
            
            //start sync in the selected app
            try ditto.startSync()
            
            // hydrate the query history from the database
            try await hydrateSelectedAppQueryHistory()
            
            // hydrate the subscriptions from the local database
            try await hydrateDittoSubscriptions()
            
            // hydrate the observers from the database
            try await hydrateDittoObservers()
            

            
            isSuccess = true
        } catch {
            self.dittoApp?.setError(error)
            isSuccess = false
        }
        return isSuccess
    }
    
    func hydrateSelectedAppQueryHistory() async throws {
        if let ditto = dittoLocal,
           let id = dittoSelectedAppConfig?._id,
           let dittoAppRef = dittoApp {
            let query = "SELECT * FROM dittoqueryhistory WHERE selectedApp_id = :selectedAppId"
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
            self.dittoQueryHistory = historyItems
            
            //register for any changes in the database
            self.selectedAppHistoryObserver = try ditto.store.registerObserver(
                query: query,
                arguments: arguments
            ) { [weak self] results in
                    guard let self else { return }
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
                Task {@MainActor [weak self] in
                    await self?.updateQueryHistory(historyItems)
                }
            }
        }
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
    
    func hydrateDittoObservers() async throws {
        if let ditto = dittoLocal,
           let id = dittoSelectedAppConfig?._id
        {
            let query =
            "SELECT * FROM dittoobservations WHERE selectedApp_id = :selectedAppId"
            let arguments = ["selectedAppId": id]
            let results = try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            
            results.items.forEach { item in
                let observable = DittoObservable(item.value)
                self.dittoObservables.append(observable)
            }
        }
    }
    
    func updateQueryHistory(_ items: [DittoQueryHistory]) {
        self.dittoQueryHistory = items
    }
}
