package com.costoda.dittoedgestudio.data.ditto

import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.domain.model.AdvancedApplyResult
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAuthenticationProvider
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

class DittoManager(
    private val coroutineScope: CoroutineScope,
    private val logCaptureService: DittoLogCaptureService? = null,
    private val appPreferences: com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway? = null,
    private val multicastLockController: MulticastLockController? = null,
) {

    private var ditto: Ditto? = null

    @Volatile
    private var activeDatabase: DittoDatabase? = null

    /** Outcome of the most recent advanced-configuration apply, for the editor UI. */
    @Volatile
    var lastAdvancedApplyResult: AdvancedApplyResult? = null
        private set

    fun currentDatabase(): DittoDatabase? = activeDatabase

    /**
     * Keeps the active config current after an edit-save of the open database, or a
     * later sync restart would re-apply the settings this database was opened with —
     * silently reverting the scope the user just changed.
     */
    fun refreshActiveConfigIfMatching(database: DittoDatabase) {
        if (activeDatabase?.id == database.id && database.id != 0L) {
            activeDatabase = database
        }
    }

    companion object {
        /** Env var the SDK maps to `metrics_exporter_virtual_collection_enabled`. */
        internal const val SYSTEM_METRICS_ENV_VAR = "DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED"

        private const val TAG = "DittoManager"
    }

    suspend fun hydrate(database: DittoDatabase): Ditto {
        require(database.databaseId.isNotBlank()) { "databaseId must not be blank" }
        if (database.mode == AuthMode.SERVER) {
            require(database.token.isNotBlank()) { "token must not be blank for SERVER mode" }
            require(database.authUrl.isNotBlank()) { "authUrl must not be blank for SERVER mode" }
        }
        // Fail-closed: unreadable stored scopes mean the containment configuration is
        // unknown, and "probably applied" is not good enough (see
        // docs/ADVANCED_DATABASE_CONFIG.md). The editor blocks Save until the scopes
        // are re-entered or the loss is explicitly confirmed.
        require(!database.hasCorruptSyncScopes) {
            "Collection sync scopes could not be read; re-enter or discard them in the database editor."
        }

        closeCurrentInstance()

        // Set Ditto SDK log level to Info by default (can be changed in the Logging UI)
        if (logCaptureService != null) {
            runCatching { DittoLogger.minimumLogLevel = DittoLogLevel.Info }
        }

        // Startup-gated SDK 5.1 knob: `metrics_exporter_virtual_collection_enabled` is
        // read once at Ditto construction (runtime ALTER SYSTEM is ignored), so the
        // env var must be flipped BEFORE DittoFactory.create. When the setting is off
        // we actively unset it — a stale "true" from an earlier toggle-on must not
        // survive within the same process.
        applySystemMetricsEnv()

        val config = buildConfig(database)
        val newDitto = withContext(Dispatchers.IO) {
            DittoFactory.create(config, coroutineScope)
        }

        // Set device name for peer identification
        newDitto.deviceName = "Edge Studio"

        // Set peer metadata to include deviceName so it is visible to other peers
        // (mirrors Swift: ditto.presence.setPeerMetadata(["deviceName": "Edge Studio"]))
        runCatching { newDitto.presence.peerMetadataJsonString = """{"deviceName":"Edge Studio"}""" }
            .onFailure { e -> Log.e(TAG, "Failed to set peer metadata: ${e.message}") }

        // Register auth handler BEFORE starting sync
        setupAuth(newDitto, database)

        // Advanced configuration + transports + sync start, in the mandated order
        // (user settings → transports → DQL_STRICT_MODE → sync scopes → startSync).
        runOpenSequence(newDitto, database)

        ditto = newDitto
        activeDatabase = database
        return newDitto
    }

    /**
     * Re-applies the advanced configuration and starts sync on the current instance.
     *
     * Every path that starts sync must go through this funnel (the initial open and
     * the sync toggle alike), so scopes are re-applied and re-verified rather than
     * trusting whatever is still in memory — `ALTER SYSTEM` state is in-memory only.
     * Uses the manager's own copy of the active config, which
     * [refreshActiveConfigIfMatching] keeps current across edit-saves.
     */
    suspend fun startSync() {
        val instance = ditto ?: error("No active Ditto instance")
        val database = activeDatabase ?: error("No active database")
        runOpenSequence(instance, database)
    }

    /**
     * Restores every system parameter to its SDK default on the live instance, then
     * re-applies everything Edge Studio manages and restarts sync.
     *
     * `RESET ALL` is indiscriminate — it resets every parameter, not just the user's —
     * so the re-apply is mandatory, not tidy-up. For a database that is not open there
     * is nothing to reset: `ALTER SYSTEM` state dies with the instance, so the next
     * open already starts from SDK defaults.
     */
    suspend fun resetSystemSettingsToDefaults(database: DittoDatabase) {
        val instance = ditto
        if (instance == null || activeDatabase?.id != database.id) {
            if (BuildConfig.DEBUG) {
                Log.i(TAG, "[Advanced] Reset requested for a database that is not open — no action needed")
            }
            return
        }
        // Adopt the saved config first: everything below re-applies from it, and the
        // manager's copy must not keep pointing at the pre-reset object.
        activeDatabase = database

        // STOP SYNC FIRST. `RESET ALL` clears the collection sync scopes, so running it
        // against a syncing instance leaves every collection replicable at the SDK
        // default `AllPeers` for the whole re-apply window — including ones the user
        // marked `LocalPeerOnly` — and permanently if any statement below throws. The
        // SDK also requires scopes to be set before `start_sync()`, so re-applying them
        // to a running session may not take effect at all.
        withContext(Dispatchers.IO) { instance.sync.stop() }
        if (BuildConfig.DEBUG) Log.i(TAG, "[Advanced] Sync stopped for system-settings reset")

        AdvancedSettingsApplier(DittoDQLExecutor(instance)).resetAllToDefaults()

        // Re-apply through the same OpenSequence used at open, so scopes are verified
        // before sync starts again.
        runOpenSequence(instance, database)
    }

    private suspend fun runOpenSequence(
        instance: Ditto,
        database: DittoDatabase,
    ): AdvancedApplyResult {
        val result = AdvancedSettingsApplier.OpenSequence(
            applier = AdvancedSettingsApplier(DittoDQLExecutor(instance)),
            applyTransportConfig = { applyTransportConfig(instance, database) },
            isStrictModeEnabled = database.isStrictModeEnabled,
            startSync = { withContext(Dispatchers.IO) { instance.sync.start() } },
        ).run(database.startupSettings, database.collectionSyncScopes)
        lastAdvancedApplyResult = result
        if (result.hasFailures || result.scopesUnverified) {
            // Operational summary (includes setting/collection names) — debug only.
            if (BuildConfig.DEBUG) {
                Log.w(TAG, "[Advanced] Open sequence completed with issues: $result")
            }
        }
        return result
    }

    private fun setupAuth(ditto: Ditto, database: DittoDatabase) {
        when (database.mode) {
            AuthMode.SERVER -> {
                ditto.auth?.expirationHandler = { d, secondsRemaining ->
                    if (BuildConfig.DEBUG) {
                        Log.i(TAG, "[Auth] Handler called, secondsRemaining=$secondsRemaining")
                    }
                    d.auth?.login(
                        token = database.token,
                        provider = DittoAuthenticationProvider.development(),
                    )
                }
            }
            AuthMode.SMALL_PEERS_ONLY -> {
                if (database.token.isNotEmpty()) {
                    runCatching { ditto.setOfflineOnlyLicenseToken(database.token) }
                        .onFailure { e ->
                            // Auth-adjacent — gated in case the SDK error echoes token material.
                            if (BuildConfig.DEBUG) {
                                Log.e(TAG, "[Auth] Failed to set offline license token: ${e.message}")
                            }
                        }
                }
            }
        }
    }

    suspend fun close() = closeCurrentInstance()

    fun currentInstance(): Ditto? = ditto

    fun applyTransportConfig(ditto: Ditto, database: DittoDatabase) {
        ditto.updateTransportConfig { builder ->
            builder.peerToPeer {
                bluetoothLe { enabled = database.isBluetoothLeEnabled }
                lan {
                    enabled = database.isLanEnabled
                    // VS Code extension parity: mDNS + multicast peer *discovery*
                    // ride the single LAN preference.
                    mdnsEnabled = database.isLanEnabled
                    multicastEnabled = database.isLanEnabled
                }
                wifiAware { enabled = database.isAwdlEnabled }
                val spec = database.toMulticastBetaSpec()
                multicastBeta {
                    enabled = spec.enabled
                    groupAddress = spec.groupAddress
                    port = spec.port
                    interfaceName = spec.interfaceName
                }
            }
            if (database.isCloudSyncEnabled && database.websocketUrl.isNotBlank()) {
                builder.connect {
                    websocketUrls = mutableSetOf(database.websocketUrl)
                }
            }
        }
        // The SDK holds its own engine-level multicast lock; this app-level lock
        // covers the process for the whole enabled period (Zava Retail pattern).
        // applyTransportConfig is the single chokepoint — it runs at open, at every
        // sync-start funnel, and at live apply — so the lock always tracks the flag.
        // NOTE: the SDK defers multicast changes while sync is active; every caller
        // reaches this function with sync stopped (open sequence / live apply both
        // stop sync first).
        if (database.isMulticastEnabled) {
            multicastLockController?.acquire()
        } else {
            multicastLockController?.release()
        }
    }

    private suspend fun closeCurrentInstance() {
        val current = ditto ?: return
        // Null out first so any concurrent calls to currentInstance() see null immediately
        ditto = null
        activeDatabase = null
        // Never keep the process-level multicast lock past a database session.
        multicastLockController?.release()
        withContext(Dispatchers.IO) {
            // close() cancels the Ditto coroutine scope and calls implementation.close(),
            // which releases the persistence-directory lock. Stopping sync alone is not
            // sufficient — without close() the next DittoFactory.create() call on the same
            // databaseId will fail with a file-lock error, causing hydration to throw and
            // subscriptions to never be loaded.
            runCatching { current.close() }
                .onFailure { e -> Log.w(TAG, "Error closing Ditto instance: ${e.message}") }
        }
    }

    /**
     * Applies the "Collect system metrics" preference to the process env the native
     * SDK reads at Ditto construction. No-op when preferences weren't injected
     * (unit tests construct DittoManager without them).
     */
    private suspend fun applySystemMetricsEnv() {
        val prefs = appPreferences ?: return
        val enabled = prefs.collectSystemMetrics.first()
        runCatching {
            if (enabled) {
                android.system.Os.setenv(SYSTEM_METRICS_ENV_VAR, "true", true)
            } else {
                android.system.Os.unsetenv(SYSTEM_METRICS_ENV_VAR)
            }
        }
    }

    private fun buildConfig(database: DittoDatabase): DittoConfig = when (database.mode) {
        AuthMode.SERVER -> DittoConfig(
            databaseId = database.databaseId,
            connect = DittoConfig.Connect.Server(url = database.authUrl),
        )
        AuthMode.SMALL_PEERS_ONLY -> DittoConfig(
            databaseId = database.databaseId,
            connect = DittoConfig.Connect.SmallPeersOnly(),
        )
    }
}

/**
 * The SDK `multicastBeta` builder fields derived from a persisted [DittoDatabase].
 * Pure mapping, extracted from [DittoManager.applyTransportConfig] so the
 * flag/group/port/interface wiring — including the UShort port coercion — is
 * unit-testable without a live Ditto instance.
 */
internal data class MulticastBetaSpec(
    val enabled: Boolean,
    val groupAddress: String,
    val port: UShort,
    val interfaceName: String?,
)

/**
 * Maps the persisted multicast columns to the SDK boundary. The port is coerced
 * with [Int.toUShort] exactly as the SDK field requires; out-of-range values
 * truncate (70000 → 4464) or hit the broken "any port" sentinel (0), which is
 * why the QR decode boundary and the Transport Settings UI both validate
 * 1..65535 before a config can reach this mapping.
 */
internal fun DittoDatabase.toMulticastBetaSpec(): MulticastBetaSpec = MulticastBetaSpec(
    enabled = isMulticastEnabled,
    groupAddress = multicastGroupAddress,
    port = multicastPort.toUShort(),
    interfaceName = multicastInterfaceName,
)
