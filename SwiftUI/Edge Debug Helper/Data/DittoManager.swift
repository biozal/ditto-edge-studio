import DittoSwift
import Foundation

actor DittoManager {
    var appState: AppState?
    var dittoSelectedAppConfig: DittoConfigForDatabase?
    var dittoSelectedApp: Ditto?

    /// The persistence directory of the currently active database, used for log file access.
    private(set) var activePersistenceDirectory: URL?

    private init() {}

    static var shared = DittoManager()

    func closeDittoSelectedDatabase() async {
        // if an app was already selected, cancel the subscription, observations, and remove the app
        if let ditto = dittoSelectedApp {
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
        dittoSelectedApp = nil
    }

    /// Creates the appropriate Ditto DatabaseConfig based on selected Database configuration
    private func createDatabaseConfig(
        from appConfig: DittoConfigForDatabase,
        withDirectory persistenceDirectory: URL
    ) throws -> DittoConfig {
        switch appConfig.mode {
        case .smallPeersOnly:
            if !appConfig.secretKey.isEmpty {
                return DittoConfig(
                    databaseID: appConfig.databaseId,
                    connect: .smallPeersOnly(privateKey: appConfig.secretKey)
                )
            } else {
                return DittoConfig(
                    databaseID: appConfig.databaseId,
                    connect: .smallPeersOnly()
                )
            }
        case .server:
            guard !appConfig.authUrl.isEmpty, let url = URL(string: appConfig.authUrl) else {
                throw AppError.error(message: "Invalid configuration - malformed authUrl")
            }
            return DittoConfig(
                databaseID: appConfig.databaseId,
                connect: .server(url: url),
                persistenceDirectory: persistenceDirectory
            )
        }
    }

    func hydrateDittoSelectedDatabase(_ databaseConfig: DittoConfigForDatabase)
        async throws
        -> Bool
    {
        var isSuccess = false
        do {
            await closeDittoSelectedDatabase()

            // setup the new selected app
            // need to calculate the directory path so each app has it's own
            // unique directory with /database subdirectory

            // Test isolation: Use separate directory for UI tests
            let localDirectoryPath = Self.localDirectoryPath(
                for: databaseConfig
            )
            .appendingPathComponent("database")

            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: localDirectoryPath.path) {
                try FileManager.default.createDirectory(
                    at: localDirectoryPath,
                    withIntermediateDirectories: true
                )
            }

            Log.info("Ditto database path: \(localDirectoryPath.path)")

            // Validate inputs before trying to create Ditto
            guard !databaseConfig.databaseId.isEmpty,
                  !databaseConfig.token.isEmpty else
            {
                throw AppError.error(
                    message:
                    "Invalid app configuration - missing databaseId or token"
                )
            }

            // Apply stored log level BEFORE Ditto.init() — required by SDK
            DittoLogger.minimumLogLevel = Self.dittoLogLevel(
                from: databaseConfig.logLevel
            )
            DittoLogger.isEnabled = true
            Log.info("DittoLogger level set to: \(databaseConfig.logLevel)")

            // Store the persistence directory for log capture
            activePersistenceDirectory = localDirectoryPath

            var dittoInstance: Ditto?
            let config = try createDatabaseConfig(
                from: databaseConfig,
                withDirectory: localDirectoryPath
            )
            dittoInstance = try await Ditto.open(config: config)

            guard let ditto = dittoInstance else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
                dittoAuth.auth?.login(
                    token: databaseConfig.token,
                    provider: .development
                ) { _, error in
                    if let error {
                        Task {
                            await self.appState?.setError(error)
                        }
                    } else {
                        Log.info("Authentication successful \(secondsRemaining)")
                    }
                }
            }

            // For small peers only mode, set the offline license token (using token field)
            if shouldSetOfflineLicenseToken(for: databaseConfig) {
                try ditto.setOfflineOnlyLicenseToken(databaseConfig.token)
            }

            // Update Device Name to show in presence graph
            try ditto.presence.setPeerMetadata(["deviceName": "Edge Studio"])

            ditto.updateTransportConfig(block: { config in
                // Configure peer-to-peer transports from saved settings
                config.peerToPeer.bluetoothLE.isEnabled =
                    databaseConfig.isBluetoothLeEnabled
                config.peerToPeer.lan.isEnabled = databaseConfig.isLanEnabled
                config.peerToPeer.awdl.isEnabled = databaseConfig.isAwdlEnabled

                // Configure cloud sync from saved settings
                if !databaseConfig.websocketUrl.isEmpty {
                    config.connect.webSocketURLs.insert(
                        databaseConfig.websocketUrl
                    )
                }
            })

            dittoSelectedAppConfig = databaseConfig

            // start sync in the selected app on background queue to avoid priority inversion
            try await Task.detached(priority: .utility) {
                try ditto.sync.start()
            }.value

            dittoSelectedApp = ditto
            guard dittoSelectedApp != nil else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            isSuccess = true
        } catch {
            appState?.setError(error)
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
    private func shouldSetOfflineLicenseToken(
        for appConfig: DittoConfigForDatabase
    ) -> Bool {
        appConfig.mode == .smallPeersOnly && !appConfig.token.isEmpty
    }

    /// Closes the currently selected database only if it matches the given database ID.
    /// Called before deleting a database to ensure file handles are released before disk removal.
    func closeDatabaseIfSelected(databaseId: String) async {
        guard dittoSelectedAppConfig?.databaseId == databaseId else { return }
        await closeDittoSelectedDatabase()
        dittoSelectedAppConfig = nil
    }

    /// Returns the root directory for a database configuration's local storage.
    /// The Ditto data files live in a `database/` subdirectory within this path.
    nonisolated static func localDirectoryPath(
        for databaseConfig: DittoConfigForDatabase
    ) -> URL {
        let isUITesting = ProcessInfo.processInfo.arguments.contains(
            "UI-TESTING"
        )
        let baseComponent =
            isUITesting ? "ditto_edge_studio_test" : "ditto_edge_studio"
        let dbname = databaseConfig.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent(baseComponent)
            .appendingPathComponent("\(dbname)-\(databaseConfig.databaseId)")
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

// MARK: - URL Session

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
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
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
                if !config.connect.webSocketURLs.contains(
                    appConfig.websocketUrl
                ) {
                    config.connect.webSocketURLs.insert(appConfig.websocketUrl)
                }
            } else {
                config.connect.webSocketURLs.remove(appConfig.websocketUrl)
            }
        }
    }
}

// MARK: - Log Level Management

extension DittoManager {
    /// Changes the SDK log level for a database configuration and persists it.
    /// If the database is currently active, applies the change to DittoLogger immediately.
    func changeDittoLogLevel(
        _ levelStr: String,
        for config: DittoConfigForDatabase
    ) async throws {
        config.logLevel = levelStr
        try await DatabaseRepository.shared.updateDittoAppConfig(config)
        if dittoSelectedAppConfig?._id == config._id {
            DittoLogger.minimumLogLevel = Self.dittoLogLevel(from: levelStr)
            Log.info("DittoLogger level changed to: \(levelStr)")
        }
    }

    /// Maps a stored log level string to a DittoLogLevel enum value.
    nonisolated static func dittoLogLevel(from string: String) -> DittoLogLevel {
        switch string {
        case "error": return .error
        case "warning": return .warning
        case "debug": return .debug
        case "verbose": return .verbose
        default: return .info
        }
    }
}
