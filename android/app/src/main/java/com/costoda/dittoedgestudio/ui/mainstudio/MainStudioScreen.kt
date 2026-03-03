@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.MenuOpen
import androidx.compose.material.icons.automirrored.outlined.ViewSidebar
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material3.Button
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.ui.theme.TrafficBlack
import com.costoda.dittoedgestudio.ui.theme.TrafficWhite
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.coroutines.launch
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

@Composable
fun MainStudioScreen(
    databaseId: Long,
    onBack: () -> Unit,
) {
    val viewModel: MainStudioViewModel = koinViewModel(parameters = { parametersOf(databaseId) })
    val isTablet = LocalConfiguration.current.screenWidthDp >= 600

    if (isTablet) {
        TabletLayout(viewModel = viewModel, onBack = onBack)
    } else {
        PhoneLayout(viewModel = viewModel, onBack = onBack)
    }
}

// ─── Phone layout ────────────────────────────────────────────────────────────

@Composable
private fun PhoneLayout(viewModel: MainStudioViewModel, onBack: () -> Unit) {
    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet {
                PhoneDrawerContent(
                    viewModel = viewModel,
                    onItemSelected = { scope.launch { drawerState.close() } },
                )
            }
        },
    ) {
        Scaffold(
            topBar = {
                StudioTopBar(
                    isTablet = false,
                    viewModel = viewModel,
                    onBack = onBack,
                    onNavigationClick = { scope.launch { drawerState.open() } },
                )
            },
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                ContentPlaceholder(viewModel = viewModel)
                if (!viewModel.bottomBarExpanded) {
                    FloatingActionButton(
                        onClick = { viewModel.bottomBarExpanded = true },
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(16.dp),
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                            contentDescription = "Expand bottom bar",
                        )
                    }
                }
                if (viewModel.bottomBarExpanded) {
                    StudioBottomBar(
                        viewModel = viewModel,
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(8.dp),
                    )
                }
            }
        }

        if (viewModel.inspectorVisible) {
            ModalBottomSheet(
                onDismissRequest = { viewModel.inspectorVisible = false },
                sheetState = rememberModalBottomSheetState(),
            ) {
                InspectorContent()
            }
        }

        if (viewModel.transportConfigVisible) {
            ModalBottomSheet(
                onDismissRequest = { viewModel.transportConfigVisible = false },
                sheetState = rememberModalBottomSheetState(),
            ) {
                TransportConfigContent(viewModel = viewModel)
            }
        }
    }
}

// ─── Tablet layout ───────────────────────────────────────────────────────────

@Composable
private fun TabletLayout(viewModel: MainStudioViewModel, onBack: () -> Unit) {
    Row(modifier = Modifier.fillMaxSize()) {
        // Column 1: Navigation Rail — nav items only, no FAB
        NavigationRail {
            StudioNavItem.entries.forEach { item ->
                NavigationRailItem(
                    selected = viewModel.selectedNavItem == item,
                    onClick = { viewModel.selectedNavItem = item },
                    icon = { Icon(item.icon, contentDescription = item.label) },
                    label = { Text(item.label) },
                )
            }
        }

        // Column 2: Data Panel (togglable, slides in from start)
        AnimatedVisibility(
            visible = viewModel.dataPanelVisible,
            enter = slideInHorizontally { -it },
            exit = slideOutHorizontally { -it },
        ) {
            Row {
                DataPanel(
                    viewModel = viewModel,
                    modifier = Modifier
                        .width(200.dp)
                        .fillMaxHeight(),
                )
                VerticalDivider()
            }
        }

        // Column 3: Content (takes remaining width)
        Column(modifier = Modifier.weight(1f)) {
            StudioTopBar(
                isTablet = true,
                viewModel = viewModel,
                onBack = onBack,
                onNavigationClick = { viewModel.dataPanelVisible = !viewModel.dataPanelVisible },
            )
            Box(modifier = Modifier.weight(1f)) {
                ContentPlaceholder(viewModel = viewModel)
                if (!viewModel.bottomBarExpanded) {
                    FloatingActionButton(
                        onClick = { viewModel.bottomBarExpanded = true },
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(16.dp),
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                            contentDescription = "Expand bottom bar",
                        )
                    }
                }
                if (viewModel.bottomBarExpanded) {
                    StudioBottomBar(
                        viewModel = viewModel,
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(8.dp),
                    )
                }
            }
        }

        // Column 4: Inspector Panel (togglable, slides in from end)
        AnimatedVisibility(
            visible = viewModel.inspectorVisible,
            enter = slideInHorizontally { it },
            exit = slideOutHorizontally { it },
        ) {
            InspectorPanel(
                modifier = Modifier
                    .width(300.dp)
                    .fillMaxHeight(),
            )
        }
    }

    if (viewModel.transportConfigVisible) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.transportConfigVisible = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            TransportConfigContent(viewModel = viewModel)
        }
    }
}

// ─── Shared composables ───────────────────────────────────────────────────────

