package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.data.logging.LogAnalytics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The analyzer histograms are plotted against a real time axis, matching
 * SwiftUI's `x: .value("Time", bin.start)`.
 *
 * These tests exist because the geometry used to live inline in a `Canvas`
 * lambda as `index * (width / bins.size)`, where it was both untestable and
 * wrong: only *populated* bins are in the list, so index-based placement erases
 * every idle gap and redraws a burst as sustained activity.
 */
class LogHistogramGeometryTest {

    private val plotWidth = 1000f

    // ── timeDomainBars ──────────────────────────────────────────────────────

    @Test
    fun `an idle gap occupies proportional width`() {
        // Arrange — three 1s bins, but the third sits 10s after the second.
        val starts = listOf(0L, 1_000L, 11_000L)

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 1_000L, plotWidthPx = plotWidth)

        // Assert — the domain is [0, 12_000), so the last bar starts at
        // 11/12 of the width rather than at 2/3 of it as index placement gave.
        assertEquals(3, bars.size)
        assertEquals(0f, bars[0].leftPx, 0.01f)
        assertEquals(plotWidth * 1f / 12f, bars[1].leftPx, 0.01f)
        assertEquals(plotWidth * 11f / 12f, bars[2].leftPx, 0.01f)
    }

    @Test
    fun `evenly spaced bins are evenly spaced on screen`() {
        // Arrange — the case where index placement happened to be right.
        val starts = listOf(0L, 5_000L, 10_000L, 15_000L)

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 5_000L, plotWidthPx = plotWidth)

        // Assert
        assertEquals(0f, bars[0].leftPx, 0.01f)
        assertEquals(250f, bars[1].leftPx, 0.01f)
        assertEquals(500f, bars[2].leftPx, 0.01f)
        assertEquals(750f, bars[3].leftPx, 0.01f)
    }

    @Test
    fun `the domain ends at the end of the last bin, not its start`() {
        // Arrange — two adjacent bins.
        val starts = listOf(0L, 1_000L)

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 1_000L, plotWidthPx = plotWidth, gapPx = 0f)

        // Assert — each bar is half the plot. Ending the domain at the last bin
        // *start* would put the second bar's left edge at the far right, leaving
        // it nowhere to draw.
        assertEquals(0f, bars[0].leftPx, 0.01f)
        assertEquals(500f, bars[1].leftPx, 0.01f)
        assertEquals(500f, bars[0].widthPx, 0.01f)
        assertEquals(500f, bars[1].widthPx, 0.01f)
    }

    @Test
    fun `no bar is ever drawn outside the canvas`() {
        // Arrange — a long capture where the nominal bar is sub-pixel, so the
        // minimum-width floor is what decides the width.
        val starts = (0 until 400).map { it * 1_000L }

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 1_000L, plotWidthPx = plotWidth)

        // Assert
        assertTrue(bars.all { it.leftPx >= 0f })
        assertTrue(bars.all { it.leftPx + it.widthPx <= plotWidth + 0.01f })
    }

    @Test
    fun `every bar stays visible when bins outnumber pixels`() {
        // Arrange
        val starts = (0 until 4_000).map { it * 1_000L }

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 1_000L, plotWidthPx = plotWidth)

        // Assert — a 0.25px nominal bar would vanish; the floor keeps it drawn.
        assertTrue(bars.all { it.widthPx >= 1f })
    }

    @Test
    fun `a single bin fills the plot`() {
        // Arrange
        val starts = listOf(1_700_000_000_000L)

        // Act
        val bars = timeDomainBars(starts, binWidthMs = 60_000L, plotWidthPx = plotWidth, gapPx = 0f)

        // Assert
        assertEquals(1, bars.size)
        assertEquals(0f, bars[0].leftPx, 0.01f)
        assertEquals(plotWidth, bars[0].widthPx, 0.01f)
    }

    @Test
    fun `degenerate inputs produce no bars rather than NaN geometry`() {
        // Arrange / Act / Assert — a canvas can legitimately be measured at zero
        // width for a frame, and a NaN offset would poison the draw.
        assertEquals(emptyList<HistogramBar>(), timeDomainBars(emptyList(), 1_000L, plotWidth))
        assertEquals(emptyList<HistogramBar>(), timeDomainBars(listOf(0L, 1_000L), 1_000L, 0f))
    }

    @Test
    fun `a zero bin width does not divide by zero`() {
        // Arrange / Act
        val bars = timeDomainBars(listOf(0L, 1_000L), binWidthMs = 0L, plotWidthPx = plotWidth)

        // Assert
        assertTrue(bars.all { it.leftPx.isFinite() && it.widthPx.isFinite() })
    }

    // ── estimateBinWidthMs ──────────────────────────────────────────────────
    //
    // `LogAnalytics` derives the bin width from the window's time range and then
    // discards it, so the chart has to recover it from the bin starts alone.

    @Test
    fun `recovers the width exactly when two bins are adjacent`() {
        // Arrange — a 5s ladder step with one adjacent pair and one gap.
        val starts = listOf(0L, 5_000L, 60_000L)

        // Act / Assert
        assertEquals(5_000L, estimateBinWidthMs(starts))
    }

    @Test
    fun `recovers the width from sparse bins using the ladder`() {
        // Arrange — 30s bins, nearest populated pair 90s apart.
        val starts = listOf(0L, 90_000L, 180_000L)

        // Act — the true width for this range is 5s (range/40 = 4.5s → 5s), and
        // 5s divides 90s, so the estimator lands on it rather than on 90s.
        val width = estimateBinWidthMs(starts)

        // Assert
        assertEquals(5_000L, width)
        assertTrue(width in LogAnalytics.VOLUME_BIN_CANDIDATES_MS)
    }

    @Test
    fun `matches the picker over a long capture`() {
        // Arrange — a 13.7h capture binned at 30m, per the spec's table.
        val halfHour = 1_800_000L
        val starts = (0 until 28).map { it * halfHour }

        // Act
        val width = estimateBinWidthMs(starts)

        // Assert
        assertEquals(halfHour, width)
        assertEquals(LogAnalytics.pickBinWidthMs(27 * halfHour), width)
    }

    @Test
    fun `a single bin falls back to the finest candidate`() {
        // Arrange / Act / Assert — nothing to measure a gap against.
        assertEquals(LogAnalytics.VOLUME_BIN_CANDIDATES_MS.first(), estimateBinWidthMs(listOf(42L)))
        assertEquals(LogAnalytics.VOLUME_BIN_CANDIDATES_MS.first(), estimateBinWidthMs(emptyList()))
    }

    @Test
    fun `the estimate is never larger than the smallest gap`() {
        // Arrange — over-estimating past the smallest gap would let adjacent
        // bars overlap each other.
        val cases = listOf(
            listOf(0L, 1_000L, 2_000L),
            listOf(0L, 5_000L, 35_000L),
            listOf(0L, 30_000L, 630_000L),
            listOf(0L, 600_000L, 1_800_000L),
        )

        // Act / Assert
        cases.forEach { starts ->
            val minGap = starts.zipWithNext { a, b -> b - a }.min()
            assertTrue(
                "estimate for $starts exceeded its smallest gap",
                estimateBinWidthMs(starts) <= minGap,
            )
        }
    }
}
