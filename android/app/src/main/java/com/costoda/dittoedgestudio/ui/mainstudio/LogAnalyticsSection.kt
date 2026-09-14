package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.data.logging.LogAnalytics
import com.costoda.dittoedgestudio.ui.adaptive.showsListDetail
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.ditto.kotlin.DittoLogLevel
import com.costoda.dittoedgestudio.domain.model.shortName
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Level → color for the analyzer charts. These are the hexes pinned by
 * `docs/LOG_ANALYZER_SPEC.md` §6 and shared with SwiftUI and the VS Code
 * extension, so the same capture renders the same way on all three platforms.
 *
 * Deliberately separate from [levelColor], which tints the per-row level badge
 * against the app's Material theme and predates the shared palette.
 */
internal fun logLevelChartColor(level: DittoLogLevel): Color = when (level) {
    DittoLogLevel.Error -> Color(0xFFFF5252)
    DittoLogLevel.Warning -> Color(0xFFD4A017)
    DittoLogLevel.Info -> Color(0xFF4EA1FF)
    DittoLogLevel.Debug -> Color(0xFF888888)
    DittoLogLevel.Verbose -> Color(0xFF555555)
}

/**
 * Stable render order for the stacked volume bars, quietest at the bottom.
 * A map's iteration order is not stable, so relying on it would make the stack
 * reshuffle between refreshes (spec §4). Sourced from the data layer so the
 * order is pinned in one place.
 */
private val VOLUME_LEVEL_ORDER: List<DittoLogLevel> = LogAnalytics.LEVEL_STACK_ORDER

/** Bar color for the connection-duration tracks (#4ea1ff, spec §6 "info"). */
private val DurationTrackColor = Color(0xFF4EA1FF)

/**
 * Fixed drawing height for each time-series chart.
 *
 * Matches SwiftUI's *ideal* chart height (`LogAnalyticsSection.chartHeight`
 * = 150). SwiftUI expresses it as `minHeight 70 / ideal 150 / maxHeight ∞`
 * inside the [HISTOGRAMS_MAX_HEIGHT] region and lets the charts flex; Compose's
 * `Canvas` has no intrinsic size to flex from, so the ideal is pinned instead.
 * Pinning is also the safer half of that pair here — a `maxHeight ∞` chart in a
 * `Column` would be free to negotiate its own height, which is exactly the
 * feedback loop the fixed canvas exists to prevent.
 */
private val CHART_HEIGHT = 150.dp

/**
 * Hard cap on the whole histogram region.
 *
 * The section sits in a [Column] above a weighted log list, so anything it
 * contributes to the minimum height is taken from the list. Bounding it here —
 * and scrolling internally past the bound — is what stops a tall chart from
 * squeezing the log rows off the screen. This is the Compose counterpart of the
 * SwiftUI hazard where a `GeometryReader`-sized bar list grew the window past
 * the display: never size a bar with a greedy layout primitive, and never let
 * this region negotiate its own height.
 */
private val HISTOGRAMS_MAX_HEIGHT = 340.dp

private val axisTimeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

// MARK: - Log Volume by Level

/**
 * Stacked bars of entry volume per time bin, one segment per level in
 * [VOLUME_LEVEL_ORDER] (verbose at the bottom, error on top).
 *
 * Bars are placed on a **real time axis** by [timeDomainBars], matching
 * SwiftUI's `x: .value("Time", bin.start)`. Only populated bins exist in
 * [LogAnalytics.volumeByLevel], so laying them out by list index would collapse
 * every idle gap and turn a burst into apparent sustained activity.
 *
 * Drawn on a [Canvas] with a fixed height rather than composed from weighted
 * boxes: the canvas is handed a bounded size and reports it back unchanged, so
 * there is no way for bar geometry to feed back into the layout pass.
 */
