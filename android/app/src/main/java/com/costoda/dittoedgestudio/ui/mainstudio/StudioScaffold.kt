@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.focusable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ViewSidebar
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.window.core.layout.WindowSizeClass
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.ui.adaptive.inspectorDefaultVisible
import com.costoda.dittoedgestudio.ui.adaptive.inspectorWidth
import com.costoda.dittoedgestudio.ui.adaptive.studioMultiPane
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.mainstudio.inspector.InspectorContentView
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.coroutines.launch

/**
 * UI chrome shared by every scene-migrated studio section.
 *
 * Layout:
 *  - **≥840dp (Expanded+)**: [NavigationRail] on the start edge, optional inspector column
 *    on the end edge (default-visible at Large widths), `content` slot in between (which
 *    hosts the scene-driven `listPane | detailPane` layout).
 *  - **600–839dp (Medium — e.g. an open flip phone)**: drawer chrome (hamburger, no rail
 *    column), but the `content` slot still hosts the two-pane `listPane | detailPane`
 *    scene — the drawer carries rail items only. Exception: Presence with "Split Presence
 *    view" off keeps its Data Panel (subscriptions) in the drawer at these widths too.
 *  - **<600dp (Compact)**: rail collapses into a [ModalNavigationDrawer] that contains
 *    BOTH the rail items (section nav) AND the current section's Data Panel — rail items
 *    at top, divider, Data Panel below. The body is single-pane (list-first drill-in for
 *    Query Metrics / Observation; Content Pane default elsewhere). Pushed drill-in
 *    details show an Up arrow in place of the hamburger. Selecting anything in the
 *    drawer closes it. Inspector renders as a [ModalBottomSheet].
 *
 * The scaffold does NOT own session state; it takes a [StudioSession] purely for the
 * sync-toggle top-bar button (so the new shell behaves identically to the legacy one for
 * sections we have already migrated).
 *
 * The inspector column normally renders [InspectorContentView] keyed off [currentSection] (help
 * content). Sections that need a richer inspector (e.g. Query Workbench with History /
 * Favorites / JSON / Metrics tabs) pass [inspectorContent] to override the default; the override
 * is responsible for surfacing the help content itself if desired (the Query inspector exposes
 * help as one of its tabs — see [com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView]
 * usage in [com.costoda.dittoedgestudio.ui.mainstudio.QueryWorkbenchSection]).
 *
 * @param dataPanelContent Below 600dp (and at drawer-mode widths for Presence with
 *   "Split Presence view" off), the Data Panel (section list) is rendered inside the
 *   drawer below the rail items. The lambda receives a `closeDrawer` callback that the
 *   list content should invoke when the user picks an item so the drawer closes and the
 *   chosen item drives the Content Pane. Pass null for sections without a Data Panel
 *   (Logging, AppMetrics, QueryMetrics, DiskUsage). Ignored at ≥840dp (the scene
 *   strategy provides the listPane).
 */
