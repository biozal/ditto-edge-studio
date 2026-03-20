package com.costoda.dittoedgestudio.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AppMetricsViewModel(
    private val context: Context,
    private val appMetricsRepository: AppMetricsRepository,
    private val dittoManager: DittoManager,
) : ViewModel() {

    private val _metrics = MutableStateFlow<AppMetrics?>(null)
    val metrics: StateFlow<AppMetrics?> = _metrics.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _lastUpdatedText = MutableStateFlow("Never")
    val lastUpdatedText: StateFlow<String> = _lastUpdatedText.asStateFlow()

    private var refreshJob: Job? = null

    fun startAutoRefresh() {
        if (refreshJob?.isActive == true) return
        refreshJob = viewModelScope.launch {
            while (true) {
                refresh()
                delay(15_000)
            }
        }
    }

    fun stopAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = null
    }

    suspend fun refresh() {
        _isLoading.value = true
        runCatching {
            val snapshot = appMetricsRepository.snapshot(context, dittoManager.currentInstance())
            _metrics.value = snapshot
            _lastUpdatedText.value = formatRelativeTime(snapshot.capturedAt)
        }
        _isLoading.value = false
    }

    override fun onCleared() {
        super.onCleared()
        stopAutoRefresh()
    }

    private fun formatRelativeTime(capturedAtMs: Long): String {
        val elapsedSecs = (System.currentTimeMillis() - capturedAtMs) / 1000
        return when {
            elapsedSecs < 5 -> "Just now"
            elapsedSecs < 60 -> "${elapsedSecs}s ago"
            elapsedSecs < 3600 -> "${elapsedSecs / 60}m ago"
            else -> "Long ago"
        }
    }
}
