package com.costoda.dittoedgestudio.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.repository.DatabaseMetricsRepository
import com.costoda.dittoedgestudio.domain.model.DatabaseMetrics
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * VM for the "Database Metrics" rail item (the screen target shown in
 * `screens/database-metrics-vsc.png`). Snapshots are expensive — the repo walks
 * the SDK disk-usage tree and reads every document's CBOR payload — so this VM
 * intentionally has **no auto-refresh**. The first snapshot runs on construction
 * and subsequent updates are triggered manually via [refresh].
 */
class DiskUsageViewModel(
    private val dittoManager: DittoManager,
    private val repo: DatabaseMetricsRepository,
) : ViewModel() {

    private val _metrics = MutableStateFlow<DatabaseMetrics?>(null)
    val metrics: StateFlow<DatabaseMetrics?> = _metrics.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** Epoch-millis of the last successful snapshot, or null if none yet. */
    private val _lastUpdatedAt = MutableStateFlow<Long?>(null)
    val lastUpdatedAt: StateFlow<Long?> = _lastUpdatedAt.asStateFlow()

    /** Tracks the in-flight refresh so concurrent invocations (double-tap, etc.) are ignored. */
    private var refreshJob: Job? = null

    init {
        refresh()
    }

    fun refresh() {
        // Synchronous guard: if a snapshot is already running, drop this request rather than
        // launching an overlapping one. The IconButton is also disabled while isLoading,
        // but the flag is set inside the coroutine — this check closes the dispatch gap.
        if (refreshJob?.isActive == true) return
        refreshJob = viewModelScope.launch {
            _isLoading.value = true
            try {
                val ditto = dittoManager.currentInstance()
                    ?: error("No active Ditto instance")
                val snap = repo.snapshot(ditto)
                _metrics.value = snap
                _lastUpdatedAt.value = snap.capturedAt
            } catch (c: CancellationException) {
                // Preserve structured concurrency — never swallow a cancellation.
                throw c
            } catch (t: Throwable) {
                Log.w(TAG, "Database metrics snapshot failed", t)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private companion object {
        const val TAG = "DiskUsageVM"
    }
}
