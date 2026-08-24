@file:OptIn(ExperimentalMaterial3ExpressiveApi::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ClearAll
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.activity.compose.rememberLauncherForActivityResult
import com.costoda.dittoedgestudio.ui.components.CollapsibleBottomBar
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
import kotlinx.coroutines.launch
import org.koin.androidx.compose.koinViewModel
import org.koin.compose.koinInject
import org.koin.core.parameter.parametersOf

/**
 * Scene-driven section composables for the Query Workbench (canonical: Query) section.
 *
 * Two entry-point variants — analogous to [PresenceSection]:
 *  - [QueryWorkbenchListSection]    — list-pane content (collections list + index FAB).
 *                                     Used by `entry<QueryKey>` as the list pane at ≥840dp,
 *                                     and rendered inside the modal Nav Drawer below 840dp.
 *  - [QueryWorkbenchContentSection] — content/detail pane: DQL editor + results +
 *                                     paginated query bottom bar. Default view at every
 *                                     width (the editor is the primary surface, matching
 *                                     legacy phone UX and the iPad MainView semantics).
 *
 * Draft-survival design:
 *  - Editor draft, results, pagination, inspector tab, and selected document live on the
 *    session-scoped [com.costoda.dittoedgestudio.data.session.QueryWorkbenchState] (a
 *    sub-object of [com.costoda.dittoedgestudio.data.session.StudioUiState]).
 *  - Each entry composition creates a fresh [QueryEditorViewModel] via Koin; the VM is
 *    parameterised on `(databaseId, workbench)` so all VM instances share the same flows.
 *    Switching rail sections destroys/recreates the VM but the user's draft and results
 *    are preserved on the session.
 */

/**
 * Internal helper — resolves the [QueryEditorViewModel] for the current studio session.
 *
 * Returns null when the session has not yet finished hydration (no `currentDittoId`). The
 * caller renders a loading placeholder in that case.
 */
@Composable
private fun rememberQueryEditorViewModelOrNull(
    viewModel: MainStudioViewModel,
): QueryEditorViewModel? {
    // Collect the session's flow (not the plain snapshot getter) so this composable
    // recomposes when hydration completes — a plain read would never recompose.
    val currentDittoId by viewModel.session.currentDittoIdFlow.collectAsStateWithLifecycle()
    val dittoId = currentDittoId ?: return null
    val workbench = viewModel.session.uiState.queryWorkbench
    return koinViewModel(
        key = "QueryEditorViewModel:$dittoId",
        parameters = { parametersOf(dittoId, workbench) },
    )
}

/**
 * List-pane content for the Query Workbench section: the COLLECTIONS list with the
 * "add index" FAB.
 *
 * @param onAfterTriggerAddIndex Optional drawer-aware callback fired after the FAB sets
 *   `viewModel.showAddIndex = true`. Used by drawer-mode callers to close the drawer so
 *   the sheet (hoisted in [QueryWorkbenchContentSection]) appears over the Content Pane.
 */
@Composable
fun QueryWorkbenchListSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
    onAfterTriggerAddIndex: (() -> Unit)? = null,
) {
    CollectionsListPane(
        viewModel = viewModel,
        modifier = modifier,
        onAfterTriggerAddIndex = onAfterTriggerAddIndex,
    )
}

/**
 * Content/detail-pane for the Query Workbench: the DQL editor + paginated results +
 * floating query bottom bar (run button is surfaced via the bottom-bar overflow, and
 * pagination/page-size are exposed as the central controls).
 *
 * The previous behaviour where the QUERY-section top bar housed a Run button is moved
 * here as a FAB-style "Run" icon inside [QueryWorkbenchBottomBar] so the scaffold's
 * shared top bar can remain identical across sections.
 */
