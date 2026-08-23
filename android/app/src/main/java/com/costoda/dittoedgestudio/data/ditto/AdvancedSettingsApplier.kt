package com.costoda.dittoedgestudio.data.ditto

import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.repository.parseJsonToMap
import com.costoda.dittoedgestudio.domain.model.AdvancedApplyResult
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsDql
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsValidator
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.ditto.kotlin.Ditto
import org.json.JSONObject

/**
 * Minimal DQL execution surface, so the advanced-settings apply logic can be tested
 * with a recording fake instead of a live Ditto instance.
 */
interface DQLExecuting {
    /** Runs [query] and returns each result item's value map. */
    suspend fun runDQL(query: String, arguments: Map<String, Any?>): List<Map<String, Any?>>
}

class DittoDQLExecutor(private val ditto: Ditto) : DQLExecuting {
    override suspend fun runDQL(
        query: String,
        arguments: Map<String, Any?>,
    ): List<Map<String, Any?>> = ditto.store.execute(query, arguments) { result ->
        result.items.map { item ->
            runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                .getOrDefault(emptyMap())
        }
    }
}

/**
 * Applies a database's Advanced Configuration to an open Ditto instance.
 *
 * Split out of [DittoManager] for two reasons: the statement order relative to
 * `sync.start()` is safety-critical and needs a unit test that doesn't require
 * credentials, and the two lists need **opposite failure policies**:
 *
 * - **Startup settings** are tuning knobs → best-effort. One bad parameter name is
 *   reported, not fatal.
 * - **Sync scopes** are a data-containment control → fail-closed. If they cannot be
 *   applied and verified, the caller must not start sync, because "scope missing"
 *   means data the user marked device-local would replicate.
 *
 * Port of SwiftUI `AdvancedSettingsApplier` — see docs/ADVANCED_DATABASE_CONFIG.md.
 */
class AdvancedSettingsApplier(private val executor: DQLExecuting) {

    sealed class ApplyError(message: String) : Exception(message) {
        data class ScopeStatementFailed(val collections: List<String>, val underlying: String) :
            ApplyError(
                "Could not apply collection sync scopes for ${collections.joinToString(", ")}. " +
                    "The database was not opened, to avoid syncing data you marked device-local. " +
                    "($underlying)",
            )

        data class ScopeVerificationMismatch(
            val expected: Map<String, String>,
            val actual: Map<String, String>,
        ) : ApplyError(
            "Collection sync scopes were not stored as requested " +
                "(expected $expected, found $actual). The database was not opened, " +
                "to avoid syncing data you marked device-local.",
        )

        data class InvalidScopes(val detail: String) :
            ApplyError("Collection sync scopes are invalid: $detail. The database was not opened.")
    }

    // MARK: - Startup Settings (best-effort)

    /**
     * Applies each startup setting independently. A failure is recorded and skipped
     * rather than aborting: an unrecognized parameter name is a typo, not a reason to
     * lock the user out of their database.
     */
    suspend fun applyStartupSettings(settings: List<StartupSetting>): AdvancedApplyResult {
        var applied = listOf<String>()
        var skipped = listOf<AdvancedApplyResult.Skipped>()
        if (settings.isEmpty()) return AdvancedApplyResult()

        // Whole-list validation, not per-row: `validateSetting(setting, others = [])`
        // cannot see duplicates, and the row cap was only ever enforced in the editor —
        // so a hand-edited or imported config could issue thousands of statements, or
        // two conflicting writes to one parameter, silently.
        val (allowed, rejected) = AdvancedSettingsValidator.partitionSettings(settings)
        skipped = skipped + rejected.map { (setting, error) ->
            AdvancedApplyResult.Skipped(setting.syncKey, error.message)
        }

        for (setting in allowed) {
            val name = setting.syncKey
            val typedValue = setting.typedValue()
            if (typedValue == null) {
                skipped = skipped + AdvancedApplyResult.Skipped(name, "Value could not be converted.")
                continue
            }
            try {
                executor.runDQL(
                    AdvancedSettingsDql.settingStatement(setting),
                    mapOf("value" to typedValue.argumentValue()),
                )
                applied = applied + name
            } catch (e: Exception) {
                skipped = skipped + AdvancedApplyResult.Skipped(name, e.message ?: e.toString())
            }
        }

        if (BuildConfig.DEBUG) {
            if (applied.isEmpty() && skipped.isEmpty()) {
                Log.i(TAG, "[Advanced] No startup settings to apply")
            } else {
                Log.i(TAG, "[Advanced] Startup settings applied=${applied.size} skipped=${skipped.size}")
                skipped.forEach { Log.w(TAG, "[Advanced] Skipped startup setting '${it.name}': ${it.reason}") }
            }
        }
        return AdvancedApplyResult(appliedSettings = applied, skippedSettings = skipped)
    }

