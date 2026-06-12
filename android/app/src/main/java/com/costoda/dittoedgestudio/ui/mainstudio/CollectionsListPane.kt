package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
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
 * List pane for the Query Workbench section (Task 4.3e scene-driven shell).
 *
 * Renders the database's collections (with expandable indexes) as a vertical scrollable
 * list, extracted faithfully from the COLLECTIONS section of the legacy
 * [DataPanel] / [PhoneDrawerContent] in [MainStudioScreen]:
 *  - per-collection expandable row (delegated to existing [CollectionListItem])
 *  - section header with refresh icon (refreshes the [CollectionsRepository] cache)
 *  - "Add index" FAB at the bottom — opens the legacy [AddIndexSheet] via the VM's
 *    `showAddIndex` flag (session-scoped state so the sheet survives rail switches)
 *
 * Index CRUD is wired through [MainStudioViewModel.addIndex] (which delegates to
 * [com.costoda.dittoedgestudio.data.session.StudioSession.addIndex] →
 * [com.costoda.dittoedgestudio.data.repository.CollectionsRepository.createIndex]).
 *
 * @param onOpenEditor When non-null an "Open Editor" affordance is shown at the top of the
 *   list (compact-width only). At expanded widths the detail placeholder already shows
 *   the editor and this callback should be null so the button is hidden.
 */
@Composable
fun CollectionsListPane(
    viewModel: MainStudioViewModel,
    onOpenEditor: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
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
            // "Open Editor" affordance — shown at compact widths so users can reach the
            // editor/results content pane from the list pane.
            if (onOpenEditor != null) {
                FilledTonalButton(
                    onClick = onOpenEditor,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Storage,
                        contentDescription = null,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Open Editor")
                }
                HorizontalDivider()
            }

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

        // Add-index FAB — opens the legacy AddIndexSheet via session-scoped uiState.showAddIndex,
        // identical to the legacy DataPanel "Add Index" FAB menu item path.
        FloatingActionButton(
            onClick = { viewModel.showAddIndex = true },
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

        // Add-index sheet hoisted here so it appears as a child of this pane regardless of
        // layout breakpoint (mirrors how SubscriptionEditorSheet is hoisted in PresenceListSection).
        if (viewModel.showAddIndex) {
            AddIndexSheet(
                collections = collections,
                onAdd = { collection, field -> viewModel.addIndex(collection, field) },
                onDismiss = { viewModel.showAddIndex = false },
            )
        }
    }
}
