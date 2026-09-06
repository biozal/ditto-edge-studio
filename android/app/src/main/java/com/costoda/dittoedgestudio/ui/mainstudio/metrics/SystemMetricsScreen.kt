package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.Clear
import androidx.compose.material.icons.outlined.DragHandle
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.SystemMetricKind
import com.costoda.dittoedgestudio.domain.model.SystemMetricSample
import com.costoda.dittoedgestudio.domain.model.SystemMetricSeriesRef
import com.costoda.dittoedgestudio.domain.model.SystemMetricsPinOrdering
import com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot
import com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus
import com.costoda.dittoedgestudio.domain.model.seriesId
import com.costoda.dittoedgestudio.domain.model.toSeriesRef
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private enum class NamespaceFilter(val label: String, val prefixes: List<String>?) {
    ALL("All", null),
    NETWORK("Network", listOf("ditto.network.")),
    STORE("Store", listOf("ditto.backend.")),
    SYNC("Sync", listOf("ditto.sync.", "ditto.replication.")),
    OTHER("Other", listOf()),
}

private fun matchesFilter(sample: SystemMetricSample, filter: NamespaceFilter): Boolean = when (filter) {
    NamespaceFilter.ALL -> true
    NamespaceFilter.OTHER -> NamespaceFilter.entries
        .filter { it.prefixes != null }
        .none { other -> other.prefixes!!.any { sample.key.startsWith(it) } }
    else -> filter.prefixes!!.any { sample.key.startsWith(it) }
}

/**
 * Case-insensitive substring over the metric key AND its label keys and values,
 * so `ble` finds the `transport=ble` series and `dsoq` every dsoq metric. A blank
 * query matches everything.
 */
private fun matchesQuery(sample: SystemMetricSample, query: String): Boolean {
    val needle = query.trim().lowercase(Locale.US)
    if (needle.isEmpty()) return true
    if (sample.key.lowercase(Locale.US).contains(needle)) return true
    return sample.labels.any { (k, v) ->
        k.lowercase(Locale.US).contains(needle) || v.lowercase(Locale.US).contains(needle)
    }
}

internal fun formatMetricValue(value: Double): String {
    val longValue = value.toLong()
    return when {
        value == longValue.toDouble() -> "%,d".format(Locale.US, longValue)
        value < 10 -> "%.2f".format(Locale.US, value)
        else -> "%.1f".format(Locale.US, value)
    }
}

/** Durations scale to µs / ms / s; everything else prints its raw unit. */
private fun formatScaled(value: Double, unit: String): String = when {
    unit != "seconds" -> formatMetricValue(value) + if (unit.isNotBlank()) " $unit" else ""
    value < 0.001 -> "%.0f µs".format(Locale.US, value * 1_000_000)
    value < 1 -> "%.1f ms".format(Locale.US, value * 1000)
    else -> "%.2f s".format(Locale.US, value)
}

/** Histograms accumulate a COUNT of observations, so their headline is a plain
 *  number regardless of the observed values' unit. */
private fun headlineValue(sample: SystemMetricSample): String =
    if (sample.kind == SystemMetricKind.HISTOGRAM) {
        formatMetricValue(sample.sinceConnect)
    } else {
        formatScaled(sample.sinceConnect, sample.unit)
    }

private fun deltaValue(sample: SystemMetricSample): String =
    if (sample.kind == SystemMetricKind.HISTOGRAM) {
        formatMetricValue(sample.periodDelta)
    } else {
        formatScaled(sample.periodDelta, sample.unit)
    }

private val timeFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("h:mm:ss a", Locale.US).withZone(ZoneId.systemDefault())

private fun Long.formatClockTime(): String =
    if (this <= 0L) "—" else timeFormatter.format(Instant.ofEpochMilli(this))

/**
 * The System Metrics rail section (SDK 5.1 `system:metrics`) — parity with the
 * SwiftUI `SystemMetricsDetailView` and the VS Code extension's System Metrics
 * panel.
 *
 * Owns the visibility-gated polling and the header; the dashboard itself lives in
 * the stateless [SystemMetricsPane] below so it can be exercised without a session.
 */