    // MARK: - Sync Scopes (fail-closed)

    /**
     * Applies the sync scopes and verifies them by reading the parameter back.
     *
     * @return how many collections were scoped, and whether the read-back confirmed them.
     * @throws ApplyError if the statement fails, the scopes are invalid, or the read-back
     *   disagrees with what was requested. The caller must not start sync on throw.
     */
    suspend fun applySyncScopes(scopes: List<CollectionSyncScope>): Pair<Int, Boolean> {
        val map = try {
            AdvancedSettingsDql.scopeMap(scopes)
        } catch (e: Exception) {
            throw ApplyError.InvalidScopes(e.message ?: e.toString())
        }

        // NOTE: an empty map still issues the statement. `ALTER SYSTEM` state is
        // in-memory and lives as long as the instance, so returning early on "no scopes"
        // meant deleting the last scope row never took effect — the SDK kept enforcing
        // the old `LocalPeerOnly` while the UI showed none, and the re-apply reported
        // success having sent nothing.
        try {
            executor.runDQL(AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY, mapOf("scopes" to map))
        } catch (e: Exception) {
            throw ApplyError.ScopeStatementFailed(
                collections = map.keys.sorted(),
                underlying = e.message ?: e.toString(),
            )
        }

        // Verify. The SDK accepts the statement silently, so a read-back is the only
        // proof the containment the user asked for is actually in effect.
        return when (val readback = readSyncScopes()) {
            is ScopeReadback.Parsed -> {
                val actual = readback.map
                // Subset, not equality: the instance may legitimately carry scopes this
                // config did not set (e.g. one applied by a query the user ran), and
                // demanding an exact match would refuse to open the database over it.
                for ((collection, expected) in map) {
                    val found = actual[collection]
                    if (found == null || found != expected) {
                        throw ApplyError.ScopeVerificationMismatch(expected = map, actual = actual)
                    }
                }
                // Clearing case: nothing was requested, so nothing of ours may remain. A
                // leftover scope here means some other writer set it (a query the user ran),
                // which we report rather than treat as our own success.
                if (map.isEmpty() && actual.isNotEmpty()) {
                    if (BuildConfig.DEBUG) {
                        Log.w(
                            TAG,
                            "[Advanced] Requested no sync scopes but the instance still reports " +
                                "${actual.size}: ${actual.keys.sorted().joinToString(", ")}",
                        )
                    }
                    return 0 to false
                }
                if (BuildConfig.DEBUG) {
                    Log.i(TAG, "[Advanced] Sync scopes verified for ${map.size} collection(s)")
                }
                map.size to true
            }

            ScopeReadback.Unavailable -> {
                // The write succeeded; only the read-back is unusable. Don't block the
                // open — but never report this as verified either.
                if (BuildConfig.DEBUG) {
                    Log.w(
                        TAG,
                        "[Advanced] Applied ${map.size} sync scope(s) but could NOT verify them via " +
                            "'${AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY}'. Treating as unverified.",
                    )
                }
                map.size to false
            }
        }
    }

    private sealed interface ScopeReadback {
        data class Parsed(val map: Map<String, String>) : ScopeReadback
        data object Unavailable : ScopeReadback
    }

    /**
     * Reads the current scope map.
     *
     * Deliberately does **not** fall back to "the first value in the row": on an
     * unordered map that picks an arbitrary element, making verification succeed or
     * fail unpredictably. Only known keys are consulted, and the `SHOW` statement
     * itself is allowed to fail without bricking every database that uses scopes.
     */
    private suspend fun readSyncScopes(): ScopeReadback {
        val rows = try {
            executor.runDQL(AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY, emptyMap())
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) {
                Log.w(TAG, "[Advanced] Sync scope read-back query failed: ${e.message}")
            }
            return ScopeReadback.Unavailable
        }

