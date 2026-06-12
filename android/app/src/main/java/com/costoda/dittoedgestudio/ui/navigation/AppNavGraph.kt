@file:OptIn(androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi::class)

package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.navigation3.ListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigation3.rememberListDetailSceneStrategy
import androidx.compose.runtime.Composable
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.database.DatabaseListScreen
import com.costoda.dittoedgestudio.ui.mainstudio.AppMetricsSection
import com.costoda.dittoedgestudio.ui.mainstudio.DiskUsageSection
import com.costoda.dittoedgestudio.ui.mainstudio.LoggingSection
import com.costoda.dittoedgestudio.ui.mainstudio.ObserverEventsSection
import com.costoda.dittoedgestudio.ui.mainstudio.ObserversListSection
import com.costoda.dittoedgestudio.ui.mainstudio.PresenceContentSection
import com.costoda.dittoedgestudio.ui.mainstudio.PresenceListSection
import com.costoda.dittoedgestudio.ui.mainstudio.QueryMetricsDetailSection
import com.costoda.dittoedgestudio.ui.mainstudio.QueryMetricsListSection
import com.costoda.dittoedgestudio.ui.mainstudio.QueryWorkbenchContentSection
import com.costoda.dittoedgestudio.ui.mainstudio.QueryWorkbenchInspector
import com.costoda.dittoedgestudio.ui.mainstudio.QueryWorkbenchListSection
import com.costoda.dittoedgestudio.ui.mainstudio.StudioScaffold
import com.costoda.dittoedgestudio.ui.adaptive.inspectorDefaultVisible
import com.costoda.dittoedgestudio.ui.adaptive.studioMultiPane
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import org.koin.androidx.compose.koinViewModel
import org.koin.compose.getKoin
import org.koin.core.parameter.parametersOf
import org.koin.core.qualifier.named

