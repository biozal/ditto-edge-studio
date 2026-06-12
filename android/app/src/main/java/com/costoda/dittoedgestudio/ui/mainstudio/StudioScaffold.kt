@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ViewSidebar
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.ui.adaptive.inspectorDefaultVisible
import com.costoda.dittoedgestudio.ui.adaptive.showsRail
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.mainstudio.inspector.InspectorContentView
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.coroutines.launch

/**
 * UI chrome shared by every scene-migrated studio section (Task 4.3+).
 *
 * Layout:
 *  - Expanded (≥600dp): [NavigationRail] on the start edge, optional inspector column on the
 *    end edge (default-visible at Large widths), content slot in between.
 *  - Compact (<600dp): rail collapses into a [ModalNavigationDrawer]; inspector is reachable
 *    via the top-bar toggle (rendered as a side column for now — bottom-sheet variant comes
 *    later if user feedback demands it).
 *
 * The scaffold does NOT own session state; it takes a [StudioSession] purely for the sync-toggle
 * top-bar button (so the new shell behaves identically to the legacy one for sections we have
 * already migrated).
 *
 * The inspector column normally renders [InspectorContentView] keyed off [currentSection] (help
 * content). Sections that need a richer inspector (e.g. Query Workbench with History /
 * Favorites / JSON / Metrics tabs) pass [inspectorContent] to override the default; the override
 * is responsible for surfacing the help content itself if desired (the Query inspector exposes
 * help as one of its tabs — see [com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView]
 * usage in [com.costoda.dittoedgestudio.ui.mainstudio.QueryWorkbenchSection]).
 */
@Composable
fun StudioScaffold(
    currentSection: StudioNavItem,
    session: StudioSession,
    onBack: () -> Unit,
    onSectionSelect: (StudioNavItem) -> Unit,
    inspectorContent: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val windowSizeClass = studioWindowSizeClass()
    val expandedLayout = windowSizeClass.showsRail
    val inspectorDefault = windowSizeClass.inspectorDefaultVisible
    // Use the session-scoped inspectorVisible so the user's choice persists across rail-section
    // switches. On first access (null) fall back to the window-size-class default.
    val inspectorVisible: Boolean = session.uiState.inspectorVisible ?: inspectorDefault
    val syncEnabled by session.syncEnabled.collectAsStateWithLifecycle()

    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val coroutineScope = rememberCoroutineScope()

    if (expandedLayout) {
        Row(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
            // Rail
            NavigationRail {
                StudioNavItem.entries.forEach { item ->
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
                Row(modifier = Modifier.width(300.dp).fillMaxHeight()) {
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
        // Compact: ModalNavigationDrawer wraps rail items as a list.
        ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                ModalDrawerSheet {
                    Column {
                        StudioNavItem.entries.forEach { item ->
                            androidx.compose.material3.NavigationDrawerItem(
                                icon = { Icon(item.icon, contentDescription = item.label) },
                                label = { Text(item.label) },
                                selected = currentSection == item,
                                onClick = {
                                    onSectionSelect(item)
                                    coroutineScope.launch { drawerState.close() }
                                },
                                modifier = Modifier.padding(horizontal = 12.dp),
                            )
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
                            IconButton(onClick = { coroutineScope.launch { drawerState.open() } }) {
                                Icon(
                                    imageVector = Icons.Outlined.Menu,
                                    contentDescription = "Open menu",
                                )
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
    }
}