@Composable
fun QueryWorkbenchContentSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    val queryVm = rememberQueryEditorViewModelOrNull(viewModel)
    val collections by viewModel.collections.collectAsStateWithLifecycle()
    var showImportSheet by remember { mutableStateOf(false) }
    Box(modifier = modifier.fillMaxSize()) {
        if (queryVm == null) {
            // Session has not finished hydrating yet (no currentDittoId). Render a small
            // loading placeholder — the parent scaffold's content area is the slot here.
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            val queryText by queryVm.queryText.collectAsStateWithLifecycle()
            val isExecuting by queryVm.isExecuting.collectAsStateWithLifecycle()
            val executeMode by queryVm.executeMode.collectAsStateWithLifecycle()
            val executeModes by queryVm.executeModes.collectAsStateWithLifecycle()
            val captureProfilingData by queryVm.captureProfilingData.collectAsStateWithLifecycle()
            val captureQueryMetrics by queryVm.captureQueryMetrics.collectAsStateWithLifecycle()
            Column(modifier = Modifier.fillMaxSize()) {
                QueryWorkbenchTopToolbar(
                    queryText = queryText,
                    isExecuting = isExecuting,
                    executeMode = executeMode,
                    executeModes = executeModes,
                    captureProfilingData = captureProfilingData,
                    captureQueryMetrics = captureQueryMetrics,
                    onRun = { queryVm.executeQuery() },
                    onExplain = { queryVm.explainQuery() },
                    onModeSelect = { queryVm.setExecuteMode(it) },
                    onCaptureProfilingDataChange = { queryVm.setCaptureProfilingData(it) },
                    onCaptureQueryMetricsChange = { queryVm.setCaptureQueryMetrics(it) },
                    onGenerateStatement = { kind ->
                        queryVm.insertGeneratedStatement(kind)?.let { viewModelError ->
                            android.util.Log.w("QueryWorkbench", "statement generation: $viewModelError")
                        }
                    },
                    onImportJson = { showImportSheet = true },
                )
                QueryEditorScreen(
                    viewModel = queryVm,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            // Floating bottom bar (Run removed in Task 13).
            QueryWorkbenchBottomBar(
                viewModel = queryVm,
                mainViewModel = viewModel,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(8.dp),
            )
        }
    }

    // Add-index sheet — hoisted here (out of CollectionsListPane) so the bottom sheet
    // remains in composition even when the list pane leaves it (e.g. when the Nav Drawer
    // dismisses below 840dp). Triggered by `viewModel.showAddIndex` which the CollectionsListPane
    // FAB flips on.
    if (viewModel.showAddIndex) {
        AddIndexSheet(
            collections = collections,
            onAdd = { collection, fields -> viewModel.addIndex(collection, fields) },
            // onAdd is suspend: the sheet awaits the result to show errors inline.
            onDismiss = { viewModel.showAddIndex = false },
        )
    }

    // Import-JSON sheet — dispatched from the toolbar options menu.
    if (showImportSheet) {
        ImportJsonSheet(
            importService = koinInject(),
            collections = collections,
            onDismiss = { showImportSheet = false },
        )
    }
}

/**
 * Inspector content for the Query Workbench. Renders the rich
 * [com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView] (History,
 * Favorites, JSON document viewer, per-query metrics tabs) when the session is hydrated;
 * otherwise falls back to the help text via the scaffold's default.
 *
 * Called by the AppNavGraph and threaded into the scaffold via its `inspectorContent`
 * slot.
 */
@Composable
fun QueryWorkbenchInspector(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    val queryVm = rememberQueryEditorViewModelOrNull(viewModel)
    if (queryVm == null) {
        // Fall back to the help view while we wait for hydration so the inspector pane
        // is never empty.
        com.costoda.dittoedgestudio.ui.mainstudio.inspector.InspectorContentView(
            selectedNavItem = com.costoda.dittoedgestudio.viewmodel.StudioNavItem.QUERY,
            modifier = modifier,
        )
    } else {
        com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView(
            viewModel = queryVm,
            modifier = modifier,
        )
    }
}

/**
 * Floating bottom bar for the Query Workbench. Mirrors the legacy `QueryBottomBar`
 * in `MainStudioScreen` 1:1 (peers chip + dropdown, prev/next page, page-size submenu,
 * Clear Results). The Run button lives in [QueryWorkbenchTopToolbar] — not here.
 */
@Composable
private fun QueryWorkbenchBottomBar(
    viewModel: QueryEditorViewModel,
    mainViewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    val connections by mainViewModel.connectionsByTransport.collectAsStateWithLifecycle()
    val queryResult by viewModel.queryResult.collectAsStateWithLifecycle()
    val currentPage by viewModel.currentPage.collectAsStateWithLifecycle()
    val pageSize by viewModel.pageSize.collectAsStateWithLifecycle()
    val pageSizeOptions by viewModel.pageSizeOptions.collectAsStateWithLifecycle()

    var overflowExpanded by remember { mutableStateOf(false) }
    var pageSizeExpanded by remember { mutableStateOf(false) }

    // SAF save dialog for the results export (full result, not just the page).
    val exportContext = LocalContext.current
    val exportScope = rememberCoroutineScope()
    val jsonExportLauncher = rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        val payload = viewModel.resultsJsonForExport()
        if (uri != null && payload != null) {
            exportScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                runCatching {
                    exportContext.contentResolver.openOutputStream(uri)?.use { stream ->
                        stream.write(payload.toByteArray(Charsets.UTF_8))
                    } ?: error("Could not open destination")
                }
            }
        }
    }

    val totalCount = queryResult?.totalCount ?: 0
    val pageCount = if (totalCount == 0) 1 else (totalCount + pageSize - 1) / pageSize

    // Collapse/expand chrome lives in CollapsibleBottomBar (SwiftUI
    // DetailBottomBar parity): the bar floats over the results content, so the user
    // can fold it away (e.g. while reading the Profile tab) and bring it back with
    // the chevron pill.
    CollapsibleBottomBar(modifier = modifier) {
            // Connections counter — SwiftUI DetailBottomBar parity (antenna icon +
            // monospaced count, colored-dot transport popover).
            ConnectionsMenuButton(connections = connections)

            Spacer(modifier = Modifier.weight(1f))

            if (queryResult != null && totalCount > 0) {
                IconButton(
                    onClick = { viewModel.setPage(currentPage - 1) },
                    enabled = currentPage > 0,
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                        contentDescription = "Previous page",
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
                Text(
                    text = "Pg ${currentPage + 1} / $pageCount",
                    color = MaterialTheme.colorScheme.onSurface,
                    style = MaterialTheme.typography.labelSmall,
                )
                IconButton(
                    onClick = { viewModel.setPage(currentPage + 1) },
                    enabled = currentPage < pageCount - 1,
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "Next page",
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Box {
                IconButton(onClick = { overflowExpanded = true }) {
                    Icon(
                        imageVector = Icons.Outlined.MoreVert,
                        contentDescription = "More options",
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
                DropdownMenu(
                    expanded = overflowExpanded,
                    onDismissRequest = { overflowExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Page size: $pageSize") },
                        onClick = {
                            overflowExpanded = false
                            pageSizeExpanded = true
                        },
                        trailingIcon = {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                            )
                        },
                    )
                    // SwiftUI parity: export the ENTIRE result set (all pages) as JSON.
                    DropdownMenuItem(
                        text = { Text("Export results as JSON…") },
                        enabled = (queryResult?.documents?.isNotEmpty() == true),
                        onClick = {
                            overflowExpanded = false
                            jsonExportLauncher.launch("query_results.json")
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Clear Results") },
                        onClick = {
                            overflowExpanded = false
                            viewModel.clearResults()
                        },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Outlined.ClearAll,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                        },
                    )
                }

                DropdownMenu(
                    expanded = pageSizeExpanded,
                    onDismissRequest = { pageSizeExpanded = false },
                ) {
                    pageSizeOptions.forEach { size ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    text = "$size",
                                    color = if (size == pageSize) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurface
                                    },
                                )
                            },
                            onClick = {
                                viewModel.setPageSize(size)
                                pageSizeExpanded = false
                            },
                        )
                    }
                }
            }
        }
}
