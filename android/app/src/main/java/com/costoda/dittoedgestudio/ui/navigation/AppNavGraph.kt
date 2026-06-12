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
 *  - [StudioChildKey]    — compact/detail drill-ins; pushed onto the active section.
 *
 * **Studio scope ownership** is handled by [StudioScopeManager] over the back stack: a Koin
 * `studio` scope (and its [StudioSession]) is kept open while any studio entry for that
 * databaseId is on the stack, and closed when all studio entries for that id leave the stack.
 *
 * ## Chrome hoisting (Layout fix — release-1.0b5)
 *
 * The studio chrome ([StudioScaffold]: Rail + top bar + Inspector) is rendered EXACTLY ONCE,
 * wrapping the entire [NavDisplay] — never per-entry. Wrapping it per-entry causes the
 * [ListDetailSceneStrategy] to compose two scaffolds side-by-side (one in the list pane, one
 * in the detail pane), which makes the Inspector column swallow the Data Panel at ≥1200dp and
 * inverts the visual ordering (Inspector renders to the LEFT of content).
 *
 * The chrome is rendered only when the back stack top is a studio key (section or child).
 * Non-studio destinations (database list, editor, QR scanner) render the [NavDisplay] alone
 * without the studio chrome.
 *
 * The [NavDisplay] is wrapped in [movableContentOf] so that moving it between the bare and
 * scaffolded branches preserves its composition state — scene strategy, entry providers, and
 * any in-flight transitions stay intact across the move.
 *
 * **All seven rail sections run on the scene-driven shell:**
 *  - [ObserversKey] (list pane) + [ObserverEventsKey] (detail pane) via Material adaptive
 *    [ListDetailSceneStrategy]. Selecting an observer pushes [ObserverEventsKey]; the strategy
 *    automatically renders the two side-by-side at ≥600dp and as a normal drill-in below.
 *  - [LoggingKey] — single-pane Log Analyzer.
 *  - [AppMetricsKey] — single-pane App Metrics.
 *  - [DiskUsageKey] — single-pane Database Metrics.
 *  - [SubscriptionsKey] (list pane) + [PresenceContentKey] (detail pane).
 *  - [QueryMetricsKey] (list pane) + [QueryMetricDetailKey] (detail pane).
 *  - [QueryKey] (list pane) + [QueryContentKey] (detail pane / compact drill-in).
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
    // list, editor, QR scanner). Without movableContentOf the NavDisplay would be torn down
    // and re-created every time we transition between studio and non-studio destinations.
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
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY_METRICS,
                        ) { _ ->
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
                                            databaseId = key.databaseId,
                                            historyId = metric.historyId,
                                        ),
                                    )
                                },
                                onClearAll = {
                                    backStack.removeIf { it is QueryMetricDetailKey }
                                },
                            )
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
                        // Compact-only: auto-push QueryContentKey so the user lands on the editor
                        // (matches legacy phone UX). At ≥600dp the detail placeholder renders the
                        // editor inline so no push is needed.
                        val expandedLayout = studioWindowSizeClass().showsRail
                        LaunchedEffect(key.databaseId, expandedLayout) {
                            if (!expandedLayout && backStack.none { it is QueryContentKey }) {
                                backStack.add(QueryContentKey(databaseId = key.databaseId))
                            } else if (expandedLayout) {
                                backStack.removeIf { it is QueryContentKey }
                            }
                        }
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY,
                        ) { viewModel ->
                            QueryWorkbenchListSection(
                                viewModel = viewModel,
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
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY,
                        ) { viewModel ->
                            QueryWorkbenchContentSection(viewModel = viewModel)
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

        StudioScaffold(
            currentSection = section,
            session = viewModel.session,
            // Close button (top-bar X): exit the studio entirely. Pop every studio entry
            // (sections + children) for this databaseId so we land back on whatever
            // non-studio key precedes them (typically DatabaseListKey). Matches legacy
            // Close-button semantics — system back continues to pop one entry at a time
            // via the NavDisplay's own onBack.
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
 * [AppNavGraph] level, wrapping the entire [NavDisplay]. Each entry's content is rendered
 * bare so the [ListDetailSceneStrategy] can compose list + detail panes side-by-side under
 * a single scaffold (one Rail, one top bar, one Inspector on the trailing edge).
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
