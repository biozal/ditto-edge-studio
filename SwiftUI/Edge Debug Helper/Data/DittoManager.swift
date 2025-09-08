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
                .appendingPathComponent("ditto_local_config")

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
                    dittoInstance = Ditto(
                        identity: .onlinePlayground(
                            appID: appState.appConfig.appId,
                            token: appState.appConfig.authToken,
                            enableDittoCloudSync: false,
                            customAuthURL: URL(string: appState.appConfig.authUrl)
                        ),
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
                dittoInstance = Ditto(
                    identity: .onlinePlayground(
                        appID: appConfig.appId,
                        token: appConfig.authToken,
                        enableDittoCloudSync: false,
                        customAuthURL: URL(string: appConfig.authUrl)
                    ),
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
}
