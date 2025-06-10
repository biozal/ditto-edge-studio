//
//  DittoManager.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import Combine
import DittoSwift
import Foundation
import ObjectiveC
import SwiftUI

// MARK: - DittoService
actor DittoManager: ObservableObject {
    var isStoreInitialized: Bool = false

    // MARK: local app cache

    // local cache is used for remembering things like:
    // query history, favorites, subscriptions, and observers
    // always remember to save those in the dittoLocal instance

    var app: DittoApp?
    var dittoLocal: Ditto?
    var localAppConfigSubscription: DittoSyncSubscription?

    var localAppConfigsObserver: DittoStoreObserver?
    @Published var dittoAppConfigs: [DittoAppConfig] = []

    // MARK: Selected App

    // this is the actual app the user selected
    // things like query, observer events, and the ditto tools should
    // use the dittoSelectedApp instance

    var dittoSelectedAppConfig: DittoAppConfig?
    var dittoSelectedApp: Ditto?

    var selectedAppCollectionObserver: DittoStoreObserver?
    var selectedAppHistoryObserver: DittoStoreObserver?
    var selectedAppFavoritesObserver: DittoStoreObserver?

    @Published var dittoSubscriptions: [DittoSubscription] = []
    @Published var dittoObservables: [DittoObservable] = []
    @Published var dittoObservableEvents: [DittoObserveEvent] = []
    @Published var dittoIntialObservationData: [String: String] = [:]

    private init() {}

    static var shared = DittoManager()

    func initializeStore(dittoApp: DittoApp) async throws {
        do {
            if !isStoreInitialized {
                // setup logging
                DittoLogger.enabled = true
                DittoLogger.minimumLogLevel = .debug

                //cache state for future use
                self.app = dittoApp

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

                // Disable avoid_redundant_bluetooth
                // https://docs.ditto.live/sdk/latest/sync/managing-redundant-bluetooth-le-connections#disabling-redundant-connections
                try await dittoLocal?.store.execute(
                    query:
                        "ALTER SYSTEM SET mesh_chooser_avoid_redundant_bluetooth = false"
                )

                // disable strict mode - allows for DQL with counters and objects as CRDT maps, must be called before startSync
                // 
                try await dittoLocal?.store.execute(
                    query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
                )

                try dittoLocal?.disableSyncWithV3()
                try await setupLocalSubscription()
                try registerLocalObservers()
            }
        } catch {
            self.app?.setError(error)
        }
    }

}