        for (row in rows) {
            // Shape A: keyed by the parameter name (any case).
            for ((key, value) in row) {
                if (key.equals(AdvancedSettingsDql.SYNC_SCOPES_READ_PARAMETER, ignoreCase = true)) {
                    coerceScopeMap(value)?.let { return ScopeReadback.Parsed(it) }
                }
            }
            // Shape B: a name/value row, e.g. {"name": "user_collection_sync_scopes", "value": {...}}.
            val name = row["name"] as? String
            if (name != null && name.equals(AdvancedSettingsDql.SYNC_SCOPES_READ_PARAMETER, ignoreCase = true)) {
                coerceScopeMap(row["value"])?.let { return ScopeReadback.Parsed(it) }
            }
        }
        return ScopeReadback.Unavailable
    }

    /** Accepts a map of strings or a JSON object string; anything else is unreadable. */
    private fun coerceScopeMap(raw: Any?): Map<String, String>? = when (raw) {
        null -> null
        is Map<*, *> -> {
            val out = mutableMapOf<String, String>()
            for ((key, value) in raw) {
                if (key !is String || value !is String) return null
                out[key] = value
            }
            out
        }
        is String -> runCatching {
            val obj = JSONObject(raw)
            val out = mutableMapOf<String, String>()
            for (key in obj.keys()) {
                val value = obj.get(key)
                if (value !is String) return null
                out[key] = value
            }
            out
        }.getOrNull()
        else -> null
    }

    // MARK: - Open Sequence

    /**
     * The statement sequence a database open must perform, in order.
     *
     * Extracted from [DittoManager.hydrate] so a test can observe the **real**
     * ordering. Two invariants this type exists to guarantee:
     * 1. The user's startup settings run **before** the app's own `ALTER SYSTEM`
     *    statements, so app-managed parameters win.
     * 2. Sync scopes are applied **and** [startSync] is never reached if they fail —
     *    the SDK requires scopes before `start_sync()`, and a missing `LocalPeerOnly`
     *    means data the user marked device-local replicates.
     *
     * (`mesh_chooser_max_wlan_clients` from the SwiftUI sequence is macOS-only and has
     * no Android equivalent.)
     */
    class OpenSequence(
        private val applier: AdvancedSettingsApplier,
        /** Applies the peer-to-peer transport configuration (an SDK call, not DQL). */
        private val applyTransportConfig: suspend () -> Unit,
        private val isStrictModeEnabled: Boolean,
        private val startSync: suspend () -> Unit,
    ) {
        suspend fun run(
            startupSettings: List<StartupSetting>,
            syncScopes: List<CollectionSyncScope>,
        ): AdvancedApplyResult {
            // 1. User settings first, so anything Edge Studio manages overrides them.
            var result = applier.applyStartupSettings(startupSettings)

            // 2. Transports.
            applyTransportConfig()

            // 3. App-managed parameters.
            applier.executor.runDQL(
                "ALTER SYSTEM SET DQL_STRICT_MODE = ${if (isStrictModeEnabled) "true" else "false"}",
                emptyMap(),
            )

            // 4. Sync scopes — fail-closed, so a throw here means startSync is never
            //    reached and the caller aborts the open.
            val (appliedScopes, verified) = applier.applySyncScopes(syncScopes)
            result = result.copy(appliedScopeCount = appliedScopes, scopesUnverified = !verified)

            // 5. Only now may sync start.
            startSync()
            return result
        }
    }

    /**
     * Restores every system parameter to its SDK default.
     *
     * Callers must re-apply everything the app manages afterwards — transport
     * configuration, `DQL_STRICT_MODE` and the sync scopes — because this resets
     * *all* parameters, not just the user's.
     */
    suspend fun resetAllToDefaults() {
        executor.runDQL(AdvancedSettingsDql.RESET_ALL_QUERY, emptyMap())
        if (BuildConfig.DEBUG) Log.i(TAG, "[Advanced] ALTER SYSTEM RESET ALL issued")
    }

    private companion object {
        const val TAG = "AdvancedSettings"
    }
}
