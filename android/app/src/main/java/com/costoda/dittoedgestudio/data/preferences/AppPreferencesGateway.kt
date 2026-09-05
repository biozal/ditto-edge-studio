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

    /**
     * Presence section layout: when true (and width ≥600dp) the subscriptions list sits
     * beside the peers view; when false the peers view / Presence Viewer gets the full
     * width and the subscriptions list opens from the Presence toolbar (or the drawer
     * below 600dp). Default false — the Viewer needs the full width to be effective.
     */
    val presenceSplitView: Flow<Boolean>
    suspend fun setPresenceSplitView(enabled: Boolean)

    /**
     * "Show this screen when opening a new database" toggle for the Welcome
     * screen (parity with SwiftUI's `showWelcomeOnNewDatabase` AppStorage).
     * Default true — fresh databases get the onboarding tour.
     */
    val showWelcomeOnNewDatabase: Flow<Boolean>
    suspend fun setShowWelcomeOnNewDatabase(enabled: Boolean)

    /**
     * Whether the SDK 5.1 `system:metrics` exporter is enabled before Ditto opens.
     * Startup-gated in the SDK (runtime changes are ignored), so the toggle's effect
     * applies at the next database open. Default true (extension parity).
     */
    val collectSystemMetrics: Flow<Boolean>
    suspend fun setCollectSystemMetrics(enabled: Boolean)
}
