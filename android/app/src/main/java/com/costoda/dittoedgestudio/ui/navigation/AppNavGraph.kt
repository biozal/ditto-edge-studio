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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
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
import com.costoda.dittoedgestudio.ui.adaptive.showsRail
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import androidx.compose.runtime.LaunchedEffect
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
 *  - [ObserverEventsKey] — detail drill-in pushed on top of [ObserversKey].
 *
 * **Studio scope ownership** is handled by [StudioScopeManager] over the back stack: a Koin
 * `studio` scope (and its [StudioSession]) is kept open while any studio entry for that
 * databaseId is on the stack, and closed when all studio entries for that id leave the stack.
 *
 * **All seven rail sections run on the scene-driven shell:**
 *  - [ObserversKey] (list pane) + [ObserverEventsKey] (detail pane) via Material adaptive
 *    [ListDetailSceneStrategy]. Selecting an observer pushes [ObserverEventsKey]; the strategy
 *    automatically renders the two side-by-side at ≥600dp and as a normal drill-in below.
 *  - [LoggingKey] — single-pane Log Analyzer (Task 4.3b).
 *  - [AppMetricsKey] — single-pane App Metrics (Task 4.3b).
 *  - [DiskUsageKey] — single-pane Database Metrics (Task 4.3b).
 *  - [SubscriptionsKey] (list pane) + [PresenceContentKey] (detail pane) via
 *    [ListDetailSceneStrategy]. Unlike Observers, the content (Connected Peers tabs) is
 *    NOT selection-driven; it is always relevant. The detail placeholder renders
 *    [PresenceContentSection] directly so at ≥600dp both panes are always visible. At
 *    compact widths the list pane is shown first (subscriptions list) and the user taps
 *    "View Peers" to drill into [PresenceContentKey]. (Task 4.3c)
 *  - [QueryMetricsKey] (list pane) + [QueryMetricDetailKey] (detail pane) via
 *    [ListDetailSceneStrategy]. Selecting a row pushes [QueryMetricDetailKey]; at ≥600dp
 *    the strategy renders both panes side-by-side. Clear-all strips [QueryMetricDetailKey]
 *    from the stack. (Task 4.3d)
 *  - [QueryKey] (list pane) + [QueryContentKey] (detail pane / compact drill-in) via
 *    [ListDetailSceneStrategy]. The list pane is the COLLECTIONS list (with add-index FAB);
 *    the detail pane is the DQL editor + paginated results + floating Run / pagination /
 *    overflow bar. At ≥600dp both panes are visible side-by-side via the listPane's
 *    `detailPlaceholder`. At compact widths the list pane is shown first, and a one-shot
 *    LaunchedEffect on the QueryKey entry auto-pushes [QueryContentKey] so the user lands
 *    on the editor (matching legacy phone UX where the editor was the primary surface).
 *    Tapping system back returns to the collections list. The Query inspector is the rich
 *    [com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView] (History /
 *    Favorites / JSON document viewer / Metrics tabs) threaded through the scaffold's new
 *    `inspectorContent` slot. (Task 4.3e)
 */
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)

    // At Large+ widths (≥1200dp) we cap the list pane's preferred width to 320dp so the
    // detail/editor pane receives the surplus space. Below Large the strategy's own default
    // (360dp from PaneScaffoldDirective.DefaultPreferredWidth) is used.
    //
    // API evidence (material3-adaptive 1.3.0-beta02, adaptive-layout AAR):
    //   rememberListDetailSceneStrategy accepts a `directive: PaneScaffoldDirective` param.
    //   PaneScaffoldDirective exposes `defaultPanePreferredWidth` (Dp) and a `copy()` overload.
    //   calculatePaneScaffoldDirective(windowAdaptiveInfo) derives the base directive from the
    //   current window info, then we narrow `defaultPanePreferredWidth` at Large+ so the list
    //   pane doesn't consume more than ~320dp when three panes are side-by-side.
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
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.OBSERVERS,
                ) { viewModel ->
                    ObserversListSection(
                        viewModel = viewModel,
                        onObserverPicked = { observer ->
                            // Push the detail key. At ≥600dp the ListDetailSceneStrategy
                            // composes the result as the side-by-side detail pane; below
                            // 600dp it becomes a normal drill-in. Remove any existing
                            // detail before pushing so only one detail pane exists at a time.
                            backStack.removeIf { it is ObserverEventsKey }
                            backStack.add(
                                ObserverEventsKey(
                                    databaseId = key.databaseId,
                                    observerId = observer.id,
                                ),
                            )
                        },
                    )
                }
            }

            entry<ObserverEventsKey>(
                metadata = ListDetailSceneStrategy.detailPane(),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.OBSERVERS,
                ) { viewModel ->
                    // The observer is already selected by the list-pane's row tap (which
                    // calls viewModel.selectObserver). If we arrive here without that having
                    // happened (e.g. process restore landing on a detail key alone), the
                    // empty state from ObserverDetailScreen is surfaced.
                    ObserverEventsSection(viewModel = viewModel)
                }
            }

            // ── Scene-driven section: Log Analyzer ───────────────────────────────
            entry<LoggingKey> { key ->
                StudioSectionContainer(backStack, key.databaseId, StudioNavItem.LOGGING) { viewModel ->
                    LoggingSection(viewModel = viewModel)
                }
            }

            // ── Scene-driven section: App Metrics ────────────────────────────────
            entry<AppMetricsKey> { key ->
                StudioSectionContainer(backStack, key.databaseId, StudioNavItem.APP_METRICS) {
                    AppMetricsSection()
                }
            }

            // ── Scene-driven section: Database Metrics ───────────────────────────
            entry<DiskUsageKey> { key ->
                StudioSectionContainer(backStack, key.databaseId, StudioNavItem.DISK_USAGE) {
                    DiskUsageSection()
                }
            }

            // ── Scene-driven section: Presence (Subscriptions) ───────────────────
            // The detail placeholder renders the Connected Peers content pane at ≥600dp
            // so both panes are always visible side-by-side. At compact widths the list
            // pane is shown first and the user taps "View Peers" to push PresenceContentKey.
            entry<SubscriptionsKey>(
                metadata = ListDetailSceneStrategy.listPane(
                    detailPlaceholder = {
                        // Resolve databaseId from the SubscriptionsKey currently on the stack.
                        // The listPane detailPlaceholder is only composed in expanded layouts
                        // where SubscriptionsKey is always present on the back stack.
                        // rememberNavBackStack serializes/restores the entire stack, so PresenceContentKey can never be restored without SubscriptionsKey beneath it; the null-guard is purely defensive.
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
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.SUBSCRIPTIONS,
                ) { viewModel ->
                    PresenceListSection(
                        viewModel = viewModel,
                        onViewPeers = {
                            backStack.removeIf { it is PresenceContentKey }
                            backStack.add(PresenceContentKey(databaseId = key.databaseId))
                        },
                    )
                }
            }

            entry<PresenceContentKey>(
                metadata = ListDetailSceneStrategy.detailPane(),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.SUBSCRIPTIONS,
                ) { viewModel ->
                    PresenceContentSection(viewModel = viewModel)
                }
            }

            // ── Scene-driven section: Query Metrics ──────────────────────────────
            entry<QueryMetricsKey>(
                metadata = ListDetailSceneStrategy.listPane(
                    detailPlaceholder = { QueryMetricsDetailPlaceholder() },
                ),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.QUERY_METRICS,
                ) { _ ->
                    // Derive selectedHistoryId from any QueryMetricDetailKey on the stack.
                    val selectedHistoryId = backStack
                        .filterIsInstance<QueryMetricDetailKey>()
                        .lastOrNull()
                        ?.historyId
                    QueryMetricsListSection(
                        selectedHistoryId = selectedHistoryId,
                        onMetricPicked = { metric ->
                            // Remove any existing detail before pushing so only one detail
                            // pane exists at a time — mirrors ObserverEventsKey pattern.
                            backStack.removeIf { it is QueryMetricDetailKey }
                            backStack.add(
                                QueryMetricDetailKey(
                                    databaseId = key.databaseId,
                                    historyId = metric.historyId,
                                ),
                            )
                        },
                        onClearAll = {
                            // Strip the stale detail key after delete-all.
                            backStack.removeIf { it is QueryMetricDetailKey }
                        },
                    )
                }
            }

            entry<QueryMetricDetailKey>(
                metadata = ListDetailSceneStrategy.detailPane(),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.QUERY_METRICS,
                ) { _ ->
                    QueryMetricsDetailSection(historyId = key.historyId)
                }
            }

            // ── Scene-driven section: Query Workbench ────────────────────────────
            // List pane = COLLECTIONS list (with add-index FAB); detail placeholder =
            // editor + results. At ≥600dp both panes are always visible side-by-side. At
            // compact widths the list pane shows first, but a one-shot auto-push of
            // QueryContentKey makes the user land on the editor (mirrors legacy phone UX
            // where the editor was the primary surface and collections lived in the
            // sidebar drawer). The Query inspector is the rich QueryInspectorView, threaded
            // into the scaffold via inspectorContent.
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
                // Compact-only: auto-push QueryContentKey so the user lands on the editor
                // (matches legacy phone UX). At ≥600dp the detail placeholder renders the
                // editor inline so no push is needed. The pushed key contributes to the
                // back stack so system-back returns to the collections list, and the
                // StudioScopeManager treats it as a studio entry so the session survives
                // the drill-in.
                val expandedLayout = studioWindowSizeClass().showsRail
                LaunchedEffect(key.databaseId, expandedLayout) {
                    if (!expandedLayout && backStack.none { it is QueryContentKey }) {
                        backStack.add(QueryContentKey(databaseId = key.databaseId))
                    } else if (expandedLayout) {
                        backStack.removeIf { it is QueryContentKey }
                    }
                }
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.QUERY,
                    inspectorContent = { viewModel ->
                        QueryWorkbenchInspector(viewModel = viewModel)
                    },
                ) { viewModel ->
                    QueryWorkbenchListSection(
                        viewModel = viewModel,
                        // "Open Editor" affordance — compact only. At ≥600dp the editor
                        // is already visible as the detail placeholder so hide the button.
                        onOpenEditor = if (!expandedLayout) {
                            {
                                if (backStack.none { it is QueryContentKey }) {
                                    backStack.add(QueryContentKey(databaseId = key.databaseId))
                                }
                            }
                        } else null,
                    )
                }
            }

            entry<QueryContentKey>(
                metadata = ListDetailSceneStrategy.detailPane(),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.QUERY,
                    inspectorContent = { viewModel ->
                        QueryWorkbenchInspector(viewModel = viewModel)
                    },
                ) { viewModel ->
                    QueryWorkbenchContentSection(viewModel = viewModel)
                }
            }
        },
    )
}

