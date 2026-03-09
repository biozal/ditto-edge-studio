@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Clear
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.displayName
import com.costoda.dittoedgestudio.domain.model.shortName
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import kotlinx.coroutines.launch

private val ALL_LEVELS = DittoLogLevel.entries.toList()

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LoggingScreen(
    captureService: DittoLogCaptureService,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    // ── StateFlow collectors ────────────────────────────────────────────────
    val liveEntries by captureService.liveEntries.collectAsState()
    val historicalEntries by captureService.historicalEntries.collectAsState()
    val appEntries by captureService.appEntries.collectAsState()
    val isLoading by captureService.isLoading.collectAsState()
    val pendingCount by captureService.pendingNewEntriesCount.collectAsState()
    val bufferNearlyFull by captureService.bufferNearlyFull.collectAsState()
    val entriesDropped by captureService.entriesDropped.collectAsState()

    // ── Filter state ────────────────────────────────────────────────────────
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    var selectedLevels by remember { mutableStateOf(ALL_LEVELS.toSet()) }
    var selectedComponent by remember { mutableStateOf(LogComponent.ALL) }
    var searchQuery by remember { mutableStateOf("") }
    var sdkLogLevel by remember { mutableStateOf(DittoLogger.minimumLogLevel) }
    var footerExpanded by remember { mutableStateOf(true) }
    var sdkLevelDropdownExpanded by remember { mutableStateOf(false) }
    var componentDropdownExpanded by remember { mutableStateOf(false) }

    // ── Auto-pause when user scrolls away from bottom ───────────────────────
    val isAtBottom by remember { derivedStateOf { !listState.canScrollForward } }
    LaunchedEffect(isAtBottom) {
        captureService.isLivePaused = !isAtBottom
        if (isAtBottom) captureService.resetPendingCount()
    }

    // ── Filtered display list ────────────────────────────────────────────────
    val displayEntries by remember {
        derivedStateOf {
            val source = when (selectedTabIndex) {
                0 -> {
                    // SDK tab: merge historical + live, dedup by rawLine prefix
                    val all = (historicalEntries + liveEntries)
                        .sortedBy { it.timestamp }
                    all
                }
                else -> appEntries
            }
            source
                .filter { entry ->
                    entry.level in selectedLevels &&
                        (selectedTabIndex != 0 || selectedComponent == LogComponent.ALL ||
                            entry.component == selectedComponent) &&
                        (searchQuery.isBlank() || entry.message.contains(searchQuery, ignoreCase = true))
                }
                .takeLast(DittoLogCaptureService.MAX_DISPLAYED_ENTRIES)
        }
    }

    // ── High volume warning conditions ───────────────────────────────────────
    val showHighVolumeWarning = selectedTabIndex == 0 &&
        (sdkLogLevel == DittoLogLevel.Debug || sdkLogLevel == DittoLogLevel.Verbose)

    // ── Lifecycle ────────────────────────────────────────────────────────────
    LaunchedEffect(Unit) {
        captureService.startLiveCapture()
        captureService.loadHistoricalLogs(context.cacheDir)
        captureService.loadAppLogs()
    }
    DisposableEffect(Unit) {
        onDispose { captureService.stopLiveCapture() }
    }

    Column(modifier = modifier.fillMaxSize()) {
        // ── Title row ────────────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Logs",
                style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )

            // SDK Log Level dropdown
            ExposedDropdownMenuBox(
                expanded = sdkLevelDropdownExpanded,
                onExpandedChange = { sdkLevelDropdownExpanded = it },
                modifier = Modifier.width(140.dp),
            ) {
                OutlinedTextField(
                    value = "SDK: ${sdkLogLevel.displayName}",
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sdkLevelDropdownExpanded) },
                    modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                    textStyle = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    singleLine = true,
                )
                ExposedDropdownMenu(
                    expanded = sdkLevelDropdownExpanded,
                    onDismissRequest = { sdkLevelDropdownExpanded = false },
                ) {
                    ALL_LEVELS.forEach { level ->
                        DropdownMenuItem(
                            text = { Text(level.displayName) },
                            onClick = {
                                sdkLogLevel = level
                                DittoLogger.minimumLogLevel = level
                                sdkLevelDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(4.dp))
            IconButton(onClick = {
                captureService.loadHistoricalLogs(context.cacheDir)
                captureService.loadAppLogs()
            }) {
                Icon(Icons.Outlined.Refresh, contentDescription = "Refresh logs")
            }
        }

        // ── High volume warning banner ────────────────────────────────────────
        AnimatedVisibility(visible = showHighVolumeWarning) {
            Surface(
                color = androidx.compose.ui.graphics.Color(0xFFFF9500).copy(alpha = 0.12f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                shape = androidx.compose.material3.MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier.padding(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.Warning,
                        contentDescription = null,
                        tint = androidx.compose.ui.graphics.Color(0xFFFF9500),
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        text = "High log volume — UI throttled to 2 updates/sec, showing last 200 entries",
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }

        // ── Buffer nearly full warning ────────────────────────────────────────
        AnimatedVisibility(visible = bufferNearlyFull) {
            Surface(
                color = androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                shape = androidx.compose.material3.MaterialTheme.shapes.small,
            ) {
                Text(
                    text = "Log buffer nearly full — oldest entries will be dropped",
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(8.dp),
                )
            }
        }

        // ── Entries dropped warning ────────────────────────────────────────────
        AnimatedVisibility(visible = entriesDropped) {
            Surface(
                color = androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                shape = androidx.compose.material3.MaterialTheme.shapes.small,
            ) {
                Text(
                    text = "Log entries dropped (ingestion exceeded buffer)",
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(8.dp),
                )
            }
        }

        // ── Source tabs ──────────────────────────────────────────────────────
        SecondaryTabRow(selectedTabIndex = selectedTabIndex) {
            Tab(
                selected = selectedTabIndex == 0,
                onClick = { selectedTabIndex = 0 },
                text = { Text("Ditto SDK") },
            )
            Tab(
                selected = selectedTabIndex == 1,
                onClick = { selectedTabIndex = 1 },
                text = { Text("App Logs") },
            )
        }

        // ── SDK-only filters ─────────────────────────────────────────────────
        AnimatedVisibility(visible = selectedTabIndex == 0) {
            Column {
                // Level filter chips
                FlowRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    ALL_LEVELS.forEach { level ->
                        FilterChip(
                            selected = level in selectedLevels,
                            onClick = {
                                selectedLevels = if (level in selectedLevels) {
                                    selectedLevels - level
                                } else {
                                    selectedLevels + level
                                }
                            },
                            label = { Text(level.shortName, style = androidx.compose.material3.MaterialTheme.typography.labelSmall) },
                        )
                    }
                }

                // Component filter
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ExposedDropdownMenuBox(
                        expanded = componentDropdownExpanded,
                        onExpandedChange = { componentDropdownExpanded = it },
                        modifier = Modifier.width(160.dp),
                    ) {
                        OutlinedTextField(
                            value = selectedComponent.displayName,
                            onValueChange = {},
                            readOnly = true,
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = componentDropdownExpanded) },
                            label = { Text("Component") },
                            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                            textStyle = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                            singleLine = true,
                        )
                        ExposedDropdownMenu(
                            expanded = componentDropdownExpanded,
                            onDismissRequest = { componentDropdownExpanded = false },
                        ) {
                            LogComponent.entries.forEach { comp ->
                                DropdownMenuItem(
                                    text = { Text(comp.displayName) },
                                    onClick = {
                                        selectedComponent = comp
                                        componentDropdownExpanded = false
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }

        // ── Search field ─────────────────────────────────────────────────────
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text("Search logs…") },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            trailingIcon = if (searchQuery.isNotEmpty()) {
                { IconButton(onClick = { searchQuery = "" }) { Icon(Icons.Outlined.Clear, contentDescription = "Clear search") } }
            } else null,
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            textStyle = androidx.compose.material3.MaterialTheme.typography.bodySmall,
        )

        if (isLoading) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        HorizontalDivider()

        // ── Log list ─────────────────────────────────────────────────────────
        Box(modifier = Modifier.weight(1f)) {
            if (displayEntries.isEmpty() && !isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "No log entries",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    items(displayEntries, key = { it.id.toString() }) { entry ->
                        LogEntryRow(entry = entry)
                        HorizontalDivider(thickness = 0.5.dp)
                    }
                }
            }

            // "↓ N new entries" FAB when paused
            if (!isAtBottom && pendingCount > 0) {
                FloatingActionButton(
                    onClick = {
                        scope.launch {
                            listState.scrollToItem(Int.MAX_VALUE)
                            captureService.resetPendingCount()
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 8.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null)
                        Text("$pendingCount new")
                    }
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────────
        HorizontalDivider()
        AnimatedVisibility(visible = footerExpanded) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                val totalCount = when (selectedTabIndex) {
                    0 -> (historicalEntries + liveEntries).size
                    else -> appEntries.size
                }
                Text(
                    text = "${displayEntries.size} of $totalCount entries",
                    style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = {
                    when (selectedTabIndex) {
                        0 -> {
                            captureService.clearLive()
                            captureService.clearHistorical()
                        }
                        else -> captureService.clearApp()
                    }
                }) {
                    Text("Clear")
                }
                IconButton(onClick = { footerExpanded = false }, modifier = Modifier.size(24.dp)) {
                    Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = "Collapse footer")
                }
            }
        }
        AnimatedVisibility(visible = !footerExpanded) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                IconButton(onClick = { footerExpanded = true }, modifier = Modifier.size(24.dp)) {
                    Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = "Expand footer")
                }
            }
        }
        Spacer(modifier = Modifier.height(4.dp))
    }
}

