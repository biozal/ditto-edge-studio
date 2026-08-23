import DittoSwift
import Foundation

actor DittoManager {
    var appState: AppState?
    var dittoSelectedAppConfig: DittoConfigForDatabase?
    var dittoSelectedApp: Ditto?

    /// The persistence directory of the currently active database, used for log file access.
    private(set) var activePersistenceDirectory: URL?

    /// Cached URLSessions that accept untrusted certificates, keyed by the
    /// configured host each bypass is scoped to. Lazily created on first use.
    /// Actor isolation serializes access — no external lock needed.
    private var cachedUntrustedSessions: [String: URLSession] = [:]

    /// Outcome of the most recent Advanced Configuration apply, so the UI can surface
    /// skipped startup settings instead of leaving them buried in the log file.
    private(set) var lastAdvancedApplyResult: AdvancedApplyResult?

    private init() {}

    static let shared = DittoManager()

    func closeDittoSelectedDatabase() async {
        let closeStart = CFAbsoluteTimeGetCurrent()

        // Stop sync
        if let ditto = dittoSelectedApp {
            await Self.stopSyncNow(ditto)
            let syncStopElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close:Ditto] sync.stop() complete (\(String(format: "%.3f", syncStopElapsed))s)")
        }

        // Stop log capture observers + the global SDK log callback so the SDK
        // stops delivering log lines into a service tied to the closed session.
        await MainActor.run {
            DittoLogCaptureService.shared.stopLiveCapture()
            DittoLogCaptureService.shared.stopTransportConditionObserver()
            DittoLogCaptureService.shared.stopConnectionRequestHandler()
        }
        let logCaptureElapsed = CFAbsoluteTimeGetCurrent() - closeStart
        Log.info("[Close:Ditto] Log capture stopped (\(String(format: "%.3f", logCaptureElapsed))s)")

        // Release Ditto reference
        dittoSelectedApp = nil
        let totalElapsed = CFAbsoluteTimeGetCurrent() - closeStart
        Log.info("[Close:Ditto] Ditto reference released (\(String(format: "%.3f", totalElapsed))s)")
    }

    /// Creates the appropriate Ditto DatabaseConfig based on selected Database configuration.
    ///
    /// `nonisolated static` and non-private so the URL validation below — a real decision
    /// on `hydrate`'s path, and the only part of it that can be exercised without a live
    /// `Ditto` — is reachable from unit tests. The body touches no instance state.
    nonisolated static func createDatabaseConfig(
        from appConfig: DittoConfigForDatabase,
        withDirectory persistenceDirectory: URL
    ) throws -> DittoConfig {
        switch appConfig.mode {
        case .smallPeerOnly:
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
        case .development:
            // A bare string with no scheme (e.g. a stray UUID) still yields a
            // non-nil relative URL from URL(string:), which then fails opaquely
            // inside Ditto.open(). Require an absolute http(s)/ws(s) URL with a
            // host so bad config data fails loudly here with a clear message.
            guard !appConfig.url.isEmpty,
                  let url = URL(string: appConfig.url),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http", "wss", "ws"].contains(scheme),
                  let host = url.host, !host.isEmpty else
            {
                throw AppError.error(
                    message: "Invalid configuration for '\(appConfig.name)' — 'url' must be an "
                        + "absolute server URL like https://<cluster>.cloud.dittolive.app "
                        + "(got: '\(appConfig.url)')"
                )
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
        Log.info("[Session] Opening database '\(databaseConfig.name)' (id: \(databaseConfig.databaseId))")
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

            // Refuse to open a database whose stored sync scopes could not be read:
            // proceeding would sync collections the user may have marked device-local.
            if databaseConfig.hasCorruptSyncScopes {
                throw AppError.error(
                    message: "The collection sync scopes saved for '\(databaseConfig.name)' could not be read. " +
                        "The database was not opened, to avoid syncing data you may have marked device-local. " +
                        "Re-enter the sync scopes in Advanced Configuration, then try again."
                )
            }

            // Validate inputs before trying to create Ditto
            guard !databaseConfig.databaseId.isEmpty,
                  !databaseConfig.developmentToken.isEmpty else
            {
                throw AppError.error(
                    message:
                    "Invalid app configuration - missing databaseId or developmentToken"
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
            let config = try Self.createDatabaseConfig(
                from: databaseConfig,
                withDirectory: localDirectoryPath
            )
            dittoInstance = try await Ditto.open(config: config)

            guard let ditto = dittoInstance else {
                throw AppError.error(message: "Failed to create Ditto instance")
            }
            // Capture only the values needed by the closure to avoid retaining
            // the DittoManager actor through the SDK-held expirationHandler.
            let capturedAppState = appState
            let capturedToken = databaseConfig.developmentToken
            ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
                dittoAuth.auth?.login(
                    token: capturedToken,
                    provider: .development
                ) { _, error in
                    if let error {
                        Task { @MainActor in
                            capturedAppState?.setError(error)
                        }
                    } else {
                        Log.info("[Auth] Authentication successful \(secondsRemaining)")
                    }
                }
            }

            // Assign before anything that can throw below. `closeDittoSelectedDatabase`
            // is guarded on this property, so an instance that fails mid-setup would
            // otherwise be unreachable for shutdown while still holding transports —
            // and once sync has started, syncing every collection at the default
            // `AllPeers`.
            dittoSelectedApp = ditto

            // For small peer only mode, set the offline license token
            if shouldSetOfflineLicenseToken(for: databaseConfig) {
                try ditto.setOfflineOnlyLicenseToken(databaseConfig.developmentToken)
            }

            // Update Device Name to show in presence graph
            try ditto.presence.setPeerMetadata(["deviceName": "Edge Studio"])

            // Log the initial transport values being loaded from the database config
            Log.info(
                "[Transport] Initial config from database '\(databaseConfig.name)': " +
                    "bluetoothLE=\(databaseConfig.isBluetoothLeEnabled) " +
                    "lan=\(databaseConfig.isLanEnabled) " +
                    "awdl=\(databaseConfig.isAwdlEnabled) " +
                    "cloudSync=\(databaseConfig.isCloudSyncEnabled)"
            )

            // Assigned here, alongside `dittoSelectedApp`, so there is no window where an
            // instance exists without its config: `resetSystemSettingsToDefaults` and
            // `selectedDatabaseStartSync` both read the pair, and a nil config in either
            // now throws rather than quietly applying nothing.
            dittoSelectedAppConfig = databaseConfig

            let transports = Self.transportFlags(
                for: databaseConfig,
                isUITesting: isRunningUITests()
            )
            let bluetoothEnabled = transports.bluetoothLE
            let lanEnabled = transports.lan
            let awdlEnabled = transports.awdl

            // The whole ordered sequence — user settings, transports, app-managed
            // parameters, sync scopes, then sync — lives in `OpenSequence` so the
            // ordering is unit-testable against the production code path rather than
            // re-stated in a test body.
            let sequence = AdvancedSettingsApplier.OpenSequence(
                applier: AdvancedSettingsApplier(executor: ditto),
                applyTransportConfig: {
                    ditto.updateTransportConfig { config in
                        config.peerToPeer.bluetoothLE.isEnabled = bluetoothEnabled
                        config.peerToPeer.lan.isEnabled = lanEnabled
                        config.peerToPeer.awdl.isEnabled = awdlEnabled

                        // Cloud sync (Big Peer / WebSocket) is established automatically
                        // by the SDK from the server URL passed at Ditto.open() — no
                        // manual webSocketURLs configuration is required in v5.
                    }
                },
                isStrictModeEnabled: databaseConfig.isStrictModeEnabled,
                meshMaxWlanClients: Self.meshMaxWlanClients,
                beforeSync: {
                    // Readback AFTER every ALTER SYSTEM statement, so the log reflects
                    // the transports actually in force rather than pre-override values.
                    // Deliberately non-suspending: an `await` back into this actor here
                    // opened a re-entrancy window right before sync started, during which
                    // the database could be closed or deleted underneath the open.
                    Self.logTransportReadback(from: ditto, context: "hydrate")
                },
                startSync: { try await DittoManager.startSyncNow(ditto) }
            )

            lastAdvancedApplyResult = try await sequence.run(
                startupSettings: databaseConfig.startupSettings,
                syncScopes: databaseConfig.collectionSyncScopes
            )

            // Post-condition: the instance we just opened must still be the selected
            // one. Between `Ditto.open` and here the actor suspends several times, and a
            // concurrent close/delete can nil or replace it — previously that produced a
            // `true` return with `dittoSelectedApp == nil` and an orphan instance syncing
            // against deleted files.
            guard dittoSelectedApp === ditto else {
                // Stop only OUR instance and return without entering the shared teardown:
                // `closeDittoSelectedDatabase()` acts on whatever is currently selected,
                // so on iPad multi-window the loser's cleanup used to kill the winner's
                // live session (and reset its log level and persistence directory).
                Log.warning("[Session] Database was closed or replaced while opening — aborting")
                await Self.stopSyncNow(ditto)
                return false
            }

            // Start transport condition observer for the database lifetime
            await MainActor.run {
                DittoLogCaptureService.shared.clearTransportEntries()
                DittoLogCaptureService.shared.startTransportConditionObserver(ditto: ditto)
                DittoLogCaptureService.shared.clearConnectionRequestEntries()
                DittoLogCaptureService.shared.startConnectionRequestHandler(ditto: ditto)
            }
            isSuccess = true
        } catch {
            // Tear down anything already started. Without this, a failure after
            // `Ditto.open` (notably a fail-closed sync-scope error) can leave a live
            // instance holding transports — and if it got as far as `sync.start()`,
            // syncing at the SDK default `AllPeers`.
            await closeDittoSelectedDatabase()
            dittoSelectedAppConfig = nil
            // Both were set for the database that failed to open; leaving them pointed
            // at it makes log-file access read the wrong directory and keeps the failed
            // config's log level in force.
            activePersistenceDirectory = nil
            DittoLogger.minimumLogLevel = .info
            await appState?.setError(error)
            isSuccess = false
        }
        return isSuccess
    }

    /// Keeps the actor's copy of the active config current.
    ///
    /// `DatabaseEditorView.save` builds a **new** `DittoConfigForDatabase` and persists
    /// it, so without this the actor kept re-applying the settings the database was
    /// opened with — silently reverting a sync scope the user had just changed, and
    /// verifying it against the stale map so nothing looked wrong.
    func refreshSelectedConfigIfMatching(_ config: DittoConfigForDatabase) {
        guard dittoSelectedAppConfig?._id == config._id else { return }
        dittoSelectedAppConfig = config
        Log.info("[Advanced] Active database configuration refreshed after save")
    }

    /// Restores every system parameter to its SDK default, then re-applies everything
    /// Edge Studio manages.
    ///
    /// `ALTER SYSTEM RESET ALL` is indiscriminate — it also clears `DQL_STRICT_MODE`,
    /// the macOS mesh setting, the sync scopes, and potentially the peer-to-peer
    /// transport parameters — so the re-apply below is mandatory, not tidy-up.
    func resetSystemSettingsToDefaults(for config: DittoConfigForDatabase) async throws {
        guard let ditto = dittoSelectedApp, dittoSelectedAppConfig?._id == config._id else {
            // Not the open database: nothing to reset. `ALTER SYSTEM` state dies with
            // the instance, so the next open already starts from SDK defaults.
            Log.info("[Advanced] Reset requested for a database that is not open — no action needed")
            return
        }

        // Adopt the saved config first: everything below re-applies from it, and the
        // actor's copy must not keep pointing at the pre-reset object (which a later
        // re-apply would otherwise replay, undoing this reset).
        dittoSelectedAppConfig = config

        // STOP SYNC FIRST. `RESET ALL` clears the collection sync scopes, so running it
        // against a syncing instance leaves every collection replicable at the SDK
        // default `AllPeers` for the whole re-apply window — including ones the user
        // marked `LocalPeerOnly` — and permanently if any statement below throws. The SDK
        // also requires scopes to be set before `start_sync()`, so re-applying them to a
        // running session may not take effect at all.
        await Self.stopSyncNow(ditto)
        Log.info("[Advanced] Sync stopped for system-settings reset")

        let applier = AdvancedSettingsApplier(executor: ditto)
        do {
            try await applier.resetAllToDefaults()

            // Re-apply everything Edge Studio manages, then restart sync — through the
            // same OpenSequence used at open, so scopes are verified before sync starts.
            //
            // Transports are applied to the CAPTURED `ditto`, exactly as `hydrate` does,
            // rather than by calling back into `self.applyTransportConfig(...)`. That
            // method re-reads `dittoSelectedApp`, so if the selected database changed
            // while this reset was in flight it either threw "No Ditto app is currently
            // selected" or configured a *different* instance while the `ALTER SYSTEM`
            // statements and `sync.start()` below still targeted the captured one.
            //
            // The UI-test gate is applied here too. It was missing on this path, so a
            // reset under UI tests re-enabled BLE/LAN/AWDL and could raise the OS
            // permission dialogs the gate exists to suppress.
            let transports = Self.transportFlags(for: config, isUITesting: isRunningUITests())
            let sequence = AdvancedSettingsApplier.OpenSequence(
                applier: applier,
                applyTransportConfig: {
                    ditto.updateTransportConfig { transportConfig in
                        transportConfig.peerToPeer.bluetoothLE.isEnabled = transports.bluetoothLE
                        transportConfig.peerToPeer.lan.isEnabled = transports.lan
                        transportConfig.peerToPeer.awdl.isEnabled = transports.awdl
                    }
                    Log.info(
                        "[Transport] Re-applied after RESET ALL: bluetoothLE=\(transports.bluetoothLE) " +
                            "lan=\(transports.lan) awdl=\(transports.awdl)"
                    )
                },
                isStrictModeEnabled: config.isStrictModeEnabled,
                meshMaxWlanClients: Self.meshMaxWlanClients,
                beforeSync: { Self.logTransportReadback(from: ditto, context: "resetSystemSettings") },
                startSync: { try await DittoManager.startSyncNow(ditto) }
            )
            lastAdvancedApplyResult = try await sequence.run(
                startupSettings: config.startupSettings,
                syncScopes: config.collectionSyncScopes
            )

            // Post-condition, mirroring `hydrate`: the instance we just reconfigured must
            // still be the selected one. `sequence.run` suspends repeatedly, and a
            // concurrent close/delete can nil or replace it — leaving this instance
            // syncing, unreachable for shutdown, against a database the user closed.
            guard dittoSelectedApp === ditto else {
                // Stop only OUR instance. `closeDittoSelectedDatabase()` acts on whatever
                // is currently selected, so entering the shared teardown here would kill
                // the winner's live session on iPad multi-window.
                Log.warning("[Advanced] Database was closed or replaced during reset — stopping our instance")
                await Self.stopSyncNow(ditto)
                return
            }

            Log.info("[Advanced] System settings reset to defaults and app-managed values re-applied")
        } catch {
            // Sync is already stopped and stays stopped: resuming it here would run
            // unscoped, which is the exact outcome the fail-closed policy exists to
            // prevent. The caller surfaces this to the user.
            Log.error("[Advanced] Reset failed after RESET ALL; leaving sync stopped: \(error)")
            throw error
        }
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func selectedDatabaseStartSync() async throws {
        do {
            // Throws rather than returning: a silent `return` from a `throws` function is
            // success-shaped, and every caller treats "did not throw" as "sync is running"
            // (`SyncStatusViewModel.toggleSync`, `TransportConfigView`'s restart step, the
            // MCP `set_sync` tool). C3 stops the indicator from lying about it, but the user
            // still tapped a button that did nothing and got no message. Reachable via
            // multi-window: `closeDatabaseIfSelected` and `hydrate`'s catch both nil the
            // config out from under an open studio window.
            guard let ditto = dittoSelectedApp, let config = dittoSelectedAppConfig else {
                throw AppError.error(
                    message: "No database is currently open, so sync could not be started. "
                        + "Close and reopen the database, then try again."
                )
            }

            // Routed through the same `OpenSequence` that `hydrate` uses, so this is not
            // a second, independently-maintained path to `sync.start()`. Sync scopes live
            // in memory, so anything that cleared them (an `ALTER SYSTEM RESET ALL` typed
            // into the query editor, for instance) would otherwise let a restart run
            // unscoped. Transports are already configured, so that step is a no-op here.
            let sequence = AdvancedSettingsApplier.OpenSequence(
                applier: AdvancedSettingsApplier(executor: ditto),
                applyTransportConfig: {},
                isStrictModeEnabled: config.isStrictModeEnabled,
                meshMaxWlanClients: Self.meshMaxWlanClients,
                beforeSync: { Log.info("[Sync] Starting Sync") },
                startSync: { try await DittoManager.startSyncNow(ditto) }
            )
            lastAdvancedApplyResult = try await sequence.run(
                startupSettings: config.startupSettings,
                syncScopes: config.collectionSyncScopes
            )

            // Post-condition, mirroring `hydrate`: `sequence.run` suspends repeatedly, so
            // the instance we started may no longer be the selected one by the time we
            // get here — which would leave it syncing and unreachable for shutdown.
            guard dittoSelectedApp === ditto else {
                Log.warning("[Sync] Database was closed or replaced while starting sync — stopping our instance")
                await Self.stopSyncNow(ditto)
                return
            }
        } catch {
            await appState?.setError(error)
            throw error
        }
    }

    // MARK: - Sync start/stop funnels

    /// Starts sync on `ditto` and publishes the resulting state.
    ///
    /// **Every path that starts sync must go through here.** Two reasons:
    /// 1. `SyncRuntimeState` is what the UI renders, so a start that bypasses this leaves
    ///    the indicator lying about whether sync is running.
    /// 2. It concentrates `sync.start(` into one place, which is what makes the
    ///    `sync_start_choke_point` lint rule enforceable rather than decorative.
    ///
    /// `nonisolated` and taking `ditto` as a parameter, both deliberately: the callers are
    /// `@Sendable` closures inside `AdvancedSettingsApplier.OpenSequence`, and awaiting an
    /// actor-isolated method from there would suspend back into this actor at the exact
    /// point `hydrate`'s `beforeSync` comment documents as a re-entrancy hazard. Re-reading
    /// `dittoSelectedApp` here instead of accepting a parameter would reintroduce the C5
    /// bug — acting on a different instance than the caller intended.
    ///
    /// The state is published **after** the SDK call returns, so a throwing start leaves
    /// `isRunning == false` rather than claiming success.
    nonisolated static func startSyncNow(_ ditto: Ditto) async throws {
        // Background queue to avoid a priority inversion.
        try await Task.detached(priority: .utility) {
            // swiftlint:disable:next sync_start_choke_point
            try ditto.sync.start()
        }.value
        await MainActor.run { SyncRuntimeState.shared.setRunning(true) }
    }

    /// Stops sync on `ditto` and publishes the resulting state.
    ///
    /// Unconditional publication: a stop that throws still leaves sync down, so reporting
    /// `false` is correct either way. See `startSyncNow` for why this is `nonisolated` and
    /// takes `ditto` as a parameter.
    nonisolated static func stopSyncNow(_ ditto: Ditto) async {
        await Task.detached(priority: .utility) { ditto.sync.stop() }.value
        await MainActor.run { SyncRuntimeState.shared.setRunning(false) }
    }

    /// The peer-to-peer transport flags to apply for `config`.
    ///
    /// Under UI tests all three are forced off. Enabling BLE / LAN / AWDL triggers OS
    /// permission prompts (Bluetooth, Local Network) that appear as system dialogs over
    /// the app and block the test harness on a fresh machine. The query/observer flows
    /// don't need mesh transport — cloud sync is established by the SDK from the server
    /// URL passed at `Ditto.open()` and is unaffected by these flags.
    ///
    /// Pure and `nonisolated static` so the gating rule is unit-testable without a live
    /// `Ditto`, and so both `hydrate` and `resetSystemSettingsToDefaults` apply the *same*
    /// rule. The reset path previously passed `config.is…Enabled` straight through, which
    /// meant a reset under UI tests re-enabled every transport the gate exists to suppress.
    ///
    /// **`isUITesting` is a parameter, not an internal `isRunningUITests()` call, on
    /// purpose.** The gate must be applied by each *call site* that owns an open sequence,
    /// never pushed down into `applyTransportConfig(isBluetoothLeEnabled:…)` — that method
    /// is also called by the user's Transport Settings screen
    /// (`TransportConfigView.applyTransportConfig`) and by the MCP `configure_transport`
    /// tool. Gating inside it would silently no-op an explicit user toggle while
    /// `TransportConfigView.loadCurrentSettings` kept reading the *stored* config, so the
    /// Settings tab would show "Bluetooth on" over an SDK with Bluetooth off.
    nonisolated static func transportFlags(
        for config: DittoConfigForDatabase,
        isUITesting: Bool
    ) -> TransportFlags {
        let p2pEnabled = !isUITesting
        return TransportFlags(
            bluetoothLE: config.isBluetoothLeEnabled && p2pEnabled,
            lan: config.isLanEnabled && p2pEnabled,
            awdl: config.isAwdlEnabled && p2pEnabled
        )
    }

    /// The three peer-to-peer transport switches, as a named type rather than a tuple:
    /// three same-typed `Bool`s positionally is exactly the shape a caller can transpose
    /// silently, and `large_tuple` flags it for that reason.
    struct TransportFlags: Sendable, Equatable {
        let bluetoothLE: Bool
        let lan: Bool
        let awdl: Bool
    }

    /// The macOS-only mesh client cap, nil elsewhere. Shared by every path that
    /// re-applies the app-managed system parameters.
    static var meshMaxWlanClients: Int? {
        #if os(macOS)
        12
        #else
        nil
        #endif
    }

    func selectedDatabaseStopSync() async {
        if let ditto = dittoSelectedApp {
            Log.info("[Sync] Stopping sync")
            await Self.stopSyncNow(ditto)
        }
    }

    /// Determines if offline license token should be set for the given app configuration
    private func shouldSetOfflineLicenseToken(
        for appConfig: DittoConfigForDatabase
    ) -> Bool {
        appConfig.mode == .smallPeerOnly && !appConfig.developmentToken.isEmpty
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
        let isUITesting = isRunningUITests()
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
    /// Extracts the host the untrusted-cert bypass should be scoped to from a
    /// configured HTTP API URL. `httpApiUrl` is stored as a bare `host[:port]`
    /// (callers prepend `https://`), but a full URL is tolerated too.
    /// `nonisolated static` so the decision is unit-testable without a live
    /// `Ditto` — same pattern as `createDatabaseConfig`.
    nonisolated static func expectedHost(fromHttpApiUrl httpApiUrl: String) -> String? {
        let withScheme = httpApiUrl.contains("://") ? httpApiUrl : "https://\(httpApiUrl)"
        guard let host = URL(string: withScheme)?.host(percentEncoded: false),
              !host.isEmpty else
        {
            return nil
        }
        return host.lowercased()
    }

    /// Session whose delegate accepts untrusted certificates **only** for the
    /// currently selected database's HTTP API host. Cached per host so
    /// switching databases never reuses a bypass scoped to another host.
    /// Falls back to the shared (fully validating) session when no host can
    /// be determined — in that case the bypass simply does not apply.
    func getCachedUntrustedSession() -> URLSession {
        // Actor isolation already serializes access — no lock needed.
        guard let appConfig = dittoSelectedAppConfig,
              let host = Self.expectedHost(fromHttpApiUrl: appConfig.httpApiUrl) else
        {
            return .shared
        }

        if let cachedSession = cachedUntrustedSessions[host] {
            return cachedSession
        }

        // Create new session with delegate for untrusted certificates
        let delegate = AllowUntrustedCertsDelegate(expectedHost: host)
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        cachedUntrustedSessions[host] = session
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
    ///
    /// Cloud sync (Big Peer) is governed by the connect mode passed at
    /// `Ditto.open()` in v5 and is not toggled here.
    ///
    /// - Throws: AppError if no app is selected
    func applyTransportConfig(
        isBluetoothLeEnabled: Bool,
        isLanEnabled: Bool,
        isAwdlEnabled: Bool
    ) async throws {
        guard let ditto = dittoSelectedApp else {
            throw AppError.error(message: "No Ditto app is currently selected")
        }

        Log
            .info(
                "[Transport] Applying config: bluetoothLE=\(isBluetoothLeEnabled) lan=\(isLanEnabled) awdl=\(isAwdlEnabled)"
            )

        // Apply transport configuration changes
        ditto.updateTransportConfig { config in
            // Configure peer-to-peer transports
            config.peerToPeer.bluetoothLE.isEnabled = isBluetoothLeEnabled
            config.peerToPeer.lan.isEnabled = isLanEnabled
            config.peerToPeer.awdl.isEnabled = isAwdlEnabled
        }
        Log
            .info(
                "[Transport] Config applied — bluetoothLE=\(isBluetoothLeEnabled) lan=\(isLanEnabled) awdl=\(isAwdlEnabled)"
            )
        logTransportReadback(from: ditto, context: "applyTransportConfig")
    }

    /// Reads the current transport config back from the SDK and writes it to the app log.
    ///
    /// Call this immediately after every `updateTransportConfig` to confirm the SDK
    /// accepted the values you intended. The `context` label distinguishes call sites
    /// (e.g. "hydrate", "applyTransportConfig") in the log output.
    private func logTransportReadback(from ditto: Ditto, context: String) {
        Self.logTransportReadback(from: ditto, context: context)
    }

    /// Static so callers that must not suspend into the actor (the open sequence's
    /// pre-sync hook) can log the readback directly.
    static func logTransportReadback(from ditto: Ditto, context: String) {
        let tc = ditto.transportConfig
        let wsURLs = tc.connect.webSocketURLs
        let wsDescription = wsURLs.isEmpty ? "(none)" : wsURLs.joined(separator: ", ")
        Log.info(
            "[Transport] Readback (\(context)): " +
                "bluetoothLE=\(tc.peerToPeer.bluetoothLE.isEnabled) " +
                "lan=\(tc.peerToPeer.lan.isEnabled) " +
                "awdl=\(tc.peerToPeer.awdl.isEnabled) " +
                "webSocketURLs=[\(wsDescription)]"
        )
    }
}

// MARK: - Protocol Conformance

extension DittoManager: DittoManagerProtocol {}

// MARK: - Log Level Management

extension DittoManager {
    /// Persists `config` (whose `logLevel` the caller has already set on the
    /// MainActor) and, if it is the active database, applies the level to
    /// `DittoLogger` immediately.
    ///
    /// IMPORTANT: this does NOT mutate `config`. `DittoConfigForDatabase` is an
    /// `@unchecked Sendable` reference type whose contract requires all mutation
    /// to happen on the MainActor; writing to it here (on the actor) would race
    /// MainActor reads of the same shared instance.
    func changeDittoLogLevel(
        _ levelStr: String,
        for config: DittoConfigForDatabase
    ) async throws {
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