/**
 * Root navigation graph (Navigation 3).
 *
 * Top-level keys:
 *  - [DatabaseListKey]   — start destination, list of saved databases.
 *  - [DatabaseEditorKey] — create/edit a database; `id == -1L` means "new".
 *  - [QrScannerKey]      — camera-based QR code import.
 *  - [StudioSectionKey]  — seven sibling rail-section entries (one per studio section).
 *  - [StudioChildKey]    — drill-ins; pushed onto the active section.
 *
 * **Studio scope ownership** is handled by [StudioScopeManager] over the back stack: a Koin
 * `studio` scope (and its [StudioSession]) is kept open while any studio entry for that
 * databaseId is on the stack, and closed when all studio entries for that id leave the stack.
 *
 * ## Layout adaptation
 *
 * The studio adapts at the **840dp** breakpoint (see
 * [com.costoda.dittoedgestudio.ui.adaptive.studioMultiPane]):
 *
 *  - **≥840dp (multi-pane)**: scene-driven layout. Each section renders its `listPane` +
 *    `detailPane` (or `detailPlaceholder`) side-by-side via [ListDetailSceneStrategy] under a
 *    single [StudioScaffold] (Rail + top bar + Inspector).
 *  - **<840dp (drawer mode)**: no rail column. Each section entry renders ONLY its content
 *    pane as the body; the rail items AND the section's Data Panel (list pane) live inside
 *    the modal Nav Drawer attached to the top-bar hamburger. The Content Pane is the
 *    default view at every section.
 *
 * ## Chrome hoisting
 *
 * The studio chrome ([StudioScaffold]: Rail + top bar + Inspector) is rendered EXACTLY ONCE,
 * wrapping the entire [NavDisplay] — never per-entry. Wrapping it per-entry causes the
 * [ListDetailSceneStrategy] to compose two scaffolds side-by-side. The chrome is rendered
 * only when the back stack top is a studio key (section or child).
 *
 * The [NavDisplay] is wrapped in [movableContentOf] so that moving it between the bare and
 * scaffolded branches preserves its composition state.
 */
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)

    // At Large+ widths (≥1200dp) we cap the list pane's preferred width to 320dp so the
    // detail/editor pane receives the surplus space. Below Large the strategy's own default
    // (360dp from PaneScaffoldDirective.DefaultPreferredWidth) is used.
    val windowAdaptiveInfo = currentWindowAdaptiveInfoV2()
    val windowSizeClass = windowAdaptiveInfo.windowSizeClass
    val baseDirective = calculatePaneScaffoldDirective(windowAdaptiveInfo)
    val listDetailDirective = if (windowSizeClass.inspectorDefaultVisible) {
        // Large/XL: cap list-pane preferred width to leave room for detail + inspector.
        baseDirective.copy(defaultPanePreferredWidth = 320.dp)
    } else {
        baseDirective
    }
    val listDetailStrategy = rememberListDetailSceneStrategy<NavKey>(directive = listDetailDirective)

    // Drive the Koin scope lifecycle from the current back stack contents. Must be inside
    // the composition so the underlying derivedStateOf reads tracked snapshot state.
    StudioScopeManager(backStack)

    // The NavDisplay itself — wrapped in movableContentOf so it preserves composition state
    // whether it ends up inside the StudioScaffold (studio destinations) or bare (database
    // list, editor, QR scanner).
    val navDisplay = remember(listDetailStrategy) {
        movableContentOf {
            NavDisplay(
                backStack = backStack,
                onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
                entryDecorators = listOf(
                    rememberSaveableStateHolderNavEntryDecorator(),
                    rememberViewModelStoreNavEntryDecorator(),
                ),
                sceneStrategy = listDetailStrategy,
                entryProvider = entryProvider {
                    entry<DatabaseListKey> {
                        DatabaseListScreen(
                            onAddDatabase = { backStack.add(DatabaseEditorKey()) },
                            onEditDatabase = { db -> backStack.add(DatabaseEditorKey(id = db.id)) },
                            onOpenDatabase = { db ->
                                // Studio entry is now SubscriptionsKey — the default section.
                                backStack.add(SubscriptionsKey(databaseId = db.id))
                            },
                            onScanQrCode = { backStack.add(QrScannerKey) },
                        )
                    }

                    entry<DatabaseEditorKey> { key ->
                        DatabaseEditorScreen(
                            databaseId = key.id,
                            onDismiss = { backStack.removeLastOrNull() },
                        )
                    }

                    entry<QrScannerKey> {
                        QrScannerScreen(onNavigateBack = { backStack.removeLastOrNull() })
                    }

                    // ── Scene-driven section: Observers ──────────────────────────────────
                    entry<ObserversKey>(
                        metadata = ListDetailSceneStrategy.listPane(
                            detailPlaceholder = { ObserverEventsPlaceholder() },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.OBSERVERS,
                        ) { viewModel ->
                            // Below 840dp: section entry renders the CONTENT pane (observer
                            // events for the currently selected observer; "select an observer"
                            // empty state when none).
                            // ≥840dp: section entry renders the LIST pane; selection pushes
                            // ObserverEventsKey which the scene strategy places side-by-side.
                            if (studioWindowSizeClass().studioMultiPane) {
                                ObserversListSection(
                                    viewModel = viewModel,
                                    onObserverPicked = { observer ->
                                        // Remove any existing detail before pushing so only
                                        // one detail pane exists at a time.
                                        backStack.removeIf { it is ObserverEventsKey }
                                        backStack.add(
                                            ObserverEventsKey(
                                                databaseId = key.databaseId,
                                                observerId = observer.id,
                                            ),
                                        )
                                    },
                                )
                            } else {
                                // Drawer-mode: events content is the default view.
                                ObserverEventsSection(viewModel = viewModel)
                            }
                        }
                    }

                    entry<ObserverEventsKey>(
                        metadata = ListDetailSceneStrategy.detailPane(),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.OBSERVERS,
                        ) { viewModel ->
                            ObserverEventsSection(viewModel = viewModel)
                        }
                    }

                    // ── Scene-driven section: Log Analyzer ───────────────────────────────
                    entry<LoggingKey> { key ->
                        StudioSectionContainer(key.databaseId, StudioNavItem.LOGGING) { viewModel ->
                            LoggingSection(viewModel = viewModel)
                        }
                    }

                    // ── Scene-driven section: App Metrics ────────────────────────────────
                    entry<AppMetricsKey> { key ->
                        StudioSectionContainer(key.databaseId, StudioNavItem.APP_METRICS) {
                            AppMetricsSection()
                        }
                    }

                    // ── Scene-driven section: Database Metrics ───────────────────────────
                    entry<DiskUsageKey> { key ->
                        StudioSectionContainer(key.databaseId, StudioNavItem.DISK_USAGE) {
                            DiskUsageSection()
                        }
                    }

                    // ── Scene-driven section: Presence (Subscriptions) ───────────────────
                    entry<SubscriptionsKey>(
                        metadata = ListDetailSceneStrategy.listPane(
                            detailPlaceholder = {
                                val databaseId = backStack
                                    .filterIsInstance<SubscriptionsKey>()
                                    .lastOrNull()
                                    ?.databaseId
                                if (databaseId != null) {
                                    val viewModel = rememberStudioViewModel(databaseId)
                                    remember(viewModel) { viewModel.selectedNavItem = StudioNavItem.SUBSCRIPTIONS }
                                    PresenceContentSection(viewModel = viewModel)
                                }
                            },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.SUBSCRIPTIONS,
                        ) { viewModel ->
                            // ≥840dp: scene shows list (subscriptions) + detail placeholder
                            // (peers). Below 840dp: the section body renders the CONTENT pane
                            // (peers) as the default; the subscriptions list lives in the drawer.
                            if (studioWindowSizeClass().studioMultiPane) {
                                PresenceListSection(viewModel = viewModel)
                            } else {
                                PresenceContentSection(viewModel = viewModel)
                            }
                        }
                    }

                    // ── Scene-driven section: Query Metrics ──────────────────────────────
                    entry<QueryMetricsKey>(
                        metadata = ListDetailSceneStrategy.listPane(
                            detailPlaceholder = { QueryMetricsDetailPlaceholder() },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY_METRICS,
                        ) { _ ->
                            val selectedHistoryId = backStack
                                .filterIsInstance<QueryMetricDetailKey>()
                                .lastOrNull()
                                ?.historyId
                            // ≥840dp: list pane; selection pushes detail key.
                            // <840dp: section body shows the selected detail (or placeholder).
                            // The list lives in the drawer; tapping a row closes the drawer.
                            if (studioWindowSizeClass().studioMultiPane) {
                                QueryMetricsListSection(
                                    selectedHistoryId = selectedHistoryId,
                                    onMetricPicked = { metric ->
                                        backStack.removeIf { it is QueryMetricDetailKey }
                                        backStack.add(
                                            QueryMetricDetailKey(
                                                databaseId = key.databaseId,
                                                historyId = metric.historyId,
                                            ),
                                        )
                                    },
                                    onClearAll = {
                                        backStack.removeIf { it is QueryMetricDetailKey }
                                    },
                                )
                            } else {
                                if (selectedHistoryId != null) {
                                    QueryMetricsDetailSection(historyId = selectedHistoryId)
                                } else {
                                    QueryMetricsDetailPlaceholder()
                                }
                            }
                        }
                    }

                    entry<QueryMetricDetailKey>(
                        metadata = ListDetailSceneStrategy.detailPane(),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY_METRICS,
                        ) { _ ->
                            QueryMetricsDetailSection(historyId = key.historyId)
                        }
                    }

                    // Legacy detail keys kept for back-stack restore compatibility. These
                    // are never pushed in the current code path (drawer mode shows content
                    // by default; multi-pane uses list-pane + detail-placeholder), but we
                    // keep the entries so any persisted stack from a previous build still
                    // resolves to something sensible.
                    entry<PresenceContentKey>(
                        metadata = ListDetailSceneStrategy.detailPane(),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.SUBSCRIPTIONS,
                        ) { viewModel ->
                            PresenceContentSection(viewModel = viewModel)
                        }
                    }

                    entry<QueryContentKey>(
                        metadata = ListDetailSceneStrategy.detailPane(),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY,
                        ) { viewModel ->
                            QueryWorkbenchContentSection(viewModel = viewModel)
                        }
                    }

                    // ── Scene-driven section: Query Workbench ────────────────────────────
                    entry<QueryKey>(
                        metadata = ListDetailSceneStrategy.listPane(
                            detailPlaceholder = {
                                val databaseId = backStack
                                    .filterIsInstance<QueryKey>()
                                    .lastOrNull()
                                    ?.databaseId
                                if (databaseId != null) {
                                    val viewModel = rememberStudioViewModel(databaseId)
                                    remember(viewModel) { viewModel.selectedNavItem = StudioNavItem.QUERY }
                                    QueryWorkbenchContentSection(viewModel = viewModel)
                                }
                            },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY,
                        ) { viewModel ->
                            // ≥840dp: scene shows collections list + editor detail-placeholder.
                            // <840dp: editor is the default view; collections live in the drawer.
                            if (studioWindowSizeClass().studioMultiPane) {
                                QueryWorkbenchListSection(viewModel = viewModel)
                            } else {
                                QueryWorkbenchContentSection(viewModel = viewModel)
                            }
                        }
                    }
                },
            )
        }
    }

    // Derive the active studio context from the back-stack top. When the top key is a
    // studio key (section or child), we wrap the NavDisplay in the StudioScaffold so the
    // chrome (Rail + top bar + Inspector) is shared across every studio entry. Non-studio
    // destinations render the NavDisplay alone.
    val topKey = backStack.lastOrNull()
    val studioContext: Pair<StudioNavItem, Long>? = when (topKey) {
        is StudioSectionKey -> topKey.navItem to topKey.databaseId
        is StudioChildKey -> topKey.parentNavItem to topKey.databaseId
        else -> null
    }

    if (studioContext != null) {
        val (section, databaseId) = studioContext
        val viewModel = rememberStudioViewModel(databaseId)
        // Set selectedNavItem synchronously during composition (not via LaunchedEffect) so the
        // correct section is active on the first frame — avoids a one-frame flash.
        remember(viewModel, section) { viewModel.selectedNavItem = section }

        // Below 840dp the section's Data Panel goes inside the modal Nav Drawer; build
        // the slot here so the drawer-aware variant (with closeDrawer plumbed through) is
        // available to the scaffold. Sections without a list pane (Logging / AppMetrics /
        // DiskUsage) pass null.
        val dataPanelSlot: (@Composable (closeDrawer: () -> Unit) -> Unit)? = when (section) {
            StudioNavItem.SUBSCRIPTIONS -> { closeDrawer ->
                PresenceListSection(
                    viewModel = viewModel,
                    onAfterAddOrEditTriggered = closeDrawer,
                )
            }
            StudioNavItem.QUERY -> { closeDrawer ->
                QueryWorkbenchListSection(
                    viewModel = viewModel,
                    onAfterTriggerAddIndex = closeDrawer,
                )
            }
            StudioNavItem.OBSERVERS -> { closeDrawer ->
                ObserversListSection(
                    viewModel = viewModel,
                    onObserverPicked = { observer ->
                        viewModel.selectObserver(observer)
                        closeDrawer()
                    },
                    onAfterAddTriggered = closeDrawer,
                )
            }
            StudioNavItem.QUERY_METRICS -> { closeDrawer ->
                val selectedHistoryId = backStack
                    .filterIsInstance<QueryMetricDetailKey>()
                    .lastOrNull()
                    ?.historyId
                QueryMetricsListSection(
                    selectedHistoryId = selectedHistoryId,
                    onMetricPicked = { metric ->
                        backStack.removeIf { it is QueryMetricDetailKey }
                        backStack.add(
                            QueryMetricDetailKey(
                                databaseId = databaseId,
                                historyId = metric.historyId,
                            ),
                        )
                        closeDrawer()
                    },
                    onClearAll = {
                        backStack.removeIf { it is QueryMetricDetailKey }
                    },
                )
            }
            // Single-pane sections (no Data Panel).
            StudioNavItem.LOGGING,
            StudioNavItem.APP_METRICS,
            StudioNavItem.DISK_USAGE -> null
        }

        StudioScaffold(
            currentSection = section,
            session = viewModel.session,
            // Close button (top-bar X): exit the studio entirely. Pop every studio entry
            // (sections + children) for this databaseId so we land back on whatever
            // non-studio key precedes them (typically DatabaseListKey).
            onBack = {
                backStack.removeAll { key ->
                    (key is StudioSectionKey && key.databaseId == databaseId) ||
                        (key is StudioChildKey && key.databaseId == databaseId)
                }
            },
            onSectionSelect = { newItem ->
                // Replace top so the new section becomes the visible entry. Strip any
                // dangling detail-pane / drill-in keys so leaving their parent section
                // doesn't leave a stale pane.
                backStack.removeIf { it is StudioChildKey }
                val newKey = newItem.toSectionKey(databaseId)
                if (backStack.isNotEmpty()) {
                    backStack[backStack.lastIndex] = newKey
                } else {
                    backStack.add(newKey)
                }
            },
            inspectorContent = if (section == StudioNavItem.QUERY) {
                { QueryWorkbenchInspector(viewModel = viewModel) }
            } else null,
            dataPanelContent = dataPanelSlot,
        ) {
            navDisplay()
        }
    } else {
        navDisplay()
    }
}

