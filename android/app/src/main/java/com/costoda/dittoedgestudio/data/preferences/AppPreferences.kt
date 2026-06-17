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
class AppPreferences(private val store: DataStore<Preferences>) {

    val metricsEnabled: Flow<Boolean> =
        store.data.map { it[KEY_METRICS_ENABLED] ?: DEFAULT_METRICS_ENABLED }

    suspend fun setMetricsEnabled(enabled: Boolean) {
        store.edit { it[KEY_METRICS_ENABLED] = enabled }
    }

    companion object {
        private const val DEFAULT_METRICS_ENABLED = true
        private val KEY_METRICS_ENABLED = booleanPreferencesKey("metrics_enabled")
    }
}

/** Application-singleton DataStore. Lives at `app/files/datastore/app_prefs.preferences_pb`. */
val Context.appPreferencesDataStore: DataStore<Preferences> by preferencesDataStore("app_prefs")
