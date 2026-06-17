package com.costoda.dittoedgestudio.data.preferences

import kotlinx.coroutines.flow.Flow

/**
 * Test-friendly façade over [AppPreferences]. The production implementation is the
 * concrete [AppPreferences] class (DataStore-backed); unit tests can supply an
 * in-memory fake without bringing DataStore into the test classpath.
 */
interface AppPreferencesGateway {
    val metricsEnabled: Flow<Boolean>
    suspend fun setMetricsEnabled(enabled: Boolean)
}
