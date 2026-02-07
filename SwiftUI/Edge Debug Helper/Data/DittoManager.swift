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
                    // Use detached task with utility priority to prevent threading priority inversion
                    await Task.detached(priority: .utility) {
                        existingDitto.sync.stop()
                    }.value
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
                // Configure peer-to-peer transports from saved settings
                config.peerToPeer.bluetoothLE.isEnabled = appConfig.isBluetoothLeEnabled
                config.peerToPeer.lan.isEnabled = appConfig.isLanEnabled
                config.peerToPeer.awdl.isEnabled = appConfig.isAwdlEnabled

                // Configure cloud sync from saved settings
                if appConfig.isCloudSyncEnabled && !appConfig.websocketUrl.isEmpty {
                    config.connect.webSocketURLs.insert(appConfig.websocketUrl)
                }
            })
            
            try ditto.disableSyncWithV3()
            
            // disable strict mode - allows for DQL with counters and objects as CRDT maps, must be called before startSync
            //
            try await ditto.store.execute(
                query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
            )
            
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
        }
    }
}

// MARK: - Transport Configuration
extension DittoManager {
    /// Applies transport configuration to the currently selected Ditto app
    ///
    /// IMPORTANT: This function does NOT stop/start sync or manage observers.
    /// Callers are responsible for:
    /// 1. Stopping sync via selectedAppStopSync()
    /// 2. Calling this function to apply config
    /// 3. Starting sync via selectedAppStartSync()
    /// 4. Managing observer lifecycle (stop/restart)
    ///
    /// - Parameters:
    ///   - isBluetoothLeEnabled: Enable/disable Bluetooth LE transport
    ///   - isLanEnabled: Enable/disable LAN transport
    ///   - isAwdlEnabled: Enable/disable AWDL transport
    ///   - isCloudSyncEnabled: Enable/disable Cloud Sync via WebSocket
    ///
    /// - Throws: AppError if no app is selected
    func applyTransportConfig(
        isBluetoothLeEnabled: Bool,
        isLanEnabled: Bool,
        isAwdlEnabled: Bool,
        isCloudSyncEnabled: Bool
    ) async throws {
        guard let ditto = dittoSelectedApp else {
            throw AppError.error(message: "No Ditto app is currently selected")
        }

        guard let appConfig = dittoSelectedAppConfig else {
            throw AppError.error(message: "No app configuration available")
        }

        // Apply transport configuration changes
        ditto.updateTransportConfig { config in
            // Configure peer-to-peer transports
            config.peerToPeer.bluetoothLE.isEnabled = isBluetoothLeEnabled
            config.peerToPeer.lan.isEnabled = isLanEnabled
            config.peerToPeer.awdl.isEnabled = isAwdlEnabled

            // Configure cloud sync via WebSocket
            if isCloudSyncEnabled {
                if !config.connect.webSocketURLs.contains(appConfig.websocketUrl) {
                    config.connect.webSocketURLs.insert(appConfig.websocketUrl)
                }
            } else {
                config.connect.webSocketURLs.remove(appConfig.websocketUrl)
            }
        }
    }
}
