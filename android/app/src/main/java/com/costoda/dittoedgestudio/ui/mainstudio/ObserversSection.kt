package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

/**
 * The "Observers" scene-driven section entry-point composable (Task 4.3).
 *
 * Two variants:
 *  - [ObserversListSection]   — list-pane content (used by entry<ObserversKey>)
 *  - [ObserverEventsSection]  — detail-pane content (used by entry<ObserverEventsKey>)
 *
 * Both share the same [MainStudioViewModel] (resolved per entry via Koin's scope; the same
 * scope id ensures both entries see the same [com.costoda.dittoedgestudio.data.session.StudioSession]).
 *
 * The list pane delegates row-tap handling to the caller so the AppNavGraph can decide
 * whether to push [com.costoda.dittoedgestudio.ui.navigation.ObserverEventsKey] (the
 * adaptive ListDetailSceneStrategy then transparently chooses between drill-in (compact)
 * and side-by-side (expanded)).
 */
@Composable
fun ObserversListSection(
    viewModel: MainStudioViewModel,
    onObserverPicked: (DittoObservable) -> Unit,
    modifier: Modifier = Modifier,
    onAfterAddTriggered: (() -> Unit)? = null,
) {
    // The observer-editor sheet is hosted by [ObserverEditorHost], rendered once by the
    // entry<ObserversKey> composable — see the note on that function for why it cannot live
    // in either pane.
    ObserversListPane(
        viewModel = viewModel,
        onSelectObserver = onObserverPicked,
        modifier = modifier,
        onAfterAddTriggered = onAfterAddTriggered,
    )
}

/**
 * Detail-pane content for a single observer. Renders the existing [ObserverDetailScreen]
 * (events table + event detail + change-type filter), wired through the shared
 * [MainStudioViewModel]. The list-pane "select observer" call already toggled the VM's
 * [MainStudioViewModel.selectedObserver], so this composable does not need any per-call args.
 */
@Composable
fun ObserverEventsSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    ObserverDetailScreen(
        selectedObserver = viewModel.selectedObserver,
        events = viewModel.selectedObserverEvents(),
        selectedEvent = viewModel.selectedEvent,
        filterMode = viewModel.eventFilterMode,
        onSelectEvent = { viewModel.selectEvent(it) },
        onFilterChange = { viewModel.eventFilterMode = it },
        pageSize = viewModel.eventPageSize,
        currentPage = viewModel.eventCurrentPage,
        onPageSizeChange = { size ->
            viewModel.eventPageSize = size
            viewModel.eventCurrentPage = 0
        },
        onPageChange = { viewModel.eventCurrentPage = it },
        modifier = modifier,
    )
}

/**
 * Hosts the observer-editor [ObserverEditorSheet]. Render this exactly once from the
 * `entry<ObserversKey>` composable — never from either pane.
 *
 * The sheet used to live in [ObserverEventsSection], on the assumption that it was the
 * always-composed body. That holds below 600dp, but not above it: there the list pane is the
 * body and the detail area falls back to `ObserverEventsPlaceholder` (a bare Text) until an
 * observer is selected. So [ObserverEventsSection] was absent from composition in exactly the
 * first-run case — empty list, nothing selected — and the "+" FAB set `editingObserver` with
 * no renderer listening. The button did nothing.
 *
 * `entry<ObserversKey>` is the one composable present in every regime: it is the whole body
 * below 600dp, and the list pane of the list-detail scene above it (where it stays composed
 * alongside a pushed `ObserverEventsKey`). Hosting here therefore yields exactly one live
 * sheet at every width, selected or not, and it survives drawer dismissal for free.
 */
@Composable
fun ObserverEditorHost(viewModel: MainStudioViewModel) {
    viewModel.editingObserver?.let { observer ->
        ObserverEditorSheet(
            initial = observer,
            onSave = { name, query ->
                if (observer.id == 0L) viewModel.addObserver(name, query)
                else viewModel.updateObserver(observer, name, query)
            },
            onDismiss = { viewModel.editingObserver = null },
        )
    }
}
