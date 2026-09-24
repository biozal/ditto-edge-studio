package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * ViewModel for the Settings screen. Currently exposes only the "Collect Metrics"
 * toggle — the Android counterpart of SwiftUI's Settings → "Collect Metrics"
 * (`AppPreferencesView`), backed by the same [AppPreferencesGateway.metricsEnabled]
 * preference that gates metrics capture and the App/Query Metrics rail items.
 */
class SettingsViewModel(
    private val appPreferences: AppPreferencesGateway,
) : ViewModel() {

    val metricsEnabled: StateFlow<Boolean> = appPreferences.metricsEnabled
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)

    val presenceSplitView: StateFlow<Boolean> = appPreferences.presenceSplitView
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    val collectSystemMetrics: StateFlow<Boolean> = appPreferences.collectSystemMetrics
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)

    fun setMetricsEnabled(enabled: Boolean) {
        viewModelScope.launch { appPreferences.setMetricsEnabled(enabled) }
    }

    fun setCollectSystemMetrics(enabled: Boolean) {
        viewModelScope.launch { appPreferences.setCollectSystemMetrics(enabled) }
    }

    fun setPresenceSplitView(enabled: Boolean) {
        viewModelScope.launch { appPreferences.setPresenceSplitView(enabled) }
    }
}
