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
import androidx.compose.material.icons.outlined.Tune
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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import androidx.compose.runtime.snapshotFlow
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.logging.LogPatternEngine
import com.costoda.dittoedgestudio.data.logging.LogPatternStore
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.displayName
import com.costoda.dittoedgestudio.domain.model.shortName
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.sample
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.compose.koinInject

private val ALL_LEVELS = DittoLogLevel.entries.toList()

/** Pattern re-scan rate limit (the capture service already batches at 500 ms). */
private const val PATTERN_SCAN_INTERVAL_MS = 1_000L

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
    val liveEntries by captureService.liveEntries.collectAsStateWithLifecycle()
    val historicalEntries by captureService.historicalEntries.collectAsStateWithLifecycle()
    val appEntries by captureService.appEntries.collectAsStateWithLifecycle()
    val transportConditionEntries by captureService.transportConditionEntries.collectAsStateWithLifecycle()
    val connectionRequestEntries by captureService.connectionRequestEntries.collectAsStateWithLifecycle()
    val isLoading by captureService.isLoading.collectAsStateWithLifecycle()
    val pendingCount by captureService.pendingNewEntriesCount.collectAsStateWithLifecycle()
    val bufferNearlyFull by captureService.bufferNearlyFull.collectAsStateWithLifecycle()
    val entriesDropped by captureService.entriesDropped.collectAsStateWithLifecycle()

    // ── Filter state ────────────────────────────────────────────────────────
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    var selectedLevels by remember { mutableStateOf(ALL_LEVELS.toSet()) }
    var selectedComponent by remember { mutableStateOf(LogComponent.ALL) }
    var searchQuery by remember { mutableStateOf("") }
    // Date-range filter (SwiftUI parity): full-day bounds for the chosen dates.
    var dateFilterEnabled by remember { mutableStateOf(false) }
    var dateRangeStartMillis by remember { mutableStateOf<Long?>(null) }
    var dateRangeEndMillis by remember { mutableStateOf<Long?>(null) }
    var sdkLogLevel by remember { mutableStateOf(DittoLogger.minimumLogLevel) }
    var footerExpanded by remember { mutableStateOf(true) }
    var exportError by remember { mutableStateOf<String?>(null) }

    // ── Export (save the active tab's buffer to a user-chosen file) ─────────
    // SwiftUI exports raw log files via a folder picker; Android uses SAF's
    // CreateDocument. Exports the full in-memory buffer, not just the visible
    // 200 rows.
    val exportLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/plain"),
    ) { uri ->
        if (uri != null) {
            val entries = when (selectedTabIndex) {
                0 -> historicalEntries + liveEntries
                1 -> appEntries
                2 -> transportConditionEntries
                else -> connectionRequestEntries
            }
            scope.launch {
                exportError = exportLogEntries(context, uri, entries)
            }
        }
    }
    var sdkLevelDropdownExpanded by remember { mutableStateOf(false) }
    var componentDropdownExpanded by remember { mutableStateOf(false) }

    // ── Log pattern analysis (VS Code extension log-analyzer parity) ────────
    val patternStore: LogPatternStore = koinInject()
    val patterns by patternStore.patterns.collectAsStateWithLifecycle()
    var showPatternManager by remember { mutableStateOf(false) }
    val patternEngine = remember(patterns) { LogPatternEngine(patterns) }
    var problems by remember { mutableStateOf<List<LogPatternEngine.Match>>(emptyList()) }

    // Scan the active tab's buffer on change, sampled to at most one pass per
    // second and capped at LogPatternEngine.MAX_SCAN_ENTRIES so hot logs can't
    // jank the UI. Runs on the Default dispatcher.
    LaunchedEffect(patternEngine, selectedTabIndex) {
        snapshotFlow {
            // Read the collected State delegates — NOT StateFlow.value, which is
            // invisible to snapshot tracking and would leave the scan stale.
            when (selectedTabIndex) {
                0 -> liveEntries.size to historicalEntries.size
                1 -> appEntries.size
                2 -> transportConditionEntries.size
                else -> connectionRequestEntries.size
            }
        }.sample(PATTERN_SCAN_INTERVAL_MS).collectLatest {
            val entries = when (selectedTabIndex) {
                0 -> historicalEntries + liveEntries
                1 -> appEntries
                2 -> transportConditionEntries
                else -> connectionRequestEntries
            }
            problems = withContext(Dispatchers.Default) { patternEngine.scanAll(entries) }
        }
    }

    // user_tag labels per entry, for row chips (parity with the webview's tag column).
    val userTagsById = remember(problems) {
        problems
            .groupBy({ it.entry.id }, { it.pattern.userTag })
            .mapValues { (_, tags) -> tags.filterNotNull().distinct().sorted() }
            .filterValues { it.isNotEmpty() }
    }

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
                1 -> appEntries
                2 -> transportConditionEntries
                else -> connectionRequestEntries
            }
            source
                .filter { entry ->
                    entry.level in selectedLevels &&
                        (selectedTabIndex != 0 || selectedComponent == LogComponent.ALL ||
                            entry.component == selectedComponent) &&
                        (searchQuery.isBlank() ||
                            entry.message.contains(searchQuery, ignoreCase = true) ||
                            userTagsById[entry.id]?.any { it.contains(searchQuery, ignoreCase = true) } == true) &&
                        (!dateFilterEnabled || run {
                            val time = entry.timestamp.time
                            val afterStart = dateRangeStartMillis?.let { time >= it } ?: true
                            val beforeEnd = dateRangeEndMillis?.let { time <= it } ?: true
                            afterStart && beforeEnd
                        })
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
                color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
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
                Icon(
                    Icons.Outlined.Refresh,
                    contentDescription = "Refresh logs",
                    tint = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = { showPatternManager = true }) {
                Icon(
                    Icons.Outlined.Tune,
                    contentDescription = "Manage log patterns",
                    tint = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                )
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
                        color = androidx.compose.ui.graphics.Color(0xFFFF9500),
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

        // ── Export error banner ─────────────────────────────────────────────
        AnimatedVisibility(visible = exportError != null) {
            Surface(
                color = androidx.compose.material3.MaterialTheme.colorScheme.errorContainer,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                shape = androidx.compose.material3.MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier.padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = exportError ?: "",
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { exportError = null }) { Text("OK") }
                }
            }
        }

        // ── Source switcher ───────────────────────────────────────────────────
        DittoConnectedButtonGroup(
            options = listOf("Ditto SDK", "App Logs", "Transports", "Connections"),
            selectedIndex = selectedTabIndex,
            onSelect = { selectedTabIndex = it },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

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

        // ── Pattern problems strip (collapsible; hidden when nothing matched) ──
        LogProblemsSection(
            problems = problems,
            onJumpToEntry = { entry -> searchQuery = entry.message },
            modifier = Modifier.fillMaxWidth(),
        )

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

        // ── Date-range filter row ───────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Date range",
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(4.dp))
            androidx.compose.material3.Switch(
                checked = dateFilterEnabled,
                onCheckedChange = {
                    dateFilterEnabled = it
                    if (it && dateRangeStartMillis == null && dateRangeEndMillis == null) {
                        // Default: today, full-day bounds (SwiftUI filters default parity).
                        val cal = java.util.Calendar.getInstance()
                        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
                        cal.set(java.util.Calendar.MINUTE, 0)
                        cal.set(java.util.Calendar.SECOND, 0)
                        cal.set(java.util.Calendar.MILLISECOND, 0)
                        dateRangeStartMillis = cal.timeInMillis
                        cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                        dateRangeEndMillis = cal.timeInMillis - 1
                    }
                },
                modifier = Modifier.height(28.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
            androidx.compose.animation.AnimatedVisibility(visible = dateFilterEnabled) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val fmt = java.text.SimpleDateFormat("MMM d, yyyy", java.util.Locale.US)
                    TextButton(onClick = {
                        showDatePicker(context, dateRangeStartMillis, isEnd = false) { dateRangeStartMillis = it }
                    }) {
                        Text(
                            text = dateRangeStartMillis?.let { fmt.format(java.util.Date(it)) } ?: "Start",
                            style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        )
                    }
                    Text(
                        text = "→",
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = {
                        showDatePicker(context, dateRangeEndMillis, isEnd = true) { dateRangeEndMillis = it }
                    }) {
                        Text(
                            text = dateRangeEndMillis?.let { fmt.format(java.util.Date(it)) } ?: "End",
                            style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }

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
                        LogEntryRow(
                            entry = entry,
                            userTags = userTagsById[entry.id].orEmpty(),
                        )
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
                    1 -> appEntries.size
                    2 -> transportConditionEntries.size
                    else -> connectionRequestEntries.size
                }
                Text(
                    text = "${displayEntries.size} of $totalCount entries",
                    style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = {
                    val tabName = when (selectedTabIndex) {
                        0 -> "ditto-sdk"
                        1 -> "app"
                        2 -> "transport-conditions"
                        else -> "connection-requests"
                    }
                    exportLauncher.launch("edge-studio-logs-$tabName.txt")
                }) {
                    Text("Export")
                }
                TextButton(onClick = {
                    when (selectedTabIndex) {
                        0 -> {
                            captureService.clearLive()
                            captureService.clearHistorical()
                        }
                        1 -> captureService.clearApp()
                        2 -> captureService.clearTransportConditions()
                        else -> captureService.clearConnectionRequests()
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

    if (showPatternManager) {
        LogPatternManagerSheet(
            store = patternStore,
            onDismiss = { showPatternManager = false },
        )
    }
}

    /** Non-null on failure (message for the banner). */
    private fun exportLogEntries(
        context: android.content.Context,
        uri: android.net.Uri,
        entries: List<LogEntry>,
    ): String? = try {
        val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", java.util.Locale.US)
        context.contentResolver.openOutputStream(uri)?.bufferedWriter()?.use { writer ->
            entries.forEach { entry ->
                writer.append(
                    iso.format(entry.timestamp),
                ).append("  ").append(entry.level.name.uppercase().padEnd(7))
                    .append(" [").append(entry.component.displayName).append("]  ")
                    .append(entry.message.replace('\n', ' '))
                writer.newLine()
            }
        } ?: return "Could not open the destination file"
        null
    } catch (e: Exception) {
        "Export failed: ${e.message}"
    }

/** Date picker for the log date-range filter; start picks normalize to the
 *  start of the day, end picks to the end of the day (local time). */
private fun showDatePicker(
    context: android.content.Context,
    initialMillis: Long?,
    isEnd: Boolean,
    onPicked: (Long) -> Unit,
) {
    val cal = java.util.Calendar.getInstance()
    initialMillis?.let { cal.timeInMillis = it }
    android.app.DatePickerDialog(
        context,
        { _, year, month, day ->
            val picked = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.YEAR, year)
                set(java.util.Calendar.MONTH, month)
                set(java.util.Calendar.DAY_OF_MONTH, day)
                if (isEnd) {
                    set(java.util.Calendar.HOUR_OF_DAY, 23)
                    set(java.util.Calendar.MINUTE, 59)
                    set(java.util.Calendar.SECOND, 59)
                    set(java.util.Calendar.MILLISECOND, 999)
                } else {
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }
            }
            onPicked(picked.timeInMillis)
        },
        cal.get(java.util.Calendar.YEAR),
        cal.get(java.util.Calendar.MONTH),
        cal.get(java.util.Calendar.DAY_OF_MONTH),
    ).show()
}

