import DittoSwift
import Foundation


// MARK: - DittoService
actor DittoManager {
    var isStoreInitialized: Bool = false

    var appState: AppState?
    var dittoLocal: Ditto?

    // this is the actual app the user selected
    // things like query, observer events, and the ditto tools should
    // use the dittoSelectedApp instance
    var dittoSelectedAppConfig: DittoAppConfig?
    var dittoSelectedApp: Ditto?
    
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
    
    func initializeStore(appState: AppState) async throws {
        do {
            if !isStoreInitialized {
                // Clean up any existing local instance first
                if let existingDitto = dittoLocal {
                    try? existingDitto.sync.stop()
                    dittoLocal = nil
                }
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

                //validate that the dittoConfig.plist file is valid
                if appState.appConfig.appId.isEmpty
                    || appState.appConfig.appId == "put appId here"
                {
                    let error = AppError.error(
                        message: "dittoConfig.plist error - App ID is empty"
                    )
                    throw error
                }
                
                // Note: We can't reliably pre-check for lock files because Ditto manages its own locking.
                // Instead, we'll rely on catching the error after initialization attempt.

                //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
                // Use Objective-C exception handler to catch NSException from Ditto initialization
                var dittoInstance: Ditto?

                let error = ExceptionCatcher.perform {
                    let identity = self.createIdentity(from: appState.appConfig)
                    dittoInstance = Ditto(
                        identity: identity,
                        persistenceDirectory: localDirectoryPath
                    )
                }

                if let error = error {
                    let errorMessage = error.localizedDescription

                    // Check if this is a lock error
                    if errorMessage.contains("persistenceDirectoryLocked") || errorMessage.contains("File already locked") {
                        await MainActor.run {
                            appState.setError(AppError.error(message: """
                                Cannot open database - Another instance of this app is already using this database.

                                Please close any other instances of this app or use a different app configuration.

                                Error: \(errorMessage)
                                """))
                        }
                    }

                    throw AppError.error(message: "Failed to initialize Ditto: \(errorMessage)")
                }

                guard let ditto = dittoInstance else {
                    throw AppError.error(message: "Failed to create Ditto instance")
                }
                
                // For shared key and offline playground modes, set the offline license token (using authToken field)
                if shouldSetOfflineLicenseToken(for: appState.appConfig) {
                    // Offline license token set
                }
                
                dittoLocal = ditto

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
            }
        } catch {
            self.appState?.setError(error)
        }
    }
    
    func closeDittoSelectedApp() async {
        //if an app was already selected, cancel the subscription, observations, and remove the app
        if let ditto = dittoSelectedApp {
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
        dittoSelectedApp = nil
    }

    /// Checks if an error indicates database corruption
    private func isDatabaseCorruptionError(_ error: Error) -> Bool {
        let errorMessage = error.localizedDescription.lowercased()
        return errorMessage.contains("no such table: __ditto_internal__") ||
               errorMessage.contains("sqlite") ||
               errorMessage.contains("database corruption") ||
               errorMessage.contains("failed to get tx_id")
    }

    /// Wipes the corrupted database directory for recovery
    private func clearCorruptedDatabase(at persistenceDirectory: URL) async throws {
        // Check if directory exists
        guard FileManager.default.fileExists(atPath: persistenceDirectory.path) else {
            return
        }

        // Delete the entire directory
        try FileManager.default.removeItem(at: persistenceDirectory)

        // Recreate the directory
        try FileManager.default.createDirectory(
            at: persistenceDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Safely initializes a Ditto instance with automatic corruption recovery
    /// Returns the initialized Ditto instance or throws an error
    private func safeInitializeDitto(
        appConfig: DittoAppConfig,
        persistenceDirectory: URL,
        maxRetries: Int = 2
    ) async throws -> Ditto {
        var lastError: Error?

        for _ in 1...maxRetries {
            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: persistenceDirectory.path) {
                try FileManager.default.createDirectory(
                    at: persistenceDirectory,
                    withIntermediateDirectories: true
                )
            }

            // Try to initialize Ditto
            var dittoInstance: Ditto?
            let error = ExceptionCatcher.perform {
                let identity = self.createIdentity(from: appConfig)
                dittoInstance = Ditto(
                    identity: identity,
                    persistenceDirectory: persistenceDirectory
                )
            }

            // Check for initialization errors
            if let error = error {
                lastError = error

                // Check if this is a corruption error
                if isDatabaseCorruptionError(error) {
                    try await clearCorruptedDatabase(at: persistenceDirectory)
                    continue
                } else {
                    // Non-corruption error, don't retry
                    throw AppError.error(message: "Failed to initialize Ditto: \(error.localizedDescription)")
                }
            }

            guard let ditto = dittoInstance else {
                throw AppError.error(message: "Failed to create Ditto instance (nil)")
            }

            // Successfully initialized
            return ditto
        }

        // All retries exhausted
        let errorMessage = lastError?.localizedDescription ?? "Unknown error"
        throw AppError.error(message: "Failed to initialize Ditto after \(maxRetries) attempts: \(errorMessage)")
    }

    func wipeDatabaseForApp(_ appConfig: DittoAppConfig) async throws {
        // If this is the currently selected app, close it first
        if let selectedConfig = dittoSelectedAppConfig, selectedConfig._id == appConfig._id {
            await closeDittoSelectedApp()
        }

        // Calculate the directory path (same logic as in hydrateDittoSelectedApp)
        let dbname = appConfig.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let localDirectoryPath = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("ditto_apps")
            .appendingPathComponent("\(dbname)-\(appConfig.appId)")

        // Check if directory exists
        guard FileManager.default.fileExists(atPath: localDirectoryPath.path) else {
            return
        }

        // Delete the directory
        try FileManager.default.removeItem(at: localDirectoryPath)
    }

    func hydrateDittoSelectedApp(_ appConfig: DittoAppConfig) async throws
    -> Bool {
        var isSuccess: Bool = false
        do {
            await closeDittoSelectedApp()

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
                .appendingPathComponent("ditto_apps")
                .appendingPathComponent("\(dbname)-\(appConfig.appId)")

            // Validate inputs before trying to create Ditto
            guard !appConfig.appId.isEmpty, !appConfig.authToken.isEmpty else {
                throw AppError.error(message: "Invalid app configuration - missing appId or token")
            }
            
            //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
            // Use Objective-C exception handler to catch NSException from Ditto initialization
            var dittoInstance: Ditto?
            
            let error = ExceptionCatcher.perform {
                let identity = self.createIdentity(from: appConfig)
                dittoInstance = Ditto(
                    identity: identity,
                    persistenceDirectory: localDirectoryPath
                )
            }
            
            if let error = error {
                let errorMessage = error.localizedDescription
                throw AppError.error(message: "Failed to initialize Ditto: \(errorMessage)")
            }
            
            guard let ditto = dittoInstance else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            
            // For shared key and offline playground modes, set the offline license token (using authToken field)
            if shouldSetOfflineLicenseToken(for: appConfig) {
                try ditto.setOfflineOnlyLicenseToken(appConfig.authToken)
            }
            
            dittoSelectedApp = ditto
            
            guard let ditto = dittoSelectedApp else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            
            ditto.updateTransportConfig(block: { config in
                config.connect.webSocketURLs.insert(
                    appConfig.websocketUrl
                )
                config.enableAllPeerToPeer()
            })

            // IMPORTANT: Execute ALTER SYSTEM commands BEFORE disableSyncWithV3()
            // This ensures the internal database schema is fully initialized
            // disable strict mode - allows for DQL with counters and objects as CRDT maps, must be called before startSync
            try await ditto.store.execute(
                query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
            )

            // Now it's safe to disable v3 sync after the database is properly initialized
            try ditto.disableSyncWithV3()
            
            self.dittoSelectedAppConfig = appConfig
            
            //start sync in the selected app on background queue to avoid priority inversion
            try await Task.detached(priority: .utility) {
                try ditto.sync.start()
            }.value
            
            isSuccess = true
        } catch {
            self.appState?.setError(error)
            isSuccess = false
        }
        return isSuccess
    }
    
    func selectedAppStartSync() async throws {
        do {
            if let ditto = dittoSelectedApp {
                try await Task.detached(priority: .utility) {
                    try ditto.sync.start()
                }.value
            }
        } catch {
            appState?.setError(error)
            throw error
        }
    }
    
    func selectedAppStopSync() async {
        if let ditto = dittoSelectedApp {
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
    }
    
    /// Shuts down all Ditto instances and cleans up resources
    func shutdown() async {
        // Stop and clean up selected app
        await closeDittoSelectedApp()
        
        // Stop and clean up local Ditto instance
        if let localDitto = dittoLocal {
            await Task.detached(priority: .utility) {
                localDitto.sync.stop()
            }.value
            dittoLocal = nil
        }
        
        // Reset state
        isStoreInitialized = false
        appState = nil
        dittoSelectedAppConfig = nil
    }
    
    /// Determines if offline license token should be set for the given app configuration
    private func shouldSetOfflineLicenseToken(for appConfig: DittoAppConfig) -> Bool {
        return (appConfig.mode == .sharedKey || appConfig.mode == .offlinePlayground)
            && !appConfig.authToken.isEmpty
    }

    /// Creates the appropriate Ditto identity based on app configuration
    private func createIdentity(from appConfig: DittoAppConfig) -> DittoIdentity {
        switch appConfig.mode {
        case .sharedKey:            
            // Use shared key identity with optional secret key
            // Note: The offline license token is set separately via setOfflineOnlyLicenseToken
            if !appConfig.secretKey.isEmpty {
                // If secret key is provided, use it for identity creation
                return .sharedKey(appID: appConfig.appId, sharedKey: appConfig.secretKey)
            } else {
                // No secret key, use basic offline playground identity
                return .offlinePlayground(appID: appConfig.appId)
            }
            
        case .offlinePlayground:
            // Use offline playground identity
            return .offlinePlayground(appID: appConfig.appId)
            
        case .onlinePlayground:
            // Use online playground identity (authToken is the playground token here)            
            return .onlinePlayground(
                appID: appConfig.appId,
                token: appConfig.authToken,
                enableDittoCloudSync: false,
                customAuthURL: URL(string: appConfig.authUrl)
            )
            
        default:
            // This should not be possible. Here as to future-proof.
            fatalError("Unknown mode: '\(appConfig.mode)'. Expected .onlinePlayground, .offlinePlayground, or .sharedKey")
        }
    }
}