@Composable
fun LogVolumeHistogram(
    bins: List<LogAnalytics.VolumeBin>,
    modifier: Modifier = Modifier,
) {
    if (bins.isEmpty()) {
        LogChartPlaceholder("No volume data yet.", modifier.testTag("LogVolumeHistogram"))
        return
    }
    val maxTotal = remember(bins) {
        bins.maxOf { bin -> bin.counts.values.sum() }.coerceAtLeast(1)
    }
    val starts = remember(bins) { bins.map { it.startMs } }
    val binWidthMs = remember(starts) { estimateBinWidthMs(starts) }
    val segmentColors = remember { VOLUME_LEVEL_ORDER.map(::logLevelChartColor) }

    Column(modifier = modifier.testTag("LogVolumeHistogram")) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(CHART_HEIGHT),
        ) {
            val slots = timeDomainBars(starts, binWidthMs, size.width)
            bins.forEachIndexed { index, bin ->
                val slot = slots.getOrNull(index) ?: return@forEachIndexed
                var bottom = size.height
                VOLUME_LEVEL_ORDER.forEachIndexed { levelIndex, level ->
                    val count = bin.counts[level] ?: 0
                    if (count <= 0) return@forEachIndexed
                    val segmentHeight = size.height * count / maxTotal
                    drawRect(
                        color = segmentColors[levelIndex],
                        topLeft = Offset(slot.leftPx, bottom - segmentHeight),
                        size = Size(slot.widthPx, segmentHeight),
                    )
                    bottom -= segmentHeight
                }
            }
        }
        TimeAxisLabels(firstMs = bins.first().startMs, lastMs = bins.last().startMs, peak = maxTotal)
        LevelLegend()
    }
}

/** Level swatches for the stacked bars — without them the stack is unreadable. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LevelLegend() {
    FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        VOLUME_LEVEL_ORDER.reversed().forEach { level ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(RoundedCornerShape(2.dp)),
                ) {
                    Canvas(Modifier.fillMaxWidth().height(7.dp)) {
                        drawRect(logLevelChartColor(level))
                    }
                }
                Text(
                    text = level.shortName,
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// MARK: - Problems over Time

/**
 * One bar per time bin; height is the match count, color the bin's worst
 * severity. Placed on a real time axis by [timeDomainBars] — see
 * [LogVolumeHistogram] for why index-based placement is wrong.
 */
@Composable
fun LogProblemsHistogram(
    bins: List<LogAnalytics.ProblemBin>,
    modifier: Modifier = Modifier,
) {
    if (bins.isEmpty()) {
        LogChartPlaceholder("No problems yet.", modifier.testTag("LogProblemsHistogram"))
        return
    }
    val peak = remember(bins) { bins.maxOf { it.count }.coerceAtLeast(1) }
    val barColors = remember(bins) { bins.map { severityColor(it.maxSeverity) } }
    val starts = remember(bins) { bins.map { it.startMs } }
    val binWidthMs = remember(starts) { estimateBinWidthMs(starts) }

    Column(modifier = modifier.testTag("LogProblemsHistogram")) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(CHART_HEIGHT),
        ) {
            val slots = timeDomainBars(starts, binWidthMs, size.width)
            bins.forEachIndexed { index, bin ->
                if (bin.count <= 0) return@forEachIndexed
                val slot = slots.getOrNull(index) ?: return@forEachIndexed
                val barHeight = size.height * bin.count / peak
                drawRect(
                    color = barColors[index],
                    topLeft = Offset(slot.leftPx, size.height - barHeight),
                    size = Size(slot.widthPx, barHeight),
                )
            }
        }
        TimeAxisLabels(firstMs = bins.first().startMs, lastMs = bins.last().startMs, peak = peak)
    }
}

/** `HH:mm:ss … peak N … HH:mm:ss` strip under a time-series chart. */
@Composable
private fun TimeAxisLabels(firstMs: Long, lastMs: Long, peak: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AxisLabel(axisTimeFormat.format(Date(firstMs)))
        Text(
            text = "peak $peak",
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        AxisLabel(axisTimeFormat.format(Date(lastMs)))
    }
}