/**
 * Shared container for studio entries. Resolves the [MainStudioViewModel] for [databaseId] and
 * pins `viewModel.selectedNavItem` to the entry's [section] so any session-side logic keyed on
 * it (inspector help content, etc.) keeps working.
 *
 * **Does NOT render [StudioScaffold]** — the chrome is rendered exactly once at the
 * [AppNavGraph] level, wrapping the entire [NavDisplay].
 */
@Composable
private fun StudioSectionContainer(
    databaseId: Long,
    section: StudioNavItem,
    content: @Composable (MainStudioViewModel) -> Unit,
) {
    val viewModel = rememberStudioViewModel(databaseId)
    // Set selectedNavItem synchronously during composition so the correct section is active
    // on the first frame.
    remember(viewModel, section) { viewModel.selectedNavItem = section }
    content(viewModel)
}

/**
 * Resolves the per-databaseId [StudioSession] from Koin's studio scope, then constructs the
 * per-entry [MainStudioViewModel] using `koinViewModel(parameters = ...)`. The Nav3 view-model
 * decorator scopes the VM to *this* entry, so a fresh entry for the same databaseId reuses
 * the same session (Koin scope is keyed by databaseId) but a new VM instance.
 */
@Composable
private fun rememberStudioViewModel(databaseId: Long): MainStudioViewModel {
    val koin = getKoin()
    val scopeId = remember(databaseId) { StudioSession.scopeId(databaseId) }
    val scope = remember(scopeId) {
        koin.getOrCreateScope(scopeId, named(StudioSession.SCOPE_QUALIFIER))
    }
    val session = remember(scope, databaseId) {
        scope.get<StudioSession> { parametersOf(databaseId) }
    }
    return koinViewModel(
        key = "MainStudioViewModel:$databaseId",
        parameters = { parametersOf(session) },
    )
}

/**
 * Placeholder shown by [ListDetailSceneStrategy.listPane] in the detail-pane area when no
 * observer has been selected yet (multi-pane widths). Mirrors the empty state in
 * [com.costoda.dittoedgestudio.ui.mainstudio.ObserverDetailScreen].
 */
@Composable
private fun ObserverEventsPlaceholder() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Select an observer to see its events",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Placeholder shown by [ListDetailSceneStrategy.listPane] in the detail-pane area when no
 * query metric has been selected yet (multi-pane widths).
 */
@Composable
private fun QueryMetricsDetailPlaceholder() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Select a query to view details",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
