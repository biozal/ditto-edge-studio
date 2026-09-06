package com.costoda.dittoedgestudio.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.costoda.dittoedgestudio.domain.model.SystemMetricSeriesRef
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Persistent user preferences for the Studio app, backed by Jetpack DataStore (Preferences).
 *
 * Currently exposes [metricsEnabled] — the "Collect Metrics" toggle that mirrors SwiftUI's
 * AppStorage key of the same purpose. When ON, the Query Workbench captures execution
 * profiles for SELECT statements (PROFILE prefix injection in QueryEditorViewModel).
 */
class AppPreferences(private val store: DataStore<Preferences>) : AppPreferencesGateway {

    override val metricsEnabled: Flow<Boolean> =
        store.data.map { it[KEY_METRICS_ENABLED] ?: DEFAULT_METRICS_ENABLED }

    override suspend fun setMetricsEnabled(enabled: Boolean) {
        store.edit { it[KEY_METRICS_ENABLED] = enabled }
    }

    override val presenceSplitView: Flow<Boolean> =
        store.data.map { it[KEY_PRESENCE_SPLIT_VIEW] ?: DEFAULT_PRESENCE_SPLIT_VIEW }

    override suspend fun setPresenceSplitView(enabled: Boolean) {
        store.edit { it[KEY_PRESENCE_SPLIT_VIEW] = enabled }
    }

    override val showWelcomeOnNewDatabase: Flow<Boolean> =
        store.data.map { it[KEY_SHOW_WELCOME] ?: DEFAULT_SHOW_WELCOME }

    override suspend fun setShowWelcomeOnNewDatabase(enabled: Boolean) {
        store.edit { it[KEY_SHOW_WELCOME] = enabled }
    }

    override val collectSystemMetrics: Flow<Boolean> =
        store.data.map { it[KEY_COLLECT_SYSTEM_METRICS] ?: DEFAULT_COLLECT_SYSTEM_METRICS }

    override suspend fun setCollectSystemMetrics(enabled: Boolean) {
        store.edit { it[KEY_COLLECT_SYSTEM_METRICS] = enabled }
    }

    override fun systemMetricPins(databaseId: Long): Flow<List<SystemMetricSeriesRef>> =
        store.data.map { prefs -> decodePins(prefs[pinsKey(databaseId)]) }

    override suspend fun setSystemMetricPins(databaseId: Long, pins: List<SystemMetricSeriesRef>) {
        val unique = dedupePins(pins)
        store.edit { prefs ->
            // An empty list removes the key entirely, so "Clear" leaves no residue.
            if (unique.isEmpty()) {
                prefs.remove(pinsKey(databaseId))
            } else {
                prefs[pinsKey(databaseId)] = json.encodeToString(unique.map(::StoredPin))
            }
        }
    }

    /** DataStore is user-editable and older builds may have written a different
     *  shape under the same versioned key family — a value that no longer parses
     *  reads as "no pins" rather than failing the screen. */
    private fun decodePins(raw: String?): List<SystemMetricSeriesRef> {
        if (raw.isNullOrBlank()) return emptyList()
        val stored = runCatching { json.decodeFromString<List<StoredPin>>(raw) }.getOrNull()
            ?: return emptyList()
        return dedupePins(stored.mapNotNull { it.toRef() })
    }

    /** First-occurrence-wins. Pins are a SET presented in pin order: the same
     *  series may never appear twice, whichever writer produced the input. Both
     *  the read and the write path funnel through here. */
    private fun dedupePins(pins: List<SystemMetricSeriesRef>): List<SystemMetricSeriesRef> =
        pins.distinctBy { it.id }

    @Serializable
    private data class StoredPin(val key: String, val labels: Map<String, String>) {
        constructor(ref: SystemMetricSeriesRef) : this(ref.key, ref.labels)

        fun toRef(): SystemMetricSeriesRef? =
            if (key.isEmpty()) null else SystemMetricSeriesRef(key, labels)
    }

    companion object {
        private const val DEFAULT_METRICS_ENABLED = true
        private const val DEFAULT_PRESENCE_SPLIT_VIEW = false
        private const val DEFAULT_SHOW_WELCOME = true
        private const val DEFAULT_COLLECT_SYSTEM_METRICS = true
        private val KEY_METRICS_ENABLED = booleanPreferencesKey("metrics_enabled")
        private val KEY_PRESENCE_SPLIT_VIEW = booleanPreferencesKey("presence_split_view")
        private val KEY_SHOW_WELCOME = booleanPreferencesKey("show_welcome_on_new_database")
        private val KEY_COLLECT_SYSTEM_METRICS = booleanPreferencesKey("collect_system_metrics")

        private val json = Json { ignoreUnknownKeys = true }

        /** Versioned per-database key, mirroring the SwiftUI defaults key
         *  `dittoSystemMetricsPins.v1.<databaseId>`. */
        private fun pinsKey(databaseId: Long) =
            stringPreferencesKey("system_metrics_pins_v1_$databaseId")
    }
}

/** Application-singleton DataStore. Lives at `app/files/datastore/app_prefs.preferences_pb`. */
val Context.appPreferencesDataStore: DataStore<Preferences> by preferencesDataStore("app_prefs")
