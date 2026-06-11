package com.costoda.dittoedgestudio.data.session

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

/**
 * Session-scoped ephemeral UI state for the studio.
 *
 * Lives on [StudioSession] so it survives rail-section switches (each section entry gets a
 * fresh [com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel], but the session — and
 * therefore this object — is reused for the same databaseId). The state resets naturally
 * when the session closes on studio exit.
 *
 * All properties are Compose snapshot-state (`mutableStateOf`) so any composable that reads
 * them is automatically recomposed on change.
 *
 * [inspectorVisible] is nullable: `null` means "not yet initialized by the scaffold"; the
 * scaffold reads it as `value ?: windowSizeClass.inspectorDefaultVisible` and sets it on
 * first toggle so subsequent section switches preserve the user's choice.
 */
class StudioUiState {
    var selectedObserver by mutableStateOf<DittoObservable?>(null)
    var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
    var editingObserver by mutableStateOf<DittoObservable?>(null)
    var editingSubscription by mutableStateOf<com.costoda.dittoedgestudio.domain.model.DittoSubscription?>(null)
    var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
    var eventPageSize by mutableStateOf(25)
    var eventCurrentPage by mutableStateOf(0)
    var bottomBarExpanded by mutableStateOf(true)
    var transportConfigVisible by mutableStateOf(false)
    var fabMenuExpanded by mutableStateOf(false)
    var connectionPopupVisible by mutableStateOf(false)
    var showAddIndex by mutableStateOf(false)

    /**
     * Inspector visibility. Null until the scaffold initializes it from the window size class
     * default on first composition.
     */
    var inspectorVisible by mutableStateOf<Boolean?>(null)
}
