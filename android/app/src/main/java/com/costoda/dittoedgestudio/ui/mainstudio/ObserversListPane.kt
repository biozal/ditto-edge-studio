package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

/**
 * List pane for the Observers section (Task 4.3 scene-driven shell).
 *
 * Renders the registered observers as a vertical list, mirroring the per-observer
 * UI from [DataPanel] / [PhoneDrawerContent] in the legacy [MainStudioScreen]:
 *  - active-state indicator
 *  - long-press action menu (activate / deactivate, edit, delete)
 *  - tap to select (drives the detail pane / pushes the events key)
 *
 * Observer CRUD goes through the existing [ObserverEditorSheet] flow via the
 * [MainStudioViewModel] facade (so the editing UX is unchanged).
 *
 * @param onSelectObserver Called when the user taps an observer row. The caller decides
 *   whether to push the detail pane onto the back stack (at compact widths) or rely on the
 *   ListDetailSceneStrategy to place it side-by-side (expanded widths).
 */
@Composable
fun ObserversListPane(
    viewModel: MainStudioViewModel,
    onSelectObserver: (DittoObservable) -> Unit,
    modifier: Modifier = Modifier,
) {
    val observers by viewModel.observers.collectAsStateWithLifecycle()

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "Observers",
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    text = "${observers.size}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (observers.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No observers registered. Tap + to add one.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                observers.forEach { observer ->
                    ObserverListItem(
                        observer = observer,
                        isSelected = viewModel.selectedObserver?.id == observer.id,
                        isActive = viewModel.isObserverActive(observer),
                        onSelect = {
                            viewModel.selectObserver(observer)
                            onSelectObserver(observer)
                        },
                        onActivate = { viewModel.activateObserver(observer) },
                        onDeactivate = { viewModel.deactivateObserver(observer) },
                        onEdit = { viewModel.editingObserver = observer },
                        onDelete = { viewModel.removeObserver(observer) },
                    )
                }
            }
        }

        // Add-observer FAB. Uses the existing ObserverEditorSheet pipeline by setting
        // editingObserver to a fresh empty DittoObservable.
        FloatingActionButton(
            onClick = { viewModel.editingObserver = DittoObservable() },
            containerColor = SulfurYellow,
            contentColor = JetBlack,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = "Add observer",
            )
        }
    }
}
