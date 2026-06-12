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
    // The observer-editor sheet is hoisted into [ObserverEventsSection] (the always-composed
    // body) so it survives drawer dismiss below 840dp.
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
 *
 * Hosts the observer-editor [ObserverEditorSheet] so the sheet remains in composition even
 * when the list pane leaves it (e.g. when the Nav Drawer dismisses below 840dp).
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
        modifier = modifier,
    )

    // Editor sheet — hoisted here so it survives drawer dismiss below 840dp.
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
