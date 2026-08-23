package com.costoda.dittoedgestudio.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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

    companion object {
        private const val DEFAULT_METRICS_ENABLED = true
        private const val DEFAULT_PRESENCE_SPLIT_VIEW = false
        private val KEY_METRICS_ENABLED = booleanPreferencesKey("metrics_enabled")
        private val KEY_PRESENCE_SPLIT_VIEW = booleanPreferencesKey("presence_split_view")
    }
}

/** Application-singleton DataStore. Lives at `app/files/datastore/app_prefs.preferences_pb`. */
val Context.appPreferencesDataStore: DataStore<Preferences> by preferencesDataStore("app_prefs")
