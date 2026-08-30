@file:OptIn(androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi::class)

package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirectiveWithTwoPanesOnMediumWidth
import androidx.compose.material3.adaptive.navigation3.ListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigation3.rememberListDetailSceneStrategy
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import com.costoda.dittoedgestudio.ui.adaptive.showsListDetail
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen
import com.costoda.dittoedgestudio.ui.qrcode.SubscriptionQrScannerScreen
import com.costoda.dittoedgestudio.ui.recovery.KeyFailureScreen
import com.costoda.dittoedgestudio.ui.settings.SettingsScreen
import com.costoda.dittoedgestudio.ui.welcome.WelcomeScreen
import com.costoda.dittoedgestudio.viewmodel.AppHealthViewModel
import com.costoda.dittoedgestudio.viewmodel.DbHealthState
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.coroutines.flow.first
import org.koin.androidx.compose.koinViewModel
import org.koin.compose.getKoin
import org.koin.compose.koinInject
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
 * The studio adapts at two breakpoints:
 *
 *  - **≥840dp (Expanded, multi-pane chrome)** — see
 *    [com.costoda.dittoedgestudio.ui.adaptive.studioMultiPane]: scene-driven layout under a
 *    single [StudioScaffold] with NavigationRail + top bar + Inspector.
 *  - **600–839dp (Medium — e.g. an open flip phone)**: drawer chrome (hamburger, no rail),
 *    but the `ListDetailSceneStrategy` still gets two horizontal partitions
 *    ([com.costoda.dittoedgestudio.ui.adaptive.showsListDetail]), so each section shows its
 *    listPane + detailPane side-by-side — the iPad `NavigationSplitView` two-column behavior.
 *  - **<600dp (Compact)**: single-pane. Section bodies render list-first; detail screens
 *    are pushed as drill-ins with a top-bar Up arrow. The rail items AND the section's
 *    Data Panel live inside the modal Nav Drawer.
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
    // Fork on database health BEFORE anything else. If the encrypted Room DB can't
    // be opened with the current Keystore-derived key, the rest of the graph (which
    // resolves AppDatabase via Koin singleton) would crash on first DAO call. Drive
    // the user-facing recovery surface here instead. See ui/recovery/KeyFailureScreen
    // and plans/android/config-loss-investigation.md (item B3).
    val healthViewModel: AppHealthViewModel = koinViewModel()
    val healthState by healthViewModel.state.collectAsState()
    var isRecovering by remember { mutableStateOf(false) }

    when (val current = healthState) {
        is DbHealthState.Initializing -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    Text(
                        text = "Opening database...",
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(top = 12.dp),
                    )
                }
            }
            return
        }
        is DbHealthState.KeyFailure -> {
            KeyFailureScreen(
                errorSummary = current.errorSummary,
                isWorking = isRecovering,
                onReset = { onComplete ->
                    isRecovering = true
                    healthViewModel.recover { success ->
                        isRecovering = false
                        onComplete(success)
                    }
                },
            )
            return
        }
        is DbHealthState.Healthy -> Unit // fall through to the normal graph
    }

    val backStack = rememberNavBackStack(DatabaseListKey)

    // Derive the active studio context from the back-stack top. When the top key is a
    // studio key (section or child), we wrap the NavDisplay in the StudioScaffold so the
    // chrome (Rail + top bar + Inspector) is shared across every studio entry. Non-studio
    // destinations render the NavDisplay alone. Computed BEFORE the pane directive below
    // because the Presence layout preference depends on the current section.
    val topKey = backStack.lastOrNull()
    val studioContext: Pair<StudioNavItem, Long>? = when (topKey) {
        is StudioSectionKey -> topKey.navItem to topKey.databaseId
        is StudioChildKey -> topKey.parentNavItem to topKey.databaseId
        else -> null
    }

    // App-wide preferences (Settings screen). metricsEnabled mirrors SwiftUI's
    // metricsEnabled AppStorage and drives rail-item visibility in StudioScaffold plus
    // the redirect further below; presenceSplitView gates the Presence two-pane layout.
    val appPreferences = koinInject<com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway>()
    val metricsEnabled by appPreferences.metricsEnabled
        .collectAsStateWithLifecycle(initialValue = true)
    val presenceSplitView by appPreferences.presenceSplitView
        .collectAsStateWithLifecycle(initialValue = false)

    // ── Last-open database restoration (SwiftUI SceneStorage parity) ─────────
    // Record whenever a studio session is active; on cold start, jump straight into
    // the last database (stacked above DatabaseListKey so Back still lands on the list).
    val databaseRepository = koinInject<com.costoda.dittoedgestudio.data.repository.DatabaseRepository>()
    LaunchedEffect(studioContext?.second) {
        studioContext?.second?.let { appPreferences.setLastOpenDatabaseId(it) }
    }
    var restoreAttempted by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (restoreAttempted) return@LaunchedEffect
        restoreAttempted = true
        val lastId = appPreferences.lastOpenDatabaseId.first()
        if (lastId != null &&
            backStack.size == 1 && backStack.firstOrNull() == DatabaseListKey &&
            // Guard against the database having been deleted since.
            databaseRepository.getById(lastId) != null
        ) {
            backStack.add(SubscriptionsKey(databaseId = lastId))
        }
    }

    // At Medium+ widths (≥600dp — includes an open flip phone at ~690dp) allow the
    // ListDetailSceneStrategy two horizontal partitions so list + detail sit side-by-side
    // (iPad NavigationSplitView behavior); below that, single-pane drill-in.
    // Exception: Presence with "Split Presence view" off stays single-pane so the peers
    // view / Presence Viewer gets the full width (see allowedHorizontalPartitions).
    // At Large+ widths (≥1200dp) we cap the list pane's preferred width to 320dp so the
    // detail/editor pane receives the surplus space; at Medium a slightly narrower 300dp
    // cap keeps the detail pane usable. Below Medium the strategy's own default
    // (360dp from PaneScaffoldDirective.DefaultPreferredWidth) is used.
    val windowAdaptiveInfo = currentWindowAdaptiveInfoV2()
    val windowSizeClass = windowAdaptiveInfo.windowSizeClass
    // The "two panes on Medium width" variant of the directive: Medium gets 2 partitions
    // with the M3-recommended 24dp pane spacer (the plain variant gives Medium 1 partition
    // with a 0dp spacer). We then override the partition count for the Presence-split-off
    // case and cap the list-pane width at Medium/Large.
    val baseDirective = calculatePaneScaffoldDirectiveWithTwoPanesOnMediumWidth(windowAdaptiveInfo)
    val listDetailDirective = baseDirective.copy(
        maxHorizontalPartitions = allowedHorizontalPartitions(
            showsListDetail = windowSizeClass.showsListDetail,
            currentSection = studioContext?.first,
            presenceSplitView = presenceSplitView,
        ),
        defaultPanePreferredWidth = when {
            windowSizeClass.inspectorDefaultVisible -> 320.dp // Large/XL: room for inspector
            windowSizeClass.showsListDetail -> 300.dp         // Medium: two panes, no rail
            else -> baseDirective.defaultPanePreferredWidth
        },
    )
    val listDetailStrategy = rememberListDetailSceneStrategy<NavKey>(directive = listDetailDirective)

    // Drive the Koin scope lifecycle from the current back stack contents. Must be inside
    // the composition so the underlying derivedStateOf reads tracked snapshot state.
    StudioScopeManager(backStack)

    // The NavDisplay itself — wrapped in movableContentOf so it preserves composition state
    // whether it ends up inside the StudioScaffold (studio destinations) or bare (database
    // list, editor, QR scanner).
    //
    // The movable content MUST NOT be keyed on the strategy: the directive depends on the
    // current section (Presence split-off forces one partition), so keying
    // `remember(listDetailStrategy)` would replace the movableContentOf instance on every
    // Presence↔other rail switch at ≥600dp — disposing the whole NavDisplay subtree
    // (saveable-state holder, scene/transition state) on routine navigation. A stable
    // movableContentOf + rememberUpdatedState propagates directive changes by plain
    // recomposition instead.
    val currentStrategy by rememberUpdatedState(listDetailStrategy)
    val navDisplay = remember {
        movableContentOf {
            NavDisplay(
                backStack = backStack,
                onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
                entryDecorators = listOf(
                    rememberSaveableStateHolderNavEntryDecorator(),
                    rememberViewModelStoreNavEntryDecorator(),
                ),
                sceneStrategy = currentStrategy,
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
                            onOpenSettings = { backStack.add(SettingsKey) },
                        )
                    }

                    entry<SettingsKey> {
                        SettingsScreen(onBack = { backStack.removeLastOrNull() })
                    }

                    entry<WelcomeKey> {
                        WelcomeScreen(onClose = { backStack.removeLastOrNull() })
                    }

                    entry<SubscriptionQrScannerKey> { key ->
                        // Resolves the studio session's VM (the studio keys stay on the
                        // back stack underneath, keeping the Koin scope alive).
                        val studioVm = rememberStudioViewModel(key.databaseId)
                        SubscriptionQrScannerScreen(
                            viewModel = studioVm,
                            onClose = { backStack.removeLastOrNull() },
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
                            // Below 600dp: section entry renders the CONTENT pane (observer
                            // events for the currently selected observer; "select an observer"
                            // empty state when none).
                            // ≥600dp: section entry renders the LIST pane; selection pushes
                            // ObserverEventsKey which the scene strategy places side-by-side.
                            if (studioWindowSizeClass().showsListDetail) {
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
                        StudioSectionContainer(key.databaseId, StudioNavItem.DISK_USAGE) { viewModel ->
                            DiskUsageSection(mainViewModel = viewModel)
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
                                    SideEffect { viewModel.selectedNavItem = StudioNavItem.SUBSCRIPTIONS }
                                    PresenceContentSection(viewModel = viewModel)
                                }
                            },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.SUBSCRIPTIONS,
                        ) { viewModel ->
                            // ≥600dp with "Split Presence view" ON: scene shows list
                            // (subscriptions) + detail placeholder (peers) side-by-side.
                            // Otherwise the body renders the CONTENT pane (peers / Viewer)
                            // full-width; the subscriptions list lives in the drawer
                            // (<600dp, or drawer-mode widths when split is off) and in the
                            // Presence toolbar's Subscriptions dialog (rail-mode widths).
                            if (studioWindowSizeClass().showsListDetail && presenceSplitView) {
                                PresenceListSection(
                                    viewModel = viewModel,
                                    onScanSubscriptionsQr = {
                                        backStack.add(SubscriptionQrScannerKey(key.databaseId))
                                    },
                                )
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
                        ) { viewModel ->
                            // Metrics are scoped per database by the DITTO databaseId
                            // string (same source QueryWorkbenchSection uses for
                            // QueryEditorViewModel); the nav key only carries the Room
                            // row id. Null while the session is still hydrating.
                            // Collect the session's StateFlows (not the plain snapshot
                            // getters) so this recomposes when hydration finishes/fails.
                            val dittoDatabaseId by viewModel.session.currentDittoIdFlow
                                .collectAsStateWithLifecycle()
                            val hydrateError by viewModel.session.hydrateErrorFlow
                                .collectAsStateWithLifecycle()
                            if (hydrateError != null) {
                                // Hydration failed — a spinner here would spin forever.
                                Box(
                                    modifier = Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        text = "Failed to open database: $hydrateError",
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                            } else if (dittoDatabaseId == null) {
                                Box(
                                    modifier = Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator()
                                }
                            } else {
                                // Local capture — a delegated `by` val can't smart-cast.
                                val dittoId = dittoDatabaseId!!
                                val selectedMetricsId = backStack
                                    .filterIsInstance<QueryMetricDetailKey>()
                                    .lastOrNull { it.databaseId == key.databaseId }
                                    ?.metricsId
                                // The section body is ALWAYS the executed-query list.
                                // ≥600dp: tapping a row pushes QueryMetricDetailKey and the
                                //   ListDetailSceneStrategy renders list + detail side-by-side.
                                // <600dp: M3 list-detail drill-in — the pushed detail covers
                                //   the list full-screen; system back (or the top-bar Up arrow)
                                //   returns to the list.
                                QueryMetricsListSection(
                                    databaseId = dittoId,
                                    selectedMetricsId = selectedMetricsId,
                                    onMetricPicked = { metric ->
                                        backStack.removeIf { it is QueryMetricDetailKey }
                                        backStack.add(
                                            QueryMetricDetailKey(
                                                databaseId = key.databaseId,
                                                metricsId = metric.id,
                                            ),
                                        )
                                    },
                                    onClearAll = {
                                        backStack.removeIf { it is QueryMetricDetailKey }
                                    },
                                )
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
                            QueryMetricsDetailSection(metricsId = key.metricsId)
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
                                    SideEffect { viewModel.selectedNavItem = StudioNavItem.QUERY }
                                    QueryWorkbenchContentSection(viewModel = viewModel)
                                }
                            },
                        ),
                    ) { key ->
                        StudioSectionContainer(
                            databaseId = key.databaseId,
                            section = StudioNavItem.QUERY,
                        ) { viewModel ->
                            // ≥600dp: scene shows collections list + editor detail-placeholder.
                            // <600dp: editor is the default view; collections live in the drawer.
                            if (studioWindowSizeClass().showsListDetail) {
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

    // Mirror SwiftUI's MainStudioView.onChange(metricsEnabled): when collection is turned
    // off while the user sits on a metrics section, auto-navigate to the default section
    // (Presence) so a hidden rail item is never left on screen.
    LaunchedEffect(metricsEnabled, studioContext) {
        val (section, databaseId) = studioContext ?: return@LaunchedEffect
        if (!metricsEnabled && section.isMetricsDestination) {
            backStack.removeIf { it is StudioChildKey }
            backStack[backStack.lastIndex] = SubscriptionsKey(databaseId)
        }
    }

    if (studioContext != null) {
        val (section, databaseId) = studioContext
        val viewModel = rememberStudioViewModel(databaseId)
        // SideEffect runs during the apply phase of a successful composition — before the
        // first frame draws — so the correct section is active immediately (no one-frame
        // flash, unlike LaunchedEffect) and the write is rolled back if composition fails
        // (unlike remember, which lint forbids for Unit-returning mutations). Note it
        // re-applies after EVERY recomposition: nothing else may set selectedNavItem while
        // an entry is on top, or it will be overwritten here.
        SideEffect { viewModel.selectedNavItem = section }

        // Below 600dp the section's Data Panel goes inside the modal Nav Drawer; build
        // the slot here so the drawer-aware variant (with closeDrawer plumbed through) is
        // available to the scaffold. At 600dp+ the body already renders list + detail
        // side-by-side, so the drawer carries section nav only (null slot) — EXCEPT
        // Presence with "Split Presence view" off, which keeps its subscriptions list in
        // the drawer at every drawer-mode width. Sections without a list pane
        // (Logging / AppMetrics / QueryMetrics / DiskUsage) pass null.
        val dataPanelSlot: (@Composable (closeDrawer: () -> Unit) -> Unit)? = when {
            // Presence: the subscriptions list lives in the drawer whenever it is NOT
            // beside the peers view — below 600dp (single-pane) or when the "Split
            // Presence view" setting is off.
            section == StudioNavItem.SUBSCRIPTIONS &&
                (!windowSizeClass.showsListDetail || !presenceSplitView) -> {
                { closeDrawer ->
                    PresenceListSection(
                        viewModel = viewModel,
                        onAfterAddOrEditTriggered = closeDrawer,
                        onScanSubscriptionsQr = {
                            closeDrawer()
                            backStack.add(SubscriptionQrScannerKey(databaseId))
                        },
                    )
                }
            }
            !windowSizeClass.showsListDetail -> when (section) {
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
                // Single-pane sections (no Data Panel). Query Metrics' section body is
                // the list itself, so there is nothing left to host in the drawer.
                else -> null
            }
            else -> null
        }

        // Auto-show the Welcome tour exactly once per session for a fresh
        // database (SwiftUI performLoad parity), subject to the user preference.
        // Reactive: hydration completes asynchronously after the studio opens.
        LaunchedEffect(viewModel) {
            viewModel.welcomeCandidateFlow.collect { candidate ->
                if (candidate &&
                    viewModel.consumeWelcomeTrigger() &&
                    appPreferences.showWelcomeOnNewDatabase.first()
                ) {
                    backStack.add(WelcomeKey(databaseId))
                }
            }
        }

        StudioScaffold(
            currentSection = section,
            session = viewModel.session,
            onShowWelcome = { backStack.add(WelcomeKey(databaseId)) },
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
            metricsEnabled = metricsEnabled,
            // Single-pane drill-in (e.g. a query-metric detail pushed on top of the
            // list below 600dp): the top bar shows an Up arrow that pops back to the
            // list. At 600dp+ list and detail sit side-by-side, where M3 list-detail
            // layouts must NOT show a back arrow on the detail pane.
            onNavigateUp = if (topKey is StudioChildKey && !windowSizeClass.showsListDetail) {
                { backStack.removeLastOrNull() }
            } else {
                null
            },
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
    // SideEffect applies the selection after a successful composition but before the first
    // frame draws, so the correct section is active immediately. The assignment is
    // idempotent — recomposition with the same section does not trigger further writes.
    SideEffect { viewModel.selectedNavItem = section }
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
    // The VM is parameterised on databaseId only — it looks up the actual
    // StudioSession lazily from Koin on every `viewModel.session` access. This
    // means the VM is safe to keep alive in the Activity's ViewModelStore across
    // a close-and-reopen cycle of the studio scope: after re-entry, the lookup
    // returns the freshly-created session, never the closed one.
    return koinViewModel(
        key = "MainStudioViewModel:$databaseId",
        parameters = { parametersOf(databaseId) },
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
 * How many horizontal partitions the [ListDetailSceneStrategy] may use for the current
 * context. Two panes are allowed at Medium+ widths (≥600dp) — EXCEPT while the Presence
 * section is on top with the "Split Presence view" setting off: Presence's detail (peers
 * list / Presence Viewer) is not selection-driven and needs the full width to be
 * effective, so the strategy is held to a single partition and the subscriptions list is
 * reached via the drawer / Presence toolbar dialog instead.
 *
 * Extracted as a pure function so the policy is unit-testable without a Compose runtime.
 */
internal fun allowedHorizontalPartitions(
    showsListDetail: Boolean,
    currentSection: StudioNavItem?,
    presenceSplitView: Boolean,
): Int = when {
    !showsListDetail -> 1
    currentSection == StudioNavItem.SUBSCRIPTIONS && !presenceSplitView -> 1
    else -> 2
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
