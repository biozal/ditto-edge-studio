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

    var dittoLocal: Ditto?
    var dittoSelected: Ditto?
    var dittoApp: DittoApp?
    var localSubscription: DittoSyncSubscription?
    var localObserver: DittoStoreObserver?
    
    @Published var dittoAppConfigs: [DittoAppConfig] = []
    
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
            let localDirectoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ditto_appconfig")
                    
            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: localDirectoryPath.path) {
                try FileManager.default.createDirectory(
                    at: localDirectoryPath,
                    withIntermediateDirectories: true
                )
            }
            
            //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
            dittoLocal = Ditto(identity: .onlinePlayground(appID: dittoApp.appConfig.appId,
                                                           token: dittoApp.appConfig.authToken,
                                                           enableDittoCloudSync: false,
                                                           customAuthURL: URL(string: dittoApp.appConfig.authUrl)),
                               persistenceDirectory: localDirectoryPath)

            dittoLocal?.updateTransportConfig(block: { config in
                config.connect.webSocketURLs.insert(dittoApp.appConfig.websocketUrl)
            })

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
            var syncScopes = [
              "dittoappconfigs": "LocalPeerOnly"
            ];
            try await ditto.store.execute(
                query: "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
                arguments: ["syncScopes": syncScopes]);
            
            //setup subscription
            self.localSubscription = try ditto.sync.registerSubscription(
                query: """
                    SELECT *
                    FROM dittoappconfigs 
                    """)
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
                    """)
            { [weak self] results in
                Task { @MainActor in
                    // Create new DittoAppConfig instances and update the published property
                    self?.dittoAppConfigs = results.items.compactMap{ DittoAppConfig(value: $0.value) }
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
                try await ditto.store.execute(
                    query: """
                    UPDATE dittoappconfigs
                    SET name = :name,
                        appId = :appId,
                        authToken = :authToken,
                        authUrl = :authUrl,
                        websocketUrl = :websocketUrl
                        httpApiUrl = :httpApiUrl
                        httpApiKey = :httpApiKey
                    WHERE _id = :_id
                """,
                    arguments: [
                        "name": appConfig.name,
                        "appId": appConfig.appId,
                        "authToken": appConfig.authToken,
                        "authUrl": appConfig.authUrl,
                        "websocketUrl": appConfig.websocketUrl,
                        "httpApiUrl": appConfig.httpApiUrl,
                        "httpApiKey": appConfig.httpApiKey,
                    ]
                )
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
    
    func addDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                try await ditto.store.execute(
                    query: """
                    INSERT INTO dittoappconfigs
                    DOCUMENTS (:newConfig)
                """,
                    arguments: ["newConfigt": [
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
                )
            }
        } catch {
            self.dittoApp?.setError(error)
        }
    }
}
