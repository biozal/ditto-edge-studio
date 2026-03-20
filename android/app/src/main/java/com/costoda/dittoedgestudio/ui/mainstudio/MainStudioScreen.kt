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
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
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
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.ClearAll
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.material3.NavigationRailItemDefaults
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
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.ui.mainstudio.inspector.InspectorContentView
import com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.AppMetricsScreen
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.QueryMetricsScreen
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import org.koin.compose.koinInject
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.ui.theme.TrafficBlack
import com.costoda.dittoedgestudio.ui.theme.TrafficWhite
import androidx.compose.runtime.collectAsState
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.viewmodel.PeersUiState
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
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
    val currentDittoId = viewModel.currentDittoId
    val queryEditorViewModel: QueryEditorViewModel? = if (currentDittoId != null) {
        koinViewModel(parameters = { parametersOf(currentDittoId) })
    } else null

    if (isTablet) {
        TabletLayout(viewModel = viewModel, queryEditorViewModel = queryEditorViewModel, onBack = onBack)
    } else {
        PhoneLayout(viewModel = viewModel, queryEditorViewModel = queryEditorViewModel, onBack = onBack)
    }
}

// ─── Phone layout ────────────────────────────────────────────────────────────

@Composable
private fun PhoneLayout(
    viewModel: MainStudioViewModel,
    queryEditorViewModel: QueryEditorViewModel?,
    onBack: () -> Unit,
) {
    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet {
                PhoneDrawerContent(
                    viewModel = viewModel,
                    onItemSelected = { scope.launch { drawerState.close() } },
                    onClose = { scope.launch { drawerState.close() } },
                )
            }
        },
    ) {
        Scaffold(
            topBar = {
                StudioTopBar(

                    viewModel = viewModel,
                    queryEditorViewModel = queryEditorViewModel,
                    isTablet = false,
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
                ContentPlaceholder(viewModel = viewModel, queryEditorViewModel = queryEditorViewModel)
                // Show query bottom bar when QUERY is selected, else show general bottom bar
                if (viewModel.selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null) {
                    QueryBottomBar(
                        viewModel = queryEditorViewModel,
                        mainViewModel = viewModel,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(8.dp),
                    )
                } else {
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
        }

        if (viewModel.inspectorVisible) {
            ModalBottomSheet(
                onDismissRequest = { viewModel.inspectorVisible = false },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            ) {
                InspectorContent(
                    selectedNavItem = viewModel.selectedNavItem,
                    queryEditorViewModel = queryEditorViewModel,
                )
            }
        }

        if (viewModel.transportConfigVisible) {
            ModalBottomSheet(
                onDismissRequest = { viewModel.transportConfigVisible = false },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            ) {
                TransportConfigContent(viewModel = viewModel)
            }
        }

        SubscriptionEditorSheetIfNeeded(viewModel)
    }
}

// ─── Tablet layout ───────────────────────────────────────────────────────────

@Composable
private fun TabletLayout(
    viewModel: MainStudioViewModel,
    queryEditorViewModel: QueryEditorViewModel?,
    onBack: () -> Unit,
) {
    Row(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
        // Column 1: Navigation Rail — nav items only, no FAB
        NavigationRail {
            StudioNavItem.entries.forEach { item ->
                NavigationRailItem(
                    selected = viewModel.selectedNavItem == item,
                    onClick = { viewModel.selectedNavItem = item },
                    icon = { Icon(item.icon, contentDescription = item.label) },
                    colors = NavigationRailItemDefaults.colors(
                        indicatorColor = SulfurYellow,
                        selectedIconColor = JetBlack,
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
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
                queryEditorViewModel = queryEditorViewModel,
                onBack = onBack,
                onNavigationClick = { viewModel.dataPanelVisible = !viewModel.dataPanelVisible },
            )
            Box(modifier = Modifier.weight(1f)) {
                ContentPlaceholder(viewModel = viewModel, queryEditorViewModel = queryEditorViewModel)
                // Show query bottom bar when QUERY is selected, else show general bottom bar
                if (viewModel.selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null) {
                    QueryBottomBar(
                        viewModel = queryEditorViewModel,
                        mainViewModel = viewModel,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(8.dp),
                    )
                } else {
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
        }

        // Column 4: Inspector Panel (togglable, slides in from end)
        AnimatedVisibility(
            visible = viewModel.inspectorVisible,
            enter = slideInHorizontally { it },
            exit = slideOutHorizontally { it },
        ) {
            InspectorPanel(
                viewModel = viewModel,
                queryEditorViewModel = queryEditorViewModel,
                modifier = Modifier
                    .width(300.dp)
                    .fillMaxHeight(),
            )
        }
    }

    if (viewModel.transportConfigVisible) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.transportConfigVisible = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            TransportConfigContent(viewModel = viewModel)
        }
    }

    SubscriptionEditorSheetIfNeeded(viewModel)

    if (viewModel.showAddIndex) {
        val collections by viewModel.collections.collectAsState()
        AddIndexSheet(
            collections = collections,
            onAdd = { collection, field -> viewModel.addIndex(collection, field) },
            onDismiss = { viewModel.showAddIndex = false },
        )
    }
}

// ─── Shared composables ───────────────────────────────────────────────────────

@Composable
private fun StudioTopBar(
    isTablet: Boolean,
    viewModel: MainStudioViewModel,
    queryEditorViewModel: QueryEditorViewModel?,
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
            // Show query controls when QUERY nav item is selected
            if (viewModel.selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null) {
                QueryTopBarControls(viewModel = queryEditorViewModel)
            }
            IconButton(onClick = { viewModel.toggleSync() }) {
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
private fun QueryTopBarControls(viewModel: QueryEditorViewModel) {
    val isExecuting by viewModel.isExecuting.collectAsState()

    IconButton(
        onClick = { viewModel.executeQuery() },
        enabled = !isExecuting,
    ) {
        if (isExecuting) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
            )
        } else {
            Icon(
                imageVector = Icons.Outlined.PlayArrow,
                contentDescription = "Run query",
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun PhoneDrawerContent(
    viewModel: MainStudioViewModel,
    onItemSelected: () -> Unit,
    onClose: () -> Unit,
) {
    val subscriptions by viewModel.subscriptions.collectAsState()
    val collections by viewModel.collections.collectAsState()
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxHeight()
            .verticalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Edge Studio",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .weight(1f)
                    .padding(vertical = 12.dp),
            )
            IconButton(onClick = onClose) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Close menu",
                )
            }
        }
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
        if (subscriptions.isEmpty()) {
            Text(
                text = "No Subscriptions",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        } else {
            subscriptions.forEach { sub ->
                SubscriptionListItem(
                    subscription = sub,
                    onEdit = { viewModel.editingSubscription = sub },
                    onDelete = { viewModel.removeSubscription(sub.id) },
                )
            }
        }

        SectionHeader(
            title = "COLLECTIONS",
            trailingIcon = Icons.Outlined.Refresh,
            onTrailingClick = { scope.launch { viewModel.collectionsRepository.refresh() } },
        )
        if (collections.isEmpty()) {
            Text(
                text = "No Collections",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        } else {
            collections.forEach { collection ->
                CollectionListItem(collection = collection)
            }
        }

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
                viewModel = viewModel,
                expanded = viewModel.fabMenuExpanded,
                onExpandChange = { viewModel.fabMenuExpanded = it },
                modifier = Modifier.align(Alignment.CenterStart),
                horizontalAlignment = Alignment.Start,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))
    }

    if (viewModel.showAddIndex) {
        AddIndexSheet(
            collections = collections,
            onAdd = { collection, field -> viewModel.addIndex(collection, field) },
            onDismiss = { viewModel.showAddIndex = false },
        )
    }
}

@Composable
private fun DataPanel(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    val subscriptions by viewModel.subscriptions.collectAsState()
    val collections by viewModel.collections.collectAsState()
    val scope = rememberCoroutineScope()

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
            if (subscriptions.isEmpty()) {
                Text(
                    text = "No Subscriptions",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            } else {
                subscriptions.forEach { sub ->
                    SubscriptionListItem(
                        subscription = sub,
                        onEdit = { viewModel.editingSubscription = sub },
                        onDelete = { viewModel.removeSubscription(sub.id) },
                    )
                }
            }

            SectionHeader(
                title = "COLLECTIONS",
                trailingIcon = Icons.Outlined.Refresh,
                onTrailingClick = { scope.launch { viewModel.collectionsRepository.refresh() } },
            )
            if (collections.isEmpty()) {
                Text(
                    text = "No Collections",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            } else {
                collections.forEach { collection ->
                    CollectionListItem(collection = collection)
                }
            }

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
            viewModel = viewModel,
            expanded = viewModel.fabMenuExpanded,
            onExpandChange = { viewModel.fabMenuExpanded = it },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(8.dp),
        )

        if (viewModel.showAddIndex) {
            AddIndexSheet(
                collections = collections,
                onAdd = { collection, field -> viewModel.addIndex(collection, field) },
                onDismiss = { viewModel.showAddIndex = false },
            )
        }
    }
}

@Composable
private fun ContentPlaceholder(
    viewModel: MainStudioViewModel,
    queryEditorViewModel: QueryEditorViewModel?,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    val peersUiState by viewModel.peersUiState.collectAsState()
    val networkInterfaces by viewModel.networkInterfaces.collectAsState()
    val p2pTransports by viewModel.p2pTransports.collectAsState()

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
        ) {
            when {
                viewModel.selectedNavItem == StudioNavItem.SUBSCRIPTIONS && selectedTabIndex == 0 -> {
                    DittoPermissionHandler()
                    ConnectedPeersScreen(
                        peersUiState = peersUiState,
                        networkInterfaces = networkInterfaces,
                        p2pTransports = p2pTransports,
                        onLoadDiagnostics = { viewModel.loadNetworkDiagnostics() },
                    )
                }
                viewModel.selectedNavItem == StudioNavItem.LOGGING -> {
                    LoggingScreen(captureService = viewModel.loggingCaptureService)
                }
                viewModel.selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null -> {
                    val isTablet = LocalConfiguration.current.screenWidthDp >= 600
                    QueryEditorScreen(
                        viewModel = queryEditorViewModel,

                        modifier = Modifier.fillMaxSize(),
                    )
                }
                viewModel.selectedNavItem == StudioNavItem.APP_METRICS -> {
                    val appMetricsViewModel: AppMetricsViewModel = koinViewModel()
                    AppMetricsScreen(
                        viewModel = appMetricsViewModel,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                viewModel.selectedNavItem == StudioNavItem.QUERY_METRICS -> {
                    val metricsRepo: QueryMetricsRepository = koinInject()
                    QueryMetricsScreen(
                        metricsRepository = metricsRepo,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                else -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "${viewModel.selectedNavItem.label} — Coming Soon",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StudioBottomBar(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    val connections by viewModel.connectionsByTransport.collectAsState()

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
                    label = { Text("((•)) ${connections.total}") },
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
                        text = { Text("Bluetooth: ${connections.bluetooth}") },
                        onClick = { viewModel.connectionPopupVisible = false },
                    )
                    DropdownMenuItem(
                        text = { Text("LAN: ${connections.lan}") },
                        onClick = { viewModel.connectionPopupVisible = false },
                    )
                    DropdownMenuItem(
                        text = { Text("P2P WiFi: ${connections.p2pWifi}") },
                        onClick = { viewModel.connectionPopupVisible = false },
                    )
                    DropdownMenuItem(
                        text = { Text("WebSocket: ${connections.webSocket}") },
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
private fun QueryBottomBar(
    viewModel: QueryEditorViewModel,
    mainViewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    val connections by mainViewModel.connectionsByTransport.collectAsState()
    val queryResult by viewModel.queryResult.collectAsState()
    val currentPage by viewModel.currentPage.collectAsState()
    val pageSize by viewModel.pageSize.collectAsState()
    val pageSizeOptions by viewModel.pageSizeOptions.collectAsState()

    var connectionsExpanded by remember { mutableStateOf(false) }
    var overflowExpanded by remember { mutableStateOf(false) }
    var pageSizeExpanded by remember { mutableStateOf(false) }

    val totalCount = queryResult?.totalCount ?: 0
    val pageCount = if (totalCount == 0) 1 else (totalCount + pageSize - 1) / pageSize

    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // ── Left: Peers count with dropdown ──────────────────────────────
            Box {
                FilterChip(
                    selected = false,
                    onClick = { connectionsExpanded = true },
                    label = { Text("((•)) ${connections.total}", color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Wifi,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                    },
                )
                DropdownMenu(
                    expanded = connectionsExpanded,
                    onDismissRequest = { connectionsExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Bluetooth: ${connections.bluetooth}") },
                        onClick = { connectionsExpanded = false },
                    )
                    DropdownMenuItem(
                        text = { Text("LAN: ${connections.lan}") },
                        onClick = { connectionsExpanded = false },
                    )
                    DropdownMenuItem(
                        text = { Text("P2P WiFi: ${connections.p2pWifi}") },
                        onClick = { connectionsExpanded = false },
                    )
                    DropdownMenuItem(
                        text = { Text("WebSocket: ${connections.webSocket}") },
                        onClick = { connectionsExpanded = false },
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // ── Center: Page navigation ───────────────────────────────────────
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

            // ── Right: Overflow menu ──────────────────────────────────────────
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
                    // Page size sub-menu trigger
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

                // Page size dropdown (shown separately after overflow closes)
                DropdownMenu(
                    expanded = pageSizeExpanded,
                    onDismissRequest = { pageSizeExpanded = false },
                ) {
                    pageSizeOptions.forEach { size ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    text = "$size",
                                    color = if (size == pageSize) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurface,
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
}

@Composable
private fun InspectorPanel(
    viewModel: MainStudioViewModel,
    queryEditorViewModel: QueryEditorViewModel?,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier) {
        VerticalDivider()
        if (viewModel.selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null) {
            QueryInspectorView(
                viewModel = queryEditorViewModel,
                modifier = Modifier.weight(1f),
            )
        } else {
            InspectorContentView(
                selectedNavItem = viewModel.selectedNavItem,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun InspectorContent(
    selectedNavItem: StudioNavItem,
    queryEditorViewModel: QueryEditorViewModel?,
) {
    if (selectedNavItem == StudioNavItem.QUERY && queryEditorViewModel != null) {
        QueryInspectorView(
            viewModel = queryEditorViewModel,
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.8f),
        )
    } else {
        InspectorContentView(
            selectedNavItem = selectedNavItem,
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.8f),
        )
    }
}

@Composable
private fun SubscriptionEditorSheetIfNeeded(viewModel: MainStudioViewModel) {
    viewModel.editingSubscription?.let { sub ->
        SubscriptionEditorSheet(
            initial = sub,
            onSave = { name, query ->
                if (sub.id == 0L) viewModel.addSubscription(name, query)
                else viewModel.updateSubscription(sub.copy(name = name, query = query))
            },
            onDismiss = { viewModel.editingSubscription = null },
        )
    }
}

@Composable
private fun TransportConfigContent(viewModel: MainStudioViewModel) {
    var bluetoothEnabled by remember { mutableStateOf(viewModel.transportBluetoothEnabled) }
    var lanEnabled by remember { mutableStateOf(viewModel.transportLanEnabled) }
    var wifiAwareEnabled by remember { mutableStateOf(viewModel.transportWifiAwareEnabled) }

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
            onClick = { viewModel.applyTransportSettings(bluetoothEnabled, lanEnabled, wifiAwareEnabled) },
            enabled = !viewModel.isApplyingTransport,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (viewModel.isApplyingTransport) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp,
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(if (viewModel.isApplyingTransport) "Applying…" else "Apply Transport Settings")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

// ─── FAB Menu ─────────────────────────────────────────────────────────────────

@Composable
private fun StudioFabMenu(
    viewModel: MainStudioViewModel,
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
            onClick = {
                viewModel.editingSubscription = DittoSubscription()
                onExpandChange(false)
            },
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
            onClick = {
                viewModel.showAddIndex = true
                onExpandChange(false)
            },
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

// ─── Subscription list item ───────────────────────────────────────────────────

@Composable
private fun SubscriptionListItem(
    subscription: DittoSubscription,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = subscription.name.ifBlank { subscription.query },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subscription.name.isNotBlank()) {
                Text(
                    text = subscription.query,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(onClick = onEdit) {
            Icon(
                imageVector = Icons.Outlined.Edit,
                contentDescription = "Edit subscription",
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = "Delete subscription",
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
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