@Composable
fun StudioScaffold(
    currentSection: StudioNavItem,
    session: StudioSession,
    onBack: () -> Unit,
    onSectionSelect: (StudioNavItem) -> Unit,
    inspectorContent: (@Composable () -> Unit)? = null,
    dataPanelContent: (@Composable (closeDrawer: () -> Unit) -> Unit)? = null,
    // "Collect Metrics" setting — when false the App Metrics / Query Metrics rail items
    // are hidden (mirrors SwiftUI's MainStudioView.availableDestinations). Defaults to
    // true so existing call sites and layout tests compile unchanged.
    metricsEnabled: Boolean = true,
    // Drawer mode only: when non-null a compact-width drill-in (StudioChildKey) is on top
    // and the top bar shows an Up arrow instead of the hamburger (M3 list-detail: pushed
    // detail screens get a back affordance; side-by-side panes never do).
    onNavigateUp: (() -> Unit)? = null,
    // Optional override for testability: pass a fixed WindowSizeClass in Compose UI tests to
    // exercise both layout branches without needing a real device window of a specific size.
    // Production code omits this arg and lets studioWindowSizeClass() read the real window.
    windowSizeClass: WindowSizeClass = studioWindowSizeClass(),
    content: @Composable () -> Unit,
) {
    val multiPaneLayout = windowSizeClass.studioMultiPane
    val inspectorDefault = windowSizeClass.inspectorDefaultVisible
    val inspectorColumnWidth = windowSizeClass.inspectorWidth
    // Use the session-scoped inspectorVisible so the user's choice persists across rail-section
    // switches. On first access (null) fall back to the window-size-class default.
    val inspectorVisible: Boolean = session.uiState.inspectorVisible ?: inspectorDefault
    val syncEnabled by session.syncEnabled.collectAsStateWithLifecycle()

    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val coroutineScope = rememberCoroutineScope()

    // Rail items actually shown — metrics sections drop out when collection is disabled.
    val railItems = remember(metricsEnabled) { StudioNavItem.visibleEntries(metricsEnabled) }

    // Back button: when the drawer is open, the back press should close the
    // drawer (matches the long-standing Android pattern), NOT pop the whole
    // studio entry. Only enabled while the drawer is open so the handler doesn't
    // interfere with normal back navigation when the drawer is dismissed.
    BackHandler(enabled = drawerState.isOpen) {
        coroutineScope.launch { drawerState.close() }
    }

    // Ctrl+1..7 section-switch shortcut modifier — shared by both layout branches.
    // onPreviewKeyEvent on the outermost focusable container intercepts the event before any
    // descendant (rail items, text fields) can consume it. The container is made focusable()
    // so it participates in focus traversal and can receive key events when nothing inside it
    // holds focus. The FocusRequester + LaunchedEffect seed focus on the scaffold root on
    // first composition so the shortcuts fire from a pure-touch entry (without a hardware
    // keypress first) — required for connected-display / Bluetooth keyboard scenarios where
    // the user expects shortcuts to work the moment the studio appears.
    val railFocus = remember { FocusRequester() }
    LaunchedEffect(railFocus) {
        runCatching { railFocus.requestFocus() }
    }
    val railShortcutModifier = Modifier
        .focusRequester(railFocus)
        .onPreviewKeyEvent { event ->
            if (event.type == KeyEventType.KeyDown) {
                val target = studioShortcutFor(event, railItems)
                if (target != null) {
                    onSectionSelect(target)
                    return@onPreviewKeyEvent true
                }
            }
            false
        }
        .focusable()

    if (multiPaneLayout) {
        Row(modifier = Modifier.fillMaxSize().safeDrawingPadding().then(railShortcutModifier)) {
            // Rail — tagged "StudioRail" so instrumented layout tests can assert its presence
            // (multi-pane) or absence (drawer mode) without depending on implementation details.
            NavigationRail(modifier = Modifier.testTag("StudioRail")) {
                railItems.forEach { item ->
                    NavigationRailItem(
                        selected = currentSection == item,
                        onClick = { onSectionSelect(item) },
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        colors = NavigationRailItemDefaults.colors(
                            indicatorColor = com.costoda.dittoedgestudio.ui.theme.SulfurYellow,
                            selectedIconColor = com.costoda.dittoedgestudio.ui.theme.JetBlack,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
            }

            // Center column: top bar + content
            Column(modifier = Modifier.weight(1f)) {
                TopAppBar(
                    title = { Text(currentSection.label) },
                    actions = {
                        IconButton(onClick = { session.toggleSync() }) {
                            Icon(
                                imageVector = Icons.Outlined.Sync,
                                contentDescription = "Toggle sync",
                                tint = if (syncEnabled) Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = onBack) {
                            Icon(
                                imageVector = Icons.Filled.Close,
                                contentDescription = "Close",
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                        IconButton(onClick = { session.uiState.inspectorVisible = !inspectorVisible }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Outlined.ViewSidebar,
                                contentDescription = "Toggle inspector",
                            )
                        }
                    },
                )
                Box(modifier = Modifier.weight(1f)) { content() }
            }

            // Inspector
            AnimatedVisibility(
                visible = inspectorVisible,
                enter = slideInHorizontally { it },
                exit = slideOutHorizontally { it },
            ) {
                Row(modifier = Modifier.width(inspectorColumnWidth).fillMaxHeight()) {
                    VerticalDivider()
                    Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                        if (inspectorContent != null) {
                            inspectorContent()
                        } else {
                            InspectorContentView(
                                selectedNavItem = currentSection,
                                modifier = Modifier.fillMaxHeight(),
                            )
                        }
                    }
                }
            }
        }
    } else {
        // Drawer mode (<840dp): the drawer holds BOTH the rail items (section nav) AND the
        // current section's Data Panel. The top bar exposes a hamburger to open it. The
        // Content Pane is the default view in the body.
        val inspectorSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val closeDrawer: () -> Unit = { coroutineScope.launch { drawerState.close() } }
        // Apply rail-section shortcuts to the compact root so they work regardless of layout.
        Box(modifier = Modifier.fillMaxSize().then(railShortcutModifier)) {
            ModalNavigationDrawer(
                drawerState = drawerState,
                drawerContent = {
                    ModalDrawerSheet {
                        Column(modifier = Modifier.fillMaxSize()) {
                            // Section nav (rail items). The list of rail items is short and
                            // doesn't need its own scroll container.
                            railItems.forEach { item ->
                                androidx.compose.material3.NavigationDrawerItem(
                                    icon = { Icon(item.icon, contentDescription = item.label) },
                                    label = { Text(item.label) },
                                    selected = currentSection == item,
                                    onClick = {
                                        onSectionSelect(item)
                                        closeDrawer()
                                    },
                                    modifier = Modifier.padding(horizontal = 12.dp),
                                )
                            }

                            // Data Panel for the current section (when present). Hosted in a
                            // weighted Box so the data panel receives a bounded height — its
                            // own `fillMaxSize().verticalScroll(...)` provides scrolling.
                            if (dataPanelContent != null) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(vertical = 8.dp),
                                )
                                Box(modifier = Modifier.weight(1f).fillMaxSize()) {
                                    dataPanelContent(closeDrawer)
                                }
                            }
                        }
                    }
                },
            ) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(currentSection.label) },
                            navigationIcon = {
                                if (onNavigateUp != null) {
                                    IconButton(onClick = onNavigateUp) {
                                        Icon(
                                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                                            contentDescription = "Back",
                                        )
                                    }
                                } else {
                                    IconButton(onClick = { coroutineScope.launch { drawerState.open() } }) {
                                        Icon(
                                            imageVector = Icons.Outlined.Menu,
                                            contentDescription = "Open menu",
                                        )
                                    }
                                }
                            },
                            actions = {
                                IconButton(onClick = { session.toggleSync() }) {
                                    Icon(
                                        imageVector = Icons.Outlined.Sync,
                                        contentDescription = "Toggle sync",
                                        tint = if (syncEnabled) Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = onBack) {
                                    Icon(
                                        imageVector = Icons.Filled.Close,
                                        contentDescription = "Close",
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                }
                                IconButton(onClick = { session.uiState.inspectorVisible = !inspectorVisible }) {
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Outlined.ViewSidebar,
                                        contentDescription = "Toggle inspector",
                                    )
                                }
                            },
                        )
                    },
                ) { padding ->
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) { content() }
                }
            }

            // Inspector bottom sheet for drawer-mode layout.
            if (inspectorVisible) {
                ModalBottomSheet(
                    onDismissRequest = { session.uiState.inspectorVisible = false },
                    sheetState = inspectorSheetState,
                ) {
                    if (inspectorContent != null) {
                        inspectorContent()
                    } else {
                        InspectorContentView(
                            selectedNavItem = currentSection,
                            modifier = Modifier.fillMaxHeight(),
                        )
                    }
                }
            }
        } // end railShortcutModifier Box (drawer-mode layout)
    }
}