@Composable
private fun AxisLabel(text: String) {
    Text(
        text = text,
        fontSize = 9.sp,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// MARK: - Connection Durations

/**
 * Closed-connection counts per duration bucket, as a `label │ track │ count`
 * row list.
 *
 * Deliberately **not** a chart. A categorical bar chart wants far more vertical
 * room than five buckets deserve: at the height this section can afford the
 * band labels collide, and a lone populated bucket renders as a hairline across
 * a mostly-empty plot. A [LinearProgressIndicator] gives a correctly
 * proportioned, natively sized bar with neither hazard.
 *
 * Empty buckets stay on screen (dimmed) so the ladder does not reflow as
 * connections close.
 */
@Composable
fun LogConnectionDurationsList(
    bins: List<LogAnalytics.DurationBin>,
    modifier: Modifier = Modifier,
) {
    val totalClosed = bins.sumOf { it.count }
    if (totalClosed == 0) {
        LogChartPlaceholder("No closed connections yet.", modifier.testTag("LogConnectionDurations"))
        return
    }
    // Scale to the busiest bucket so the widest bar always fills the track.
    val peak = bins.maxOf { it.count }.coerceAtLeast(1)

    Column(
        modifier = modifier.testTag("LogConnectionDurations"),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        bins.forEach { bin ->
            val populated = bin.count > 0
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = bin.label,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (populated) 1f else 0.45f,
                    ),
                    // Fixed so every track starts at the same x — "30s–5m" is
                    // much wider than "5m+".
                    modifier = Modifier.width(58.dp),
                    maxLines = 1,
                )
                LinearProgressIndicator(
                    progress = { bin.count.toFloat() / peak.toFloat() },
                    modifier = Modifier
                        .weight(1f)
                        .height(6.dp),
                    color = DurationTrackColor.copy(alpha = if (populated) 1f else 0.35f),
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                    drawStopIndicator = {},
                )
                Text(
                    text = bin.count.toString(),
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (populated) 1f else 0.45f,
                    ),
                    modifier = Modifier.width(28.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.End,
                    maxLines = 1,
                )
            }
        }
    }
}

// MARK: - Shared placeholder

@Composable
private fun LogChartPlaceholder(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(36.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// MARK: - Container

/**
 * The three analyzer histograms behind one expandable "Histograms" card.
 *
 * There is deliberately **no** Summary block: its Critical / Errors / Warnings
 * / Problems / Lines figures are the same numbers [LogFilterTabs] already
 * carries as badges a few points below, and two readings of one statistic
 * invite them to disagree.
 *
 * Collapsed by default at **every** width, matching SwiftUI
 * (`histogramsExpandedByDefault: Bool = false`). The log rows are what the
 * screen is for; the charts are an opt-in.
 *
 * Adaptivity (via `ui/adaptive/WindowSize.kt`, the project's single source of
 * truth for window-size decisions) affects the *layout* only, never the default:
 * - **Compact width (< 600dp, phones):** the two time-series charts stack
 *   rather than squeezing to illegibility.
 * - **Medium and up:** charts side by side.
 *
 * The expand/collapse flag is [rememberSaveable] and deliberately **not** keyed
 * on the width class. Keying it on width (`remember(wide)`) reset the flag on
 * every width-class change, so rotating the tablet or entering split-screen
 * silently threw away the user's choice and re-decided for them.
 *
 * At every width the content is bounded by [HISTOGRAMS_MAX_HEIGHT] and scrolls
 * internally past it, so this section can never grow the screen.
 */
@Composable
fun LogAnalyticsSection(
    analytics: LogAnalytics?,
    modifier: Modifier = Modifier,
) {
    if (analytics == null || analytics.isEmpty) return

    val wide = studioWindowSizeClass().showsListDetail
    var expanded by rememberSaveable { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxWidth().testTag("LogAnalyticsSection")) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
            shape = MaterialTheme.shapes.small,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 2.dp),
        ) {
            Row(
                modifier = Modifier
                    .clickable { expanded = !expanded }
                    .padding(8.dp)
                    .testTag("LogHistogramsHeader"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "Histograms",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    imageVector = if (expanded) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown,
                    contentDescription = if (expanded) "Hide histograms" else "Show histograms",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        AnimatedVisibility(visible = expanded) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = HISTOGRAMS_MAX_HEIGHT)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (wide) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        TitledChart("Log Volume by Level", Modifier.weight(1f)) {
                            LogVolumeHistogram(analytics.volumeByLevel)
                        }
                        TitledChart("Problems over Time", Modifier.weight(1f)) {
                            LogProblemsHistogram(analytics.problemsOverTime)
                        }
                    }
                } else {
                    TitledChart("Log Volume by Level") {
                        LogVolumeHistogram(analytics.volumeByLevel)
                    }
                    TitledChart("Problems over Time") {
                        LogProblemsHistogram(analytics.problemsOverTime)
                    }
                }
                TitledChart("Connection Durations") {
                    LogConnectionDurationsList(analytics.connectionDurations)
                }
            }
        }
    }
}

@Composable
private fun TitledChart(
    title: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        content()
    }
}
