package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.data.logging.LogAnalytics

/**
 * Horizontal placement of one histogram bar, in pixels within the plot.
 *
 * Deliberately a plain value type with no Compose types: the whole point of
 * hoisting this out of the `Canvas` lambda is that the geometry is unit-testable
 * and cannot participate in a layout pass. Nothing here is ever fed back into a
 * `Modifier` — the caller draws into a fixed-height canvas whose size it was
 * handed, so a wide bar can never grow the section. (The SwiftUI counterpart of
 * this hazard once grew the app window past the display.)
 */
internal data class HistogramBar(val leftPx: Float, val widthPx: Float)

/**
 * Maps time-binned histogram bars onto a real time axis.
 *
 * ## Why not `index * (width / count)`
 *
 * Only **populated** bins exist in [LogAnalytics.volumeByLevel] /
 * [LogAnalytics.problemsOverTime] — both platforms accumulate them in a hash map
 * keyed by bin start, so an idle interval contributes no entry at all. Laying the
 * bars out by list index therefore collapses every idle gap to nothing: a burst
 * that SwiftUI (`x: .value("Time", bin.start)`) draws as a spike surrounded by
 * whitespace draws on Android as a contiguous run of equal-width bars, and the
 * chart tells a different story about the same capture.
 *
 * Plotting against `[minStart, maxStart + binWidth]` restores the proportional
 * whitespace.
 *
 * @param startsMs bin start times, ascending (the order [LogAnalytics.compute] emits).
 * @param binWidthMs width of one bin in ms — see [estimateBinWidthMs].
 * @param plotWidthPx the canvas width the caller was handed.
 * @param gapPx hairline gap trimmed from each bar so adjacent bars stay distinct.
 * @param minBarWidthPx floor so a bar in a long capture never vanishes entirely.
 */
internal fun timeDomainBars(
    startsMs: List<Long>,
    binWidthMs: Long,
    plotWidthPx: Float,
    gapPx: Float = 1f,
    minBarWidthPx: Float = 1f,
): List<HistogramBar> {
    if (startsMs.isEmpty() || plotWidthPx <= 0f) return emptyList()

    val domainStart = startsMs.first()
    val width = binWidthMs.coerceAtLeast(1L)
    // The domain ends at the *end* of the last bin, not its start — otherwise a
    // two-bin chart would put the second bar's left edge at the far right and
    // leave it nowhere to be drawn.
    val domainSpan = ((startsMs.last() + width) - domainStart).coerceAtLeast(1L)
    val scale = plotWidthPx / domainSpan.toFloat()

    val nominalBarWidth = width.toFloat() * scale
    val barWidth = (nominalBarWidth - gapPx).coerceAtLeast(minBarWidthPx.coerceAtMost(plotWidthPx))

    return startsMs.map { start ->
        val rawLeft = (start - domainStart).toFloat() * scale
        // Keep the bar inside the canvas: the rightmost bin's nominal slot ends
        // exactly at plotWidthPx, but the min-width floor can push a bar past it
        // in a very long capture.
        val left = rawLeft.coerceIn(0f, (plotWidthPx - barWidth).coerceAtLeast(0f))
        HistogramBar(leftPx = left, widthPx = barWidth)
    }
}

/**
 * Recovers the bin width [LogAnalytics.compute] used, from the bin starts alone.
 *
 * `LogAnalytics` does not carry the width on its bins (both this platform and
 * SwiftUI derive it from the window's time range and then discard it), and this
 * file must not reach into the data layer to change that. It is recoverable
 * because the width is always one of [LogAnalytics.VOLUME_BIN_CANDIDATES_MS] and
 * every bin start is `floor(t / width) * width`, so:
 *
 * - the true width **divides** every gap between consecutive bin starts, and
 * - the true width is **at least** `pickBinWidthMs(span of the bin starts)`,
 *   because the entry range the picker actually saw is at least that span and
 *   the picker is monotonic.
 *
 * The smallest ladder candidate satisfying both is the answer, and it is exact
 * whenever any two populated bins are adjacent — the overwhelmingly common case.
 * A sparse chart can over-estimate by one ladder step, which only widens the
 * bars slightly; it can never mis-place them, because placement uses the true
 * bin starts.
 */
internal fun estimateBinWidthMs(startsMs: List<Long>): Long {
    if (startsMs.size < 2) return LogAnalytics.VOLUME_BIN_CANDIDATES_MS.first()

    val span = startsMs.last() - startsMs.first()
    val lowerBound = LogAnalytics.pickBinWidthMs(maxOf(span, 1L))

    var minGap = Long.MAX_VALUE
    for (index in 1 until startsMs.size) {
        val gap = startsMs[index] - startsMs[index - 1]
        if (gap in 1 until minGap) minGap = gap
    }
    if (minGap == Long.MAX_VALUE) return lowerBound

    return LogAnalytics.VOLUME_BIN_CANDIDATES_MS
        .firstOrNull { it >= lowerBound && minGap % it == 0L }
        ?: minGap.coerceAtLeast(lowerBound)
}
