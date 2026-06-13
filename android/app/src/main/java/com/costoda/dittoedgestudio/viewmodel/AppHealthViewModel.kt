package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.db.DatabaseOpenResult
import com.costoda.dittoedgestudio.data.db.DatabaseOpener
import com.costoda.dittoedgestudio.data.db.DatabaseRecovery
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * App-root health state. Probes the database at app start (see [DatabaseOpener]) and
 * exposes a [StateFlow] the root composable forks on: a healthy DB drops into the
 * normal Nav3 graph; a key failure drives the `KeyFailureScreen`.
 *
 * The recovery path ([recover]) is only called from an explicit user tap and runs
 * [DatabaseRecovery.reset]: wipe DB files + Ditto dir + Keystore alias, then re-probe.
 * After a successful recovery the activity is expected to `recreate()` so a fresh
 * Koin graph (notably `AppDatabase`) is rebuilt.
 *
 * See plans/android/config-loss-investigation.md (item B3).
 */
sealed class DbHealthState {
    object Initializing : DbHealthState()
    object Healthy : DbHealthState()
    data class KeyFailure(
        val throwable: Throwable,
        val errorSummary: String,
    ) : DbHealthState()
}

class AppHealthViewModel(
    private val opener: DatabaseOpener,
    private val recovery: DatabaseRecovery,
    // ioDispatcher is injectable so unit tests can use a TestDispatcher and drive
    // `advanceUntilIdle` deterministically. Production resolves to Dispatchers.IO via Koin.
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {

    private val _state = MutableStateFlow<DbHealthState>(DbHealthState.Initializing)
    val state: StateFlow<DbHealthState> = _state.asStateFlow()

    init {
        probe()
    }

    /**
     * Run the open + probe on IO and update [state]. Idempotent; safe to call again
     * after [recover].
     */
    fun probe() {
        viewModelScope.launch {
            _state.value = DbHealthState.Initializing
            val result = withContext(ioDispatcher) { opener.openAndProbe() }
            _state.value = result.toHealthState()
        }
    }

    /**
     * User-triggered reset. Invokes the [onComplete] callback when the post-reset re-probe
     * finishes. On success the [state] transitions back to Healthy; on failure (extremely
     * unlikely — would mean we couldn't delete files OR the new key didn't open the new
     * empty file) it transitions to KeyFailure with the new throwable.
     */
    fun recover(onComplete: (success: Boolean) -> Unit) {
        viewModelScope.launch {
            _state.value = DbHealthState.Initializing
            val resetOk = withContext(ioDispatcher) { recovery.reset() }
            val result = withContext(ioDispatcher) { opener.openAndProbe() }
            _state.value = result.toHealthState()
            onComplete(resetOk && result is DatabaseOpenResult.Ok)
        }
    }

    private fun DatabaseOpenResult.toHealthState(): DbHealthState = when (this) {
        is DatabaseOpenResult.Ok -> DbHealthState.Healthy
        is DatabaseOpenResult.KeyFailure -> DbHealthState.KeyFailure(
            throwable = throwable,
            errorSummary = errorSummary,
        )
    }
}
