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

    var appState: AppState?
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
    @Published var selectedAppIsSyncEnabled = false

    @Published var dittoSubscriptions: [DittoSubscription] = []
    @Published var dittoObservables: [DittoObservable] = []
    @Published var dittoObservableEvents: [DittoObserveEvent] = []
    @Published var dittoIntialObservationData: [String: String] = [:]
    
    // MARK: - Cached URLSession for untrusted certificates
    private static var cachedUntrustedSession: URLSession?
    private static let untrustedSessionLock = NSLock()
    
    private init() {}

    static var shared = DittoManager()
    
    // MARK: - URLSession Caching
    
    func getCachedUntrustedSession() -> URLSession {
        Self.untrustedSessionLock.lock()
        defer { Self.untrustedSessionLock.unlock() }
        
        if let cachedSession = Self.cachedUntrustedSession {
            return cachedSession
        }
        
        // Create new session with delegate for untrusted certificates
        let delegate = AllowUntrustedCertsDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        Self.cachedUntrustedSession = session
        return session
    }
    
    // MARK: - URLSession delegate to allow untrusted certificates
    class AllowUntrustedCertsDelegate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let serverTrust = challenge.protectionSpace.serverTrust {
                // Accept the server trust without validation
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    func initializeStore(appState: AppState) async throws {
        do {
            if !isStoreInitialized {
                // setup logging
                DittoLogger.isEnabled = true
                DittoLogger.minimumLogLevel = .debug

                //cache state for future use
                self.appState =  appState

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
                if appState.appConfig.appId.isEmpty
                    || appState.appConfig.appId == "put appId here"
                {
                    let error = AppError.error(
                        message: "dittoConfig.plist error - App ID is empty"
                    )
                    throw error
                }

                //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
                dittoLocal = Ditto(
                    identity: .onlinePlayground(
                        appID: appState.appConfig.appId,
                        token: appState.appConfig.authToken,
                        enableDittoCloudSync: false,
                        customAuthURL: URL(
                            string: appState.appConfig.authUrl
                        )
                    ),
                    persistenceDirectory: localDirectoryPath
                )

                dittoLocal?.updateTransportConfig(block: { config in
                    config.connect.webSocketURLs.insert(
                        appState.appConfig.websocketUrl
                    )
                })

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
            self.appState?.setError(error)
        }
    }

}
