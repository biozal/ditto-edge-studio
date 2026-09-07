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
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.testTag
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.logging.LogAnalytics
import com.costoda.dittoedgestudio.data.logging.LogEntryContext
import com.costoda.dittoedgestudio.data.logging.LogPatternEngine
import com.costoda.dittoedgestudio.data.logging.LogPatternStore
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
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
import java.util.UUID
import org.koin.compose.koinInject
import com.costoda.dittoedgestudio.data.logging.sdkLogLevelConfigValue
import com.costoda.dittoedgestudio.data.logging.sdkLogLevelFromConfigValue

private val ALL_LEVELS = DittoLogLevel.entries.toList()

/** Pattern re-scan rate limit (the capture service already batches at 500 ms). */
private const val PATTERN_SCAN_INTERVAL_MS = 1_000L

/**
 * One analysis pass, produced entirely off the composition thread and applied to
 * state in a single step, so the tag index, the match list and the analytics can
 * never be observed half-updated against each other.
 */
private data class LogScanPass(
    val searchTags: Map<UUID, List<String>>,
    val matches: List<LogPatternEngine.Match>,
    val analytics: LogAnalytics,
)

/**
 * @param activeDatabase the database config this studio session opened, or null
 *   when the caller has none. Supplies the persisted SDK log level and is the
 *   record the level is written back to — see [sdkLogLevelConfigValue].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LoggingScreen(
    captureService: DittoLogCaptureService,
    modifier: Modifier = Modifier,
    activeDatabase: DittoDatabase? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    // ── StateFlow collectors ────────────────────────────────────────────────
    // Historical + live, merged chronologically off the composition thread by the
    // capture service. Collecting the two source flows separately here would put
    // that merge back on the composition thread — see DittoLogCaptureService.sdkEntries.
    val sdkEntries by captureService.sdkEntries.collectAsStateWithLifecycle()
    val appEntries by captureService.appEntries.collectAsStateWithLifecycle()
    val transportConditionEntries by captureService.transportConditionEntries.collectAsStateWithLifecycle()
    val connectionRequestEntries by captureService.connectionRequestEntries.collectAsStateWithLifecycle()
    val isLoading by captureService.isLoading.collectAsStateWithLifecycle()
    val pendingCount by captureService.pendingNewEntriesCount.collectAsStateWithLifecycle()
    val bufferNearlyFull by captureService.bufferNearlyFull.collectAsStateWithLifecycle()
    val entriesDropped by captureService.entriesDropped.collectAsStateWithLifecycle()

    // Monotonic ingest counter. The rescan below used to be keyed on the live
    // buffer's *size*, which is pinned the moment the buffer reaches its cap —
    // entries then roll over underneath a constant count, `snapshotFlow` is
    // distinct-until-changed, and the scan, the analytics, both histograms and
    // every badge freeze permanently on exactly the high-volume captures that
    // need them most. Confirmed by unit test, not inferred.
    val ingestSequence by captureService.ingestSequence.collectAsStateWithLifecycle()

    // ── Filter state ────────────────────────────────────────────────────────
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    var filterTab by remember { mutableStateOf(LogFilterTab.ALL) }
    var selectedLevels by remember { mutableStateOf(ALL_LEVELS.toSet()) }
    var selectedComponent by remember { mutableStateOf(LogComponent.ALL) }
    var searchQuery by remember { mutableStateOf("") }
    // Date-range filter (SwiftUI parity): full-day bounds for the chosen dates.
    var dateFilterEnabled by remember { mutableStateOf(false) }
    var dateRangeStartMillis by remember { mutableStateOf<Long?>(null) }
    var dateRangeEndMillis by remember { mutableStateOf<Long?>(null) }
    // ── SDK log level (persisted, SwiftUI parity) ───────────────────────────
    //
    // SwiftUI writes the level chosen here onto the database config
    // (`LoggingDetailView` → `DittoManager.changeDittoLogLevel`), so it survives
    // a relaunch. The Android equivalent is `DittoDatabase.logLevel` — the same
    // field the Database Editor's Log Level dropdown writes — which this screen
    // previously ignored, setting only the in-process
    // `DittoLogger.minimumLogLevel` and losing the choice on the next launch.
    //
    // The stored value is also applied to the live SDK on first composition:
    // `DittoManager.hydrate` currently forces Info, so without this the config
    // would be written and never read back.
    val databaseRepository: DatabaseRepository = koinInject()
    var sdkLogLevel by remember(activeDatabase?.id) {
        mutableStateOf(
            sdkLogLevelFromConfigValue(activeDatabase?.logLevel) ?: DittoLogger.minimumLogLevel,
        )
    }
    LaunchedEffect(activeDatabase?.id) {
        val stored = sdkLogLevelFromConfigValue(activeDatabase?.logLevel) ?: return@LaunchedEffect
        if (DittoLogger.minimumLogLevel != stored) {
            runCatching { DittoLogger.minimumLogLevel = stored }
        }
    }
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
                0 -> sdkEntries
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
    var analytics by remember { mutableStateOf<LogAnalytics?>(null) }

    // ── Explicit Pause / Resume ─────────────────────────────────────────────
    //
    // Pause freezes the *source snapshot* only. Ingestion keeps running into
    // the capture buffers (which are capped, so nothing is lost that would not
    // have been lost anyway), and every filter the user owns — search, level
    // chips, component, date range, the filter tabs — keeps working over the
    // frozen snapshot. SwiftUI's pause also disabled those controls, which is a
    // confirmed defect: a paused view the user cannot interrogate is strictly
    // worse than no pause at all.
    var isPaused by remember { mutableStateOf(false) }
    var frozenFull by remember { mutableStateOf<List<LogEntry>?>(null) }

    // Row context drawer: one row open at a time, owned here because the slice
    // has to come from the unfiltered buffer, which a row cannot reach.
    var expandedEntryId by remember { mutableStateOf<UUID?>(null) }

    // ── Analysis window ─────────────────────────────────────────────────────
    //
    // Badges, histograms, the problems strip and the filtered list are all
    // computed over exactly one population — the spec's requirement (§2
    // "Analysis window"), and the fix for the SwiftUI defect where badges were
    // measured over the scan window while the list filtered the whole buffer, so
    // above 5,000 entries the badges silently under-reported.
    //
    // That population is now the newest MAX_SCAN_ENTRIES of the entries matching
    // the search / date / component filters across the WHOLE buffer, not the
    // newest MAX_SCAN_ENTRIES of the buffer full stop. Windowing first made the
    // search box blind to anything older than the newest 5,000 — see
    // [LogPopulation] for the full argument.
    val liveFull by remember {
        derivedStateOf {
            when (selectedTabIndex) {
                // SDK tab: historical + live as one chronological stream. The
                // merge itself happens on a background dispatcher in the capture
                // service, so this branch is a plain read.
                0 -> sdkEntries
                1 -> appEntries
                2 -> transportConditionEntries
                else -> connectionRequestEntries
            }
        }
    }

    // Take (or drop) the frozen snapshot. Reading `liveFull` inside the effect
    // body is a plain value read, not a tracked one, which is exactly the freeze
    // we want. Re-keyed on the source tab so switching sources while paused
    // snapshots that source rather than showing the previous one's buffer.
    LaunchedEffect(isPaused, selectedTabIndex) {
        frozenFull = if (isPaused) liveFull else null
    }

    /**
     * Whole active buffer (frozen or live).
     *
     * The population filter, the context slices and connection-session pairing
     * all run over this rather than over the window: search must be able to
     * reach an old line, context must be able to show the neighbours the filter
     * hides, and a `started` line that has aged out of the window could
     * otherwise never be paired with its `ended`.
     */
    val sourceFull = frozenFull ?: liveFull

    /**
     * user_tag labels per entry from a scan of the **unfiltered** window — the
     * only thing this map feeds is the search predicate.
     *
     * It must not come from the population's own scan: the population's search
     * matches tags, so deriving the tags from it would make the predicate depend
     * on its own output, and switching from one tag query to another would find
     * nothing.
     */
    var searchTagsById by remember { mutableStateOf<Map<UUID, List<String>>>(emptyMap()) }

    // derivedStateOf, not remember(keys): a plain `remember` result would be
    // captured by value inside the derived states below, which would then never
    // see a filter change.
    val populationFilter by remember {
        derivedStateOf {
            LogPopulationFilter(
                searchQuery = searchQuery,
                component = selectedComponent,
                // Only the Ditto SDK source carries components.
                componentApplies = selectedTabIndex == 0,
                dateFilterEnabled = dateFilterEnabled,
                dateRangeStartMillis = dateRangeStartMillis,
                dateRangeEndMillis = dateRangeEndMillis,
            )
        }
    }

    /** The analysis population: filtered over the whole buffer, then windowed. */
    val population by remember {
        derivedStateOf {
            logAnalysisPopulation(
                full = frozenFull ?: liveFull,
                filter = populationFilter,
                searchTagsById = searchTagsById,
                maxWindow = LogPatternEngine.MAX_SCAN_ENTRIES,
            )
        }
    }

    // Scan the population on change, sampled to at most one pass per second so
    // hot logs can't jank the UI. Both the pattern scan and the analytics
    // aggregation run on the Default dispatcher, over the same entry list — so
    // the badges and the list can never disagree about their population.
    LaunchedEffect(patternEngine) {
        snapshotFlow {
            // Read the collected State delegates — NOT StateFlow.value, which is
            // invisible to snapshot tracking and would leave the scan stale.
            // While frozen, neither `liveFull` nor `ingestSequence` is read, so
            // incoming entries do not trigger pointless rescans of an unchanged
            // list; the frozen snapshot is a `toList()` copy taken once, so its
            // size is a sufficient (and constant) key for the whole pause.
            //
            // Live, the key is the monotonic ingest counter rather than the
            // buffer size — see [ingestSequence]. `.sample` below is what bounds
            // the cost: the counter bumps on every publish, but at most one scan
            // per PATTERN_SCAN_INTERVAL_MS survives it.
            //
            // The population filter is part of the key too: changing the search
            // or the date range changes the population, and therefore the badges.
            val frozen = frozenFull
            listOf(
                selectedTabIndex,
                frozen != null,
                if (frozen != null) frozen.size.toLong() else ingestSequence,
                populationFilter,
                // The tag index feeds the search predicate, so a tag search
                // changes the population when the index lands. Without this the
                // first pass would count an empty population while the list
                // already showed the tagged rows. Read only while a search is
                // live, so the steady state does not compare maps. Converges in
                // one extra pass: pass 1 always scans the same unfiltered
                // window, so the index it produces is stable.
                if (populationFilter.searchQuery.isBlank()) emptyMap() else searchTagsById,
            )
        }.sample(PATTERN_SCAN_INTERVAL_MS).collectLatest {
            val full = frozenFull ?: liveFull
            val currentPopulation = population
            val filterActive = populationFilter.isActive
            // With no filter the population IS the unfiltered window, so reuse
            // it rather than re-slicing `full`: the two are read at slightly
            // different snapshot times, and taking the same list keeps the
            // matches, the badges and the rows exactly in step in the common
            // case. When a filter is active the window only feeds the tag index,
            // where a one-batch skew is harmless.
            val window = if (!filterActive) {
                currentPopulation.entries
            } else if (full.size > LogPatternEngine.MAX_SCAN_ENTRIES) {
                full.takeLast(LogPatternEngine.MAX_SCAN_ENTRIES)
            } else {
                full
            }
            val pass = withContext(Dispatchers.Default) {
                // Pass 1 — the unfiltered window, which is the only honest
                // source for the tag index the search predicate reads.
                val windowMatches = patternEngine.scanAll(window)
                val tags = windowMatches
                    .groupBy({ it.entry.id }, { it.pattern.userTag })
                    .mapValues { (_, values) -> values.filterNotNull().distinct().sorted() }
                    .filterValues { it.isNotEmpty() }

                // Pass 2 — the population, when a filter has made it something
                // other than the plain tail of the buffer. Skipped otherwise, so
                // the steady state still costs exactly one scan.
                val populationMatches = if (filterActive) {
                    patternEngine.scanAll(currentPopulation.entries)
                } else {
                    windowMatches
                }
                LogScanPass(
                    searchTags = tags,
                    matches = populationMatches,
                    analytics = LogAnalytics.compute(currentPopulation.entries, populationMatches, full),
                )
            }
            searchTagsById = pass.searchTags
            problems = pass.matches
            analytics = pass.analytics
        }
    }

    // user_tag labels per entry, for row chips (parity with the webview's tag
    // column). Sourced from the population's scan so a row surfaced by a search
    // from outside the window still gets its chips. derivedStateOf rather than
    // remember(problems) so that reads from inside other derived states stay
    // live instead of capturing a stale map.
    val userTagsById by remember {
        derivedStateOf {
            problems
                .groupBy({ it.entry.id }, { it.pattern.userTag })
                .mapValues { (_, tags) -> tags.filterNotNull().distinct().sorted() }
                .filterValues { it.isNotEmpty() }
        }
    }

    // Distinct entry ids behind the Problems and Critical tabs. These are the
    // same sets the badges count, so a badge can never promise a row the list
    // will not render.
    val problemIds by remember {
        derivedStateOf { problems.mapTo(mutableSetOf()) { it.entry.id } as Set<UUID> }
    }
    val criticalIds by remember {
        derivedStateOf {
            problems.filter { it.pattern.severity >= 5 }.mapTo(mutableSetOf()) { it.entry.id } as Set<UUID>
        }
    }

    // ── Auto-pause when user scrolls away from bottom ───────────────────────
    val isAtBottom by remember { derivedStateOf { !listState.canScrollForward } }
    LaunchedEffect(isAtBottom) {
        captureService.isLivePaused = !isAtBottom
        if (isAtBottom) captureService.resetPendingCount()
    }

    // ── Filtered display list ────────────────────────────────────────────────
    //
    // Search / date / component were applied when the population was built, so
    // all that is left here is the filter tab and the level chips — the two that
    // must NOT feed the badges, because a badge answers "how many Errors are
    // there?" and would otherwise only ever be able to answer "all of them".
    val displayEntries by remember {
        derivedStateOf {
            logDisplayEntries(
                population = population.entries,
                filterTab = filterTab,
                problemIds = problemIds,
                criticalIds = criticalIds,
                selectedLevels = selectedLevels,
                maxDisplayed = DittoLogCaptureService.MAX_DISPLAYED_ENTRIES,
            )
        }
    }

    // ±5 neighbours of the expanded row, sliced from the UNFILTERED buffer.
    // Slicing the filtered list instead would make the feature useless:
    // expanding an error on the Errors tab would show five other errors rather
    // than the lines that explain it. The whole buffer rather than the window,
    // so a row the search surfaced from outside the window still has neighbours.
    val expandedContext = remember(expandedEntryId, sourceFull) {
        expandedEntryId?.let { LogEntryContext.around(it, sourceFull) }
    }
    // Resolver for `Copy With Context` on any row, expanded or not. A lambda
    // rather than a per-row slice: resolving eagerly would be a linear scan of
    // the buffer for every visible row.
    //
    // Keyed on nothing, with the buffer read through rememberUpdatedState: a
    // `remember(sourceFull)` lambda would get a new identity on every buffer
    // publish (twice a second under load) and recompose all 200 visible rows
    // for a value none of them read until the menu is opened.
    val contextBuffer by rememberUpdatedState(sourceFull)
    val resolveContext = remember {
        { entry: LogEntry -> LogEntryContext.around(entry.id, contextBuffer) }
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
                                // Persist alongside the live change, so the
                                // choice survives a relaunch (SwiftUI parity).
                                // Best-effort: a failed write must not take the
                                // Logs screen down, and the level the user just
                                // picked is already in effect either way.
                                activeDatabase?.let { database ->
                                    scope.launch {
                                        runCatching {
                                            databaseRepository.save(
                                                database.copy(logLevel = sdkLogLevelConfigValue(level)),
                                            )
                                        }.onFailure { error ->
                                            exportError =
                                                "Log level applied but not saved: ${error.message}"
                                        }
                                    }
                                }
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(4.dp))
            IconButton(
                onClick = { isPaused = !isPaused },
                modifier = Modifier.testTag("LogPauseToggle"),
            ) {
                Icon(
                    imageVector = if (isPaused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                    contentDescription = if (isPaused) "Resume log display" else "Pause log display",
                    tint = if (isPaused) {
                        androidx.compose.material3.MaterialTheme.colorScheme.primary
                    } else {
                        androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
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

        // ── Paused banner ─────────────────────────────────────────────────────
        AnimatedVisibility(visible = isPaused) {
            Surface(
                color = androidx.compose.material3.MaterialTheme.colorScheme.primaryContainer,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                shape = androidx.compose.material3.MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier.padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Outlined.Pause,
                        contentDescription = null,
                        tint = androidx.compose.material3.MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        text = "Paused — display frozen at ${sourceFull.size} entries. " +
                            "Capture continues; filtering and search still work.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { isPaused = false }) { Text("Resume") }
                }
            }
        }

        // ── Source switcher ───────────────────────────────────────────────────
        DittoConnectedButtonGroup(
            options = listOf("Ditto SDK", "App Logs", "Transports", "Connections"),
            selectedIndex = selectedTabIndex,
            onSelect = {
                selectedTabIndex = it
                // Entry ids are per-buffer; keeping the expansion across a
                // source switch would open a row that is not on screen.
                expandedEntryId = null
            },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

        // ── Analyzer filter tabs (All / Critical / Errors / Warnings / Problems) ──
        LogFilterTabs(
            selected = filterTab,
            counts = analytics?.counts,
            onSelect = { filterTab = it },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
        )

        // ── Histograms ────────────────────────────────────────────────────────
        LogAnalyticsSection(analytics = analytics)

        // ── Level filter ─────────────────────────────────────────────────────
        //
        // Rendered and applied on EVERY log source, as SwiftUI does. Restricting
        // them to Ditto SDK left App Logs / Transports / Connections with no
        // level control at all — those sources carry INFO, WARNING and ERROR
        // entries just as the SDK source does.
        //
        // They stay suppressed whenever a non-All tab owns the level dimension;
        // the notice below says which case applies, honestly — the Critical and
        // Problems tabs constrain severity, not level.
        AnimatedVisibility(visible = filterTab.suppressesLevelChips) {
            filterTab.levelChipNotice?.let { notice ->
                Text(
                    text = notice,
                    style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }
        }
        AnimatedVisibility(visible = !filterTab.suppressesLevelChips) {
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
            }
        }

        // Component filter — available on every filter tab: it selects a
        // subsystem, not a level, so no tab overrides it.
        AnimatedVisibility(visible = selectedTabIndex == 0) {
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
                        val rowExpanded = expandedEntryId == entry.id
                        LogEntryRow(
                            entry = entry,
                            userTags = userTagsById[entry.id].orEmpty(),
                            expanded = rowExpanded,
                            onToggleExpanded = {
                                expandedEntryId = if (rowExpanded) null else entry.id
                            },
                            context = if (rowExpanded) expandedContext else null,
                            resolveContext = resolveContext,
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
                val bufferedCount = when (selectedTabIndex) {
                    0 -> sdkEntries.size
                    1 -> appEntries.size
                    2 -> transportConditionEntries.size
                    else -> connectionRequestEntries.size
                }
                // Says which population the counts above were measured over.
                // Badges and histograms all cover `population.entries`, so the
                // footer names that set and reports what it excluded — both the
                // buffer beyond the analysis window and, when a filter is
                // active, the matches that did not fit it.
                val windowNote = when {
                    population.isWindowed ->
                        " (newest ${population.entries.size} of ${population.matchedCount} matching, " +
                            "$bufferedCount buffered)"
                    bufferedCount > population.entries.size ->
                        " (of $bufferedCount buffered)"
                    else -> ""
                }
                Text(
                    text = "${displayEntries.size} of ${population.entries.size} entries$windowNote",
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
                    // A frozen snapshot would resurrect the cleared entries, and
                    // the expanded id would point at a row that no longer exists.
                    isPaused = false
                    frozenFull = null
                    expandedEntryId = null
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