/**
 * Shared container for the scene-driven Observers entries. Resolves the [StudioSession] +
 * [MainStudioViewModel] for [databaseId] and wraps content in [StudioScaffold] (so the rail
 * / drawer chrome is consistent across migrated sections).
 *
 * Forces `viewModel.selectedNavItem = section` so any session-side logic keyed on it (e.g.
 * inspector help content) keeps working until that coupling is removed in a later task.
 *
 * Section switching pushes / replaces the top of the back stack with the new section's key,
 * which both updates the visible chrome and lets [StudioScopeManager] notice we're still in
 * the studio (same databaseId).
 */
@Composable
private fun StudioSectionContainer(
    backStack: NavBackStack<NavKey>,
    databaseId: Long,
    section: StudioNavItem,
    inspectorContent: (@Composable (MainStudioViewModel) -> Unit)? = null,
    content: @Composable (MainStudioViewModel) -> Unit,
) {
    val viewModel = rememberStudioViewModel(databaseId)
    // Set selectedNavItem synchronously during composition (not via LaunchedEffect) so the
    // correct section is active on the first frame — avoids a one-frame flash of SUBSCRIPTIONS.
    remember(viewModel, section) { viewModel.selectedNavItem = section }

    StudioScaffold(
        currentSection = section,
        session = viewModel.session,
        onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
        onSectionSelect = { newItem ->
            // Replace top so the new section becomes the visible entry. Strip any dangling
            // detail-pane keys so leaving their parent section doesn't leave a stale pane.
            backStack.removeIf { it is StudioChildKey }
            val newKey = newItem.toSectionKey(databaseId)
            if (backStack.isNotEmpty()) {
                backStack[backStack.lastIndex] = newKey
            } else {
                backStack.add(newKey)
            }
        },
        inspectorContent = inspectorContent?.let { ic -> { ic(viewModel) } },
    ) {
        content(viewModel)
    }
}

/**
 * Resolves the per-databaseId [StudioSession] from Koin's studio scope, then constructs the
 * per-entry [MainStudioViewModel] using `koinViewModel(parameters = ...)`. The Nav3 view-model
 * decorator scopes the VM to *this* entry, so a fresh entry for the same databaseId reuses
 * the same session (Koin scope is keyed by databaseId) but a new VM instance — exactly the
 * behaviour we want when switching between sibling section entries.
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
 * observer has been selected yet (expanded widths). Mirrors the empty state in
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
 * query metric has been selected yet (expanded widths).
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