@Composable
private fun StudioTopBar(
    isTablet: Boolean,
    viewModel: MainStudioViewModel,
    onBack: () -> Unit,
    onNavigationClick: () -> Unit,
) {
    TopAppBar(
        title = { Text("Edge Studio") },
        navigationIcon = {
            IconButton(onClick = onNavigationClick) {
                Icon(
                    imageVector = if (isTablet) {
                        Icons.AutoMirrored.Outlined.MenuOpen
                    } else {
                        Icons.Outlined.Menu
                    },
                    contentDescription = if (isTablet) "Toggle data panel" else "Open menu",
                )
            }
        },
        actions = {
            IconButton(onClick = { viewModel.syncEnabled = !viewModel.syncEnabled }) {
                Icon(
                    imageVector = Icons.Outlined.Sync,
                    contentDescription = "Toggle sync",
                    tint = if (viewModel.syncEnabled) {
                        Color(0xFF34C759)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Close",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
            IconButton(onClick = { viewModel.inspectorVisible = !viewModel.inspectorVisible }) {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.ViewSidebar,
                    contentDescription = "Toggle inspector",
                )
            }
        },
    )
}

@Composable
private fun PhoneDrawerContent(
    viewModel: MainStudioViewModel,
    onItemSelected: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "Edge Studio",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        HorizontalDivider()
        Spacer(modifier = Modifier.height(8.dp))

        // Nav items
        StudioNavItem.entries.forEach { item ->
            NavigationDrawerItem(
                icon = { Icon(item.icon, contentDescription = item.label) },
                label = { Text(item.label) },
                selected = viewModel.selectedNavItem == item,
                onClick = {
                    viewModel.selectedNavItem = item
                    onItemSelected()
                },
                modifier = Modifier.padding(horizontal = 12.dp),
            )
        }

        Spacer(modifier = Modifier.height(16.dp))
        HorizontalDivider()

        // Data sections
        SectionHeader(
            title = "SUBSCRIPTIONS",
            trailingIcon = Icons.Outlined.QrCodeScanner,
            onTrailingClick = {},
        )
        Text(
            text = "No Subscriptions",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )

        SectionHeader(
            title = "COLLECTIONS",
            trailingIcon = Icons.Outlined.Refresh,
            onTrailingClick = {},
        )
        Text(
            text = "No Collections",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )

        SectionHeader(title = "OBSERVERS")
        Text(
            text = "No Observers",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )

        Spacer(modifier = Modifier.height(16.dp))
        HorizontalDivider()
        Spacer(modifier = Modifier.height(16.dp))

        // FAB menu — left-aligned at bottom of drawer
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            StudioFabMenu(
                expanded = viewModel.fabMenuExpanded,
                onExpandChange = { viewModel.fabMenuExpanded = it },
                modifier = Modifier.align(Alignment.CenterStart),
                horizontalAlignment = Alignment.Start,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun DataPanel(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),
        ) {
            SectionHeader(
                title = "SUBSCRIPTIONS",
                trailingIcon = Icons.Outlined.QrCodeScanner,
                onTrailingClick = {},
            )
            Text(
                text = "No Subscriptions",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )

            SectionHeader(
                title = "COLLECTIONS",
                trailingIcon = Icons.Outlined.Refresh,
                onTrailingClick = {},
            )
            Text(
                text = "No Collections",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )

            SectionHeader(title = "OBSERVERS")
            Text(
                text = "No Observers",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        // FAB menu floats at bottom-right of the data panel
        StudioFabMenu(
            expanded = viewModel.fabMenuExpanded,
            onExpandChange = { viewModel.fabMenuExpanded = it },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(8.dp),
        )
    }
}

@Composable
private fun ContentPlaceholder(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by remember { mutableIntStateOf(0) }

    Column(modifier = modifier.fillMaxSize()) {
        if (viewModel.selectedNavItem == StudioNavItem.SUBSCRIPTIONS) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                SecondaryTabRow(
                    selectedTabIndex = selectedTabIndex,
                    modifier = Modifier.weight(1f),
                ) {
                    Tab(
                        selected = selectedTabIndex == 0,
                        onClick = { selectedTabIndex = 0 },
                        text = { Text("Peers List") },
                    )
                    Tab(
                        selected = selectedTabIndex == 1,
                        onClick = { selectedTabIndex = 1 },
                        text = { Text("Presence Viewer") },
                    )
                }
                IconButton(onClick = { viewModel.transportConfigVisible = true }) {
                    Icon(
                        imageVector = Icons.Outlined.Settings,
                        contentDescription = "Transport config",
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "${viewModel.selectedNavItem.label} — Coming Soon",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StudioBottomBar(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier.padding(start = 12.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Box {
                FilterChip(
                    selected = false,
                    onClick = { viewModel.connectionPopupVisible = true },
                    label = { Text("((•)) 0") },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Wifi,
                            contentDescription = null,
                            modifier = Modifier.height(18.dp),
                        )
                    },
                )
                DropdownMenu(
                    expanded = viewModel.connectionPopupVisible,
                    onDismissRequest = { viewModel.connectionPopupVisible = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Connections: Ditto Server: 0") },
                        onClick = { viewModel.connectionPopupVisible = false },
                    )
                }
            }
            IconButton(onClick = { viewModel.bottomBarExpanded = false }) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = "Collapse bottom bar",
                )
            }
        }
    }
}

@Composable
private fun InspectorPanel(modifier: Modifier = Modifier) {
    Row(modifier = modifier) {
        VerticalDivider()
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight(),
        ) {
            Text(
                text = "Inspector",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(16.dp),
            )
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Inspector — Coming Soon",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun InspectorContent() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
    ) {
        Text(
            text = "Inspector",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Inspector — Coming Soon",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TransportConfigContent(viewModel: MainStudioViewModel) {
    var bluetoothEnabled by remember { mutableStateOf(true) }
    var lanEnabled by remember { mutableStateOf(true) }
    var wifiAwareEnabled by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
    ) {
        Surface(
            color = SulfurYellow.copy(alpha = 0.12f),
            shape = MaterialTheme.shapes.small,
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Warning,
                    contentDescription = null,
                    tint = SulfurYellow,
                )
                Text(
                    text = "Changing transport settings will temporarily stop sync and disconnect all peers.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Peer-to-Peer Transports",
            style = MaterialTheme.typography.titleMedium,
        )

        Spacer(modifier = Modifier.height(8.dp))

        TransportToggleRow(
            icon = Icons.Outlined.Bluetooth,
            name = "Bluetooth LE",
            description = "Direct peer-to-peer sync via Bluetooth Low Energy",
            enabled = bluetoothEnabled,
            onToggle = { bluetoothEnabled = it },
        )
        TransportToggleRow(
            icon = Icons.Outlined.Wifi,
            name = "Local Area Network",
            description = "Sync with peers on the same Wi-Fi or wired network",
            enabled = lanEnabled,
            onToggle = { lanEnabled = it },
        )
        TransportToggleRow(
            icon = Icons.Outlined.WifiFind,
            name = "WiFi Aware",
            description = "WiFi Aware — devices that support WiFi Aware connections",
            enabled = wifiAwareEnabled,
            onToggle = { wifiAwareEnabled = it },
        )

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = { viewModel.transportConfigVisible = false },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Apply Transport Settings")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

// ─── FAB Menu ─────────────────────────────────────────────────────────────────

@Composable
private fun StudioFabMenu(
    expanded: Boolean,
    onExpandChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    horizontalAlignment: Alignment.Horizontal = Alignment.End,
) {
    val iconRotation by animateFloatAsState(
        targetValue = if (expanded) 45f else 0f,
        label = "fabIconRotation",
    )

    FloatingActionButtonMenu(
        expanded = expanded,
        modifier = modifier,
        horizontalAlignment = horizontalAlignment,
        button = {
            ToggleFloatingActionButton(
                checked = expanded,
                onCheckedChange = onExpandChange,
                containerColor = { SulfurYellow },
            ) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = if (expanded) "Close actions menu" else "Open actions menu",
                    modifier = Modifier.rotate(iconRotation),
                    tint = JetBlack,
                )
            }
        },
    ) {
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Filled.Add, contentDescription = null) },
            text = {
                Text(
                    text = "Subscription",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Filled.Add, contentDescription = null) },
            text = {
                Text(
                    text = "Observer",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Filled.Add, contentDescription = null) },
            text = {
                Text(
                    text = "Index",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.QrCodeScanner, contentDescription = null) },
            text = {
                Text(
                    text = "Import Subscriptions",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.Cloud, contentDescription = null) },
            text = {
                Text(
                    text = "Import Subscriptions",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.FileDownload, contentDescription = null) },
            text = {
                Text(
                    text = "Import JSON",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            containerColor = TrafficBlack,
            contentColor = TrafficWhite,
        )
    }
}

// ─── Helper composables ───────────────────────────────────────────────────────

@Composable
private fun SectionHeader(
    title: String,
    trailingIcon: ImageVector? = null,
    onTrailingClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (trailingIcon != null && onTrailingClick != null) {
            IconButton(
                onClick = onTrailingClick,
                modifier = Modifier
                    .height(24.dp)
                    .width(24.dp),
            ) {
                Icon(
                    imageVector = trailingIcon,
                    contentDescription = null,
                    modifier = Modifier
                        .height(16.dp)
                        .width(16.dp),
                )
            }
        }
    }
}

@Composable
private fun TransportToggleRow(
    icon: ImageVector,
    name: String,
    description: String,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = enabled,
            onCheckedChange = onToggle,
        )
    }
}

// ─── Preview ──────────────────────────────────────────────────────────────────

@Preview(showBackground = true)
@Composable
private fun MainStudioScreenPreview() {
    EdgeStudioTheme {
        MainStudioScreen(databaseId = 1L, onBack = {})
    }
}