@Composable
fun SystemMetricsScreen(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    val snapshot by viewModel.systemMetrics.collectAsStateWithLifecycle()
    val pins by viewModel.systemMetricPins.collectAsStateWithLifecycle()

    // Visibility-gated polling: reads flush Ditto's registry, so polling while
    // nobody is looking would consume counters and show them to no one.
    DisposableEffect(viewModel) {
        viewModel.startSystemMetricsPolling()
        onDispose { viewModel.stopSystemMetricsPolling() }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 2.dp,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "System Metrics",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (snapshot.polledAtMs > 0) {
                    Text(
                        text = "Updated ${snapshot.polledAtMs.formatClockTime()}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { viewModel.refreshSystemMetricsNow() }) {
                    Icon(
                        Icons.Outlined.Refresh,
                        contentDescription = "Poll system:metrics now",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        HorizontalDivider()

        SystemMetricsPane(
            snapshot = snapshot,
            pins = pins,
            onPinsChange = viewModel::setSystemMetricPins,
        )
    }
}

/**
 * The `system:metrics` dashboard: a pinned accordion, a namespace segment filter
 * and search field, and one row per reported series with an info button for
 * details and a pin button that lifts the series into the accordion.
 *
 * Stateless with respect to pins — [onPinsChange] receives the complete
 * replacement list, so there is no merge to get wrong.
 */
@Composable
fun SystemMetricsPane(
    snapshot: SystemMetricsSnapshot,
    modifier: Modifier = Modifier,
    pins: List<SystemMetricSeriesRef> = emptyList(),
    onPinsChange: (List<SystemMetricSeriesRef>) -> Unit = {},
) {
    var filter by rememberSaveable { mutableStateOf(NamespaceFilter.ALL) }
    var query by rememberSaveable { mutableStateOf("") }
    var pinnedExpanded by rememberSaveable { mutableStateOf(true) }
    // Series with details open, by seriesId. Session-local, like the panel's.
    val expanded = remember { mutableStateOf(emptySet<String>()) }

    val samplesById = snapshot.samples.associateBy { it.seriesId }
    val pinnedIds = pins.map { it.id }.toSet()

    fun togglePin(ref: SystemMetricSeriesRef) {
        onPinsChange(if (ref.id in pinnedIds) pins.filterNot { it.id == ref.id } else pins + ref)
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (pins.isNotEmpty()) {
            item(key = "pinned") {
                PinnedSection(
                    pins = pins,
                    samplesById = samplesById,
                    isExpanded = pinnedExpanded,
                    onToggleExpanded = { pinnedExpanded = !pinnedExpanded },
                    onClear = { onPinsChange(emptyList()) },
                    expandedIds = expanded.value,
                    onToggleDetails = { id -> expanded.value = expanded.value.toggle(id) },
                    onTogglePin = ::togglePin,
                    onReorder = onPinsChange,
                )
            }
        }

        item(key = "filters") {
            FilterControls(
                filter = filter,
                onFilterChange = { filter = it },
                query = query,
                onQueryChange = { query = it },
            )
        }

        when (snapshot.status) {
            SystemMetricsStatus.SETTING_DISABLED -> item {
                StatusMessage(
                    "System metrics collection is off. Enable \"Collect system metrics\" in Settings — " +
                        "it takes effect the next time you open a database.",
                )
            }
            SystemMetricsStatus.EXPORTER_DISABLED -> item {
                StatusMessage(
                    "The SDK exporter wasn't enabled for this session. " +
                        "Close and re-open the database after enabling \"Collect system metrics\".",
                )
            }
            SystemMetricsStatus.NO_CONNECTION -> item {
                StatusMessage("No active database connection.")
            }
            SystemMetricsStatus.ERROR -> item {
                StatusMessage(
                    "system:metrics read failed: ${snapshot.errorMessage ?: "unknown error"}",
                    isError = true,
                )
            }
            SystemMetricsStatus.IDLE, SystemMetricsStatus.READY -> {
                item(key = "divergence") { DivergenceBanner(snapshot) }

                val filtered = snapshot.samples.filter {
                    matchesFilter(it, filter) && matchesQuery(it, query)
                }
                if (filtered.isEmpty()) {
                    item {
                        StatusMessage(
                            when {
                                snapshot.samples.isEmpty() ->
                                    "No metrics reported yet — they accumulate while this screen is visible."
                                query.isBlank() -> "No metrics in this namespace."
                                else -> "No metrics match \"${query.trim()}\"."
                            },
                        )
                    }
                } else {
                    items(filtered, key = { it.seriesId }) { sample ->
                        MetricRow(
                            sample = sample,
                            isPinned = sample.seriesId in pinnedIds,
                            isExpanded = sample.seriesId in expanded.value,
                            onToggleDetails = { expanded.value = expanded.value.toggle(sample.seriesId) },
                            onTogglePin = { togglePin(sample.toSeriesRef()) },
                        )
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }

                if (snapshot.sinceMs > 0) {
                    item(key = "footer") {
                        Text(
                            text = "Since ${snapshot.sinceMs.formatClockTime()} — " +
                                "updated ${snapshot.polledAtMs.formatClockTime()} · polled every 5s. " +
                                "Totals accumulate per-read deltas — reading system:metrics flushes " +
                                "Ditto's counters.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun Set<String>.toggle(id: String): Set<String> =
    if (id in this) this - id else this + id

@Composable
private fun FilterControls(
    filter: NamespaceFilter,
    onFilterChange: (NamespaceFilter) -> Unit,
    query: String,
    onQueryChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier.padding(bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Stacked rather than side-by-side (the SwiftUI/VS Code layout): with the
        // rail and inspector taking width, five segments plus an inline field
        // squeeze the segment labels into unreadable slivers.
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            NamespaceFilter.entries.forEachIndexed { index, ns ->
                SegmentedButton(
                    selected = filter == ns,
                    onClick = { onFilterChange(ns) },
                    shape = SegmentedButtonDefaults.itemShape(
                        index = index,
                        count = NamespaceFilter.entries.size,
                    ),
                    // Brand yellow in dark mode only — see `dittoToggleButtonColors`.
                    colors = if (isSystemInDarkTheme()) {
                        SegmentedButtonDefaults.colors(
                            activeContainerColor = SulfurYellow,
                            activeContentColor = Color.Black,
                            activeBorderColor = SulfurYellow,
                        )
                    } else {
                        SegmentedButtonDefaults.colors()
                    },
                ) {
                    Text(ns.label, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            singleLine = true,
            placeholder = { Text("Filter metrics…", style = MaterialTheme.typography.bodySmall) },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(Icons.Outlined.Clear, contentDescription = "Clear search")
                    }
                }
            },
            textStyle = MaterialTheme.typography.bodyMedium,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Filter metrics" },
        )
    }
}

/**
 * The pinned-series accordion. Renders whenever pins exist — even in a non-working
 * status — so the troubleshooting set is always reachable. A pinned series the
 * current snapshot doesn't report stays as a placeholder rather than vanishing, so
 * it can always be unpinned from here.
 *
 * Rows reorder by long-pressing the ☰ handle and dragging: the list re-sorts live
 * under the finger (rows swap as the drag crosses a neighbour's midpoint) and the
 * new order is persisted once, on release, rather than on every swap.
 */
@Composable
private fun PinnedSection(
    pins: List<SystemMetricSeriesRef>,
    samplesById: Map<String, SystemMetricSample>,
    isExpanded: Boolean,
    onToggleExpanded: () -> Unit,
    onClear: () -> Unit,
    expandedIds: Set<String>,
    onToggleDetails: (String) -> Unit,
    onTogglePin: (SystemMetricSeriesRef) -> Unit,
    onReorder: (List<SystemMetricSeriesRef>) -> Unit,
) {
    // Order shown while a drag is in flight and until the persisted list catches
    // up. Committing on every swap would mean a DataStore write per frame, and
    // clearing this the instant the finger lifts would flash the pre-drag order
    // for however long the write takes to round-trip.
    var workingPins by remember { mutableStateOf<List<SystemMetricSeriesRef>?>(null) }
    var draggingIndex by remember { mutableStateOf<Int?>(null) }
    // Offset of the dragged row within its current slot, in pixels.
    var dragOffset by remember { mutableFloatStateOf(0f) }
    // Measured row heights keyed by series id, NOT by index: a swap must not
    // invalidate the very measurements the next swap decision is made from.
    val rowHeights = remember { mutableStateMapOf<String, Int>() }

    LaunchedEffect(pins) {
        // The write landed (or the list changed from elsewhere) — drop the local copy.
        if (draggingIndex == null) workingPins = null
    }

    val displayed = workingPins ?: pins
    val isReorderable = displayed.size > 1

    // Takes the list to swap in rather than closing over `displayed`: several
    // pointer events can arrive between two recompositions, and the second swap of
    // a frame must build on the first one's result, not on the pre-drag order.
    fun swapWithNeighbour(
        list: List<SystemMetricSeriesRef>,
        current: Int,
        neighbour: Int,
        neighbourHeight: Int,
    ) {
        workingPins = SystemMetricsPinOrdering.move(list, current, neighbour)
        draggingIndex = neighbour
        // Carry over only the overshoot, so the row stays under the finger.
        dragOffset -= if (neighbour > current) neighbourHeight else -neighbourHeight
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onToggleExpanded, modifier = Modifier.size(32.dp)) {
                    Icon(
                        if (isExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = if (isExpanded) "Collapse pinned metrics" else "Expand pinned metrics",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(4.dp))
                Text(
                    text = "Pinned",
                    style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = "(${displayed.size})",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onClear) {
                    Text("Clear", style = MaterialTheme.typography.labelMedium)
                }
            }
            AnimatedVisibility(visible = isExpanded) {
                Column(modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) {
                    displayed.forEachIndexed { index, ref ->
                        val isDragging = draggingIndex == index
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .onGloballyPositioned { rowHeights[ref.id] = it.size.height }
                                // The dragged row rides above its neighbours so the
                                // rows it passes cannot paint over it.
                                .zIndex(if (isDragging) 1f else 0f)
                                .graphicsLayer { translationY = if (isDragging) dragOffset else 0f }
                                .alpha(if (isDragging) 0.85f else 1f),
                        ) {
                            Box(modifier = Modifier.weight(1f)) {
                                val sample = samplesById[ref.id]
                                if (sample != null) {
                                    MetricRow(
                                        sample = sample,
                                        isPinned = true,
                                        isExpanded = ref.id in expandedIds,
                                        onToggleDetails = { onToggleDetails(ref.id) },
                                        onTogglePin = { onTogglePin(ref) },
                                    )
                                } else {
                                    IdlePinnedRow(ref = ref, onUnpin = { onTogglePin(ref) })
                                }
                            }
                            if (isReorderable) {
                                DragHandle(
                                    metricKey = ref.key,
                                    onMoveUp = { onReorder(SystemMetricsPinOrdering.move(displayed, index, index - 1)) }
                                        .takeIf { index > 0 },
                                    onMoveDown = { onReorder(SystemMetricsPinOrdering.move(displayed, index, index + 1)) }
                                        .takeIf { index < displayed.lastIndex },
                                    onDragStart = {
                                        draggingIndex = index
                                        dragOffset = 0f
                                        workingPins = displayed
                                    },
                                    onDrag = { deltaY ->
                                        val from = draggingIndex ?: return@DragHandle
                                        dragOffset += deltaY
                                        val list = workingPins ?: return@DragHandle
                                        // Cross a neighbour's midpoint and the two trade
                                        // places, so the list reads as the final order the
                                        // whole time rather than only after release.
                                        if (dragOffset > 0 && from < list.lastIndex) {
                                            val height = rowHeights[list[from + 1].id] ?: 0
                                            if (height > 0 && dragOffset > height / 2f) {
                                                swapWithNeighbour(list, from, from + 1, height)
                                            }
                                        } else if (dragOffset < 0 && from > 0) {
                                            val height = rowHeights[list[from - 1].id] ?: 0
                                            if (height > 0 && -dragOffset > height / 2f) {
                                                swapWithNeighbour(list, from, from - 1, height)
                                            }
                                        }
                                    },
                                    onDragEnd = {
                                        draggingIndex = null
                                        dragOffset = 0f
                                        // `workingPins` deliberately survives the release —
                                        // LaunchedEffect(pins) drops it once the write lands.
                                        workingPins?.let(onReorder)
                                    },
                                )
                            }
                        }
                        if (index < displayed.lastIndex) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }
                }
            }
        }
    }
}

/**
 * The ☰ grab handle on a pinned row. Long-press then drag reorders; the long-press
 * requirement is what stops the enclosing LazyColumn from claiming the gesture as a
 * scroll.
 *
 * The same two moves are exposed as accessibility actions, because a drag needs
 * pointer precision that a screen-reader user does not have.
 */
@Composable
private fun DragHandle(
    metricKey: String,
    onMoveUp: (() -> Unit)?,
    onMoveDown: (() -> Unit)?,
    onDragStart: () -> Unit,
    onDrag: (Float) -> Unit,
    onDragEnd: () -> Unit,
) {
    val moveActions = buildList {
        onMoveUp?.let { add(CustomAccessibilityAction("Move $metricKey up") { it(); true }) }
        onMoveDown?.let { add(CustomAccessibilityAction("Move $metricKey down") { it(); true }) }
    }
    Icon(
        imageVector = Icons.Outlined.DragHandle,
        contentDescription = "Reorder $metricKey",
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .padding(horizontal = 6.dp)
            .size(20.dp)
            .semantics { customActions = moveActions }
            .pointerInput(metricKey) {
                detectDragGesturesAfterLongPress(
                    onDragStart = { onDragStart() },
                    onDragEnd = { onDragEnd() },
                    onDragCancel = { onDragEnd() },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        onDrag(dragAmount.y)
                    },
                )
            },
    )
}

@Composable
private fun IdlePinnedRow(ref: SystemMetricSeriesRef, onUnpin: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PinButton(isPinned = true, metricKey = ref.key, onClick = onUnpin)
        Spacer(Modifier.width(32.dp)) // aligns with rows that carry an info button
        Column(modifier = Modifier.weight(1f)) {
            Text(
                ref.key.removePrefix("ditto."),
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (ref.labelLine.isNotEmpty()) {
                Text(
                    ref.labelLine,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                "—",
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "no data yet",
                fontSize = 10.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StatusMessage(text: String, isError: Boolean = false) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(8.dp),
    )
}

/**
 * Opened ≠ closed since connect signals a connection leak or handshake instability.
 * Summed across label sets, not first-match: dsoq counters are reported per
 * transport, so one series' total is only part of the picture.
 */
@Composable
private fun DivergenceBanner(snapshot: SystemMetricsSnapshot) {
    fun total(key: String) = snapshot.samples.filter { it.key == key }.sumOf { it.sinceConnect }
    val opened = total("ditto.network.dsoq.connection.opened")
    val closed = total("ditto.network.dsoq.connection.closed")
    if (opened + closed == 0.0 || opened == closed) return

    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
    ) {
        Text(
            text = "dsoq connections opened (${formatMetricValue(opened)}) ≠ " +
                "closed (${formatMetricValue(closed)}) — possible connection leak or handshake issue. " +
                "Check the Log Analyzer's Transport Conditions tab.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.padding(8.dp),
        )
    }
}

@Composable
private fun PinButton(isPinned: Boolean, metricKey: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(32.dp)) {
        Icon(
            imageVector = if (isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
            contentDescription = if (isPinned) "Unpin $metricKey" else "Pin $metricKey",
            tint = if (isPinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun MetricRow(
    sample: SystemMetricSample,
    isPinned: Boolean,
    isExpanded: Boolean,
    onToggleDetails: () -> Unit,
    onTogglePin: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PinButton(isPinned = isPinned, metricKey = sample.key, onClick = onTogglePin)
            IconButton(onClick = onToggleDetails, modifier = Modifier.size(32.dp)) {
                Icon(
                    Icons.Outlined.Info,
                    contentDescription = "Details for ${sample.key}",
                    tint = if (isExpanded) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.size(18.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                // Wraps rather than truncates: metric names are long dot-separated
                // tokens whose distinguishing part is the suffix, which an ellipsis
                // would quietly eat.
                Text(
                    sample.key.removePrefix("ditto."),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (sample.labels.isNotEmpty()) {
                    Text(
                        sample.toSeriesRef().labelLine,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 10.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.width(8.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    headlineValue(sample),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                val period = sample.periodDelta
                Text(
                    if (period > 0) "▲ +${deltaValue(sample)}" else "—",
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    color = if (period > 0) {
                        Color(0xFF34C759)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
        AnimatedVisibility(visible = isExpanded) {
            MetricDetails(sample)
        }
    }
}

@Composable
private fun MetricDetails(sample: SystemMetricSample) {
    val average = sample.sumSinceConnect
        ?.takeIf { sample.kind == SystemMetricKind.HISTOGRAM && sample.sinceConnect > 0 }
        ?.let { formatScaled(it / sample.sinceConnect, sample.unit) }
    val absMax = sample.absMax
        ?.takeIf { sample.kind == SystemMetricKind.HISTOGRAM }
        ?.let { formatScaled(it, sample.unit) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            // Aligns the panel with the key column, past the pin + info buttons.
            .padding(start = 64.dp, end = 4.dp, bottom = 6.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(6.dp))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (sample.description.isNotBlank()) {
            Text(
                sample.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        DetailRow("METRIC", sample.key)
        DetailRow("KIND", if (sample.kind == SystemMetricKind.HISTOGRAM) "Histogram" else "Counter")
        if (sample.unit.isNotBlank()) DetailRow("UNIT", sample.unit)
        if (average != null) DetailRow("AVG SINCE CONNECT", average)
        if (absMax != null) DetailRow("ABS MAX", absMax)
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(verticalAlignment = Alignment.Top) {
        Text(
            text = label,
            fontSize = 9.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(120.dp),
        )
        Text(
            text = value,
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
    }
}
