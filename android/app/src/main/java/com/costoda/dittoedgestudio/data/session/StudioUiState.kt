package com.costoda.dittoedgestudio.data.session

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.EventFilterMode
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import com.costoda.dittoedgestudio.domain.model.QueryResult
import com.costoda.dittoedgestudio.viewmodel.QueryInspectorTab
import kotlinx.coroutines.flow.MutableStateFlow

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
 *
 * The [queryWorkbench] sub-object owns the Query Workbench's editor / results / inspector
 * state as `MutableStateFlow`s (Task 4.3e). It lives on the session so it survives rail
 * switches: each new [com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel] (one per
 * `QueryKey` entry composition) re-exposes the *same* flow instances, so the user's draft
 * query, results, pagination cursor, and inspector tab selection all persist across
 * Observers ⇄ Query navigation.
 */
class StudioUiState {
    var selectedObserver by mutableStateOf<DittoObservable?>(null)
    var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
    var editingObserver by mutableStateOf<DittoObservable?>(null)
    var editingSubscription by mutableStateOf<com.costoda.dittoedgestudio.domain.model.DittoSubscription?>(null)
    var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
    var eventPageSize by mutableStateOf(25)
    var eventCurrentPage by mutableStateOf(0)
    var transportConfigVisible by mutableStateOf(false)
    var showAddIndex by mutableStateOf(false)

    /**
     * Inspector visibility. Null until the scaffold initializes it from the window size class
     * default on first composition.
     */
    var inspectorVisible by mutableStateOf<Boolean?>(null)

    /**
     * Session-scoped state for the Query Workbench. See [QueryWorkbenchState].
     */
    val queryWorkbench: QueryWorkbenchState = QueryWorkbenchState()
}

/**
 * Session-scoped state holder for the Query Workbench (Task 4.3e).
 *
 * Holds editor draft, results, pagination, and inspector state as [MutableStateFlow]s so the
 * Query section's `QueryEditorViewModel` can be re-created on each `QueryKey` entry
 * composition without losing user-visible state. Each VM instance reads/writes these flows
 * directly; the flows live as long as the [StudioSession] (i.e. the studio scope).
 *
 * Why MutableStateFlow (not `mutableStateOf` like the rest of [StudioUiState])?
 * - The legacy `QueryEditorViewModel` already used `MutableStateFlow` + `combine` operators
 *   for derived flows ([com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel.displayedDocuments],
 *   `pageSizeOptions`). Keeping the same type lets the VM expose the flows verbatim with
 *   minimal diff.
 * - StateFlow integrates cleanly with `collectAsStateWithLifecycle()` used throughout the
 *   inspector and editor composables.
 */
class QueryWorkbenchState {
    val queryText = MutableStateFlow("")
    val isExecuting = MutableStateFlow(false)
    val executionError = MutableStateFlow<String?>(null)
    val queryResult = MutableStateFlow<QueryResult?>(null)
    val currentPage = MutableStateFlow(0)
    val pageSize = MutableStateFlow(25)
    val selectedInspectorTab = MutableStateFlow(QueryInspectorTab.HISTORY)
    val selectedDocument = MutableStateFlow<Map<String, Any?>?>(null)
    val queryMetrics = MutableStateFlow<QueryMetrics?>(null)
    val isFavorited = MutableStateFlow(false)

    /** Last-saved history id, used to link metrics rows back to a history entry. Survives
     *  rail switches just like the rest of the workbench state. */
    var lastHistoryId: Long = -1L
}
