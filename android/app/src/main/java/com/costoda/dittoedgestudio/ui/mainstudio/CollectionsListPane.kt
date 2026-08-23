package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import kotlinx.coroutines.launch

/**
 * List pane for the Query Workbench section.
 *
 * Renders the database's collections (with expandable indexes) as a vertical scrollable
 * list, extracted faithfully from the COLLECTIONS section of the legacy
 * data-panel / phone-drawer layout in the legacy MainStudioScreen:
 *  - per-collection expandable row (delegated to existing [CollectionListItem])
 *  - section header with refresh icon (refreshes the [CollectionsRepository] cache)
 *  - "Add index" FAB at the bottom — sets `viewModel.showAddIndex = true` so the
 *    [AddIndexSheet] hoisted in [QueryWorkbenchContentSection] opens
 *
 * Index CRUD is wired through [MainStudioViewModel.addIndex] (which delegates to
 * [com.costoda.dittoedgestudio.data.session.StudioSession.addIndex] →
 * [com.costoda.dittoedgestudio.data.repository.CollectionsRepository.createIndex]).
 *
 * The [AddIndexSheet] itself is rendered by [QueryWorkbenchContentSection] so that the
 * sheet remains in composition even when this list pane is closed (e.g. when the Nav Drawer
 * dismisses after the user taps a section item below 840dp).
 *
 * @param onAfterTriggerAddIndex Invoked after the FAB sets `showAddIndex = true`. Used by
 *   the drawer-mode caller to close the drawer so the sheet appears over the Content Pane.
 *   Null in multi-pane mode where the FAB lives inline next to the editor.
 */
@Composable
fun CollectionsListPane(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
    onAfterTriggerAddIndex: (() -> Unit)? = null,
) {
    val collections by viewModel.collections.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),
        ) {
            // Section header with refresh action.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "COLLECTIONS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(
                    onClick = { scope.launch { viewModel.collectionsRepository.refresh() } },
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Refresh,
                        contentDescription = "Refresh collections",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.width(16.dp),
                    )
                }
            }

            if (collections.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No Collections",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                collections.forEach { collection ->
                    CollectionListItem(collection = collection)
                }
            }
        }

        // Add-index FAB — opens the AddIndexSheet via session-scoped uiState.showAddIndex.
        // The sheet itself is rendered by QueryWorkbenchContentSection so it survives even
        // when this list pane leaves composition (e.g. drawer dismiss in drawer-mode).
        FloatingActionButton(
            onClick = {
                viewModel.showAddIndex = true
                onAfterTriggerAddIndex?.invoke()
            },
            containerColor = SulfurYellow,
            contentColor = JetBlack,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = "Add index",
            )
        }
    }
}
