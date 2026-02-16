import DittoSwift
import Foundation

actor DittoManager {
    var appState: AppState?
    var dittoSelectedAppConfig: DittoConfigForDatabase?
    var dittoSelectedApp: Ditto?
    
    private init() {}

    static var shared = DittoManager()

    func closeDittoSelectedDatabase() async {
        //if an app was already selected, cancel the subscription, observations, and remove the app
        if let ditto = dittoSelectedApp {
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
        dittoSelectedApp = nil
    }

    /// Creates the appropriate DittoCopnfig based on selected Database configuration
    private func createIdentity(from appConfig: DittoConfigForDatabase) -> DittoIdentity {
        switch appConfig.mode {
            case .smallPeersOnly:
                // Use shared key identity if secret key is provided, otherwise offline playground
                if !appConfig.secretKey.isEmpty {
                    return .sharedKey(appID: appConfig.databaseId, sharedKey: appConfig.secretKey)
                } else {
                    return .offlinePlayground(appID: appConfig.databaseId)
                }

            case .server:
                // Use online playground identity (token is the playground token)
                return .onlinePlayground(
                    appID: appConfig.databaseId,
                    token: appConfig.token,
                    enableDittoCloudSync: false,
                    customAuthURL: URL(string: appConfig.authUrl)
                )
        }
    }

    func hydrateDittoSelectedDatabase(_ databaseConfig: DittoConfigForDatabase) async throws
    -> Bool {
        var isSuccess: Bool = false
        do {
            await closeDittoSelectedDatabase()

            // setup the new selected app
            // need to calculate the directory path so each app has it's own
            // unique directory with /database subdirectory
            let dbname = databaseConfig.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            let localDirectoryPath = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appendingPathComponent("ditto_apps")
                .appendingPathComponent("\(dbname)-\(databaseConfig.databaseId)")
                .appendingPathComponent("database")  // NEW: Add database/ subdirectory

            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: localDirectoryPath.path)
            {
                try FileManager.default.createDirectory(
                    at: localDirectoryPath,
                    withIntermediateDirectories: true
                )
            }

            // Validate inputs before trying to create Ditto
            guard !databaseConfig.databaseId.isEmpty, !databaseConfig.token.isEmpty else {
                throw AppError.error(message: "Invalid app configuration - missing databaseId or token")
            }

            //https://docs.ditto.live/sdk/latest/install-guides/swift#integrating-and-initializing-sync
            // Use Objective-C exception handler to catch NSException from Ditto initialization
            var dittoInstance: Ditto?

            let error = ExceptionCatcher.perform {
                let identity = self.createIdentity(from: databaseConfig)
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

            // For small peers only mode, set the offline license token (using token field)
            if shouldSetOfflineLicenseToken(for: databaseConfig) {
                try ditto.setOfflineOnlyLicenseToken(databaseConfig.token)
            }

            // Update Device Name to show in presence graph
            try ditto.presence.setPeerMetadata(["deviceName": "Edge Studio"]);

            ditto.updateTransportConfig(block: { config in

                // Configure peer-to-peer transports from saved settings
                config.peerToPeer.bluetoothLE.isEnabled = databaseConfig.isBluetoothLeEnabled
                config.peerToPeer.lan.isEnabled = databaseConfig.isLanEnabled
                config.peerToPeer.awdl.isEnabled = databaseConfig.isAwdlEnabled

                // Configure cloud sync from saved settings
                if databaseConfig.isCloudSyncEnabled && !databaseConfig.websocketUrl.isEmpty {
                    config.connect.webSocketURLs.insert(databaseConfig.websocketUrl)
                }
            })

            try ditto.disableSyncWithV3()

            // disable strict mode - allows for DQL with counters and objects as CRDT maps, must be called before startSync
            try await ditto.store.execute(
                query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
            )

            self.dittoSelectedAppConfig = databaseConfig

            //start sync in the selected app on background queue to avoid priority inversion
            try await Task.detached(priority: .utility) {
                try ditto.sync.start()
            }.value

            self.dittoSelectedApp = ditto
            guard let _ = dittoSelectedApp else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            isSuccess = true
        } catch {
            self.appState?.setError(error)
            isSuccess = false
        }
        return isSuccess
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func selectedDatabaseStartSync() async throws {
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
    
    func selectedDatabaseStopSync() async {
        if let ditto = dittoSelectedApp {
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
    }

    /// Determines if offline license token should be set for the given app configuration
    private func shouldSetOfflineLicenseToken(for appConfig: DittoConfigForDatabase) -> Bool {
        return appConfig.mode == .smallPeersOnly && !appConfig.token.isEmpty
    }

    /// Shuts down all Ditto instances and cleans up resources
    func shutdown() async {
        // Stop and clean up selected app
        await closeDittoSelectedDatabase()

        // Reset state
        appState = nil
        dittoSelectedAppConfig = nil
    }

}

//MARK: - URL Session
extension DittoManager {

    // Cached URLSession for untrusted certificates
    private static var cachedUntrustedSession: URLSession?
    private static let untrustedSessionLock = NSLock()

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
