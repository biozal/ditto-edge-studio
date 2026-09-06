package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import kotlin.math.roundToLong
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors `SwiftUI/EdgeStudioUnitTests/Logging/LogAnalyticsTests.swift`. The
 * constants pinned here are normative across SwiftUI, Android and the VS Code
 * extension (`docs/LOG_ANALYZER_SPEC.md`) — changing one is a deliberate
 * cross-platform decision, not a local tweak.
 */
class LogAnalyticsTest {

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun entry(
        message: String = "hello",
        atSeconds: Double = 0.0,
        level: DittoLogLevel = DittoLogLevel.Info,
        component: LogComponent = LogComponent.SYNC,
        rawLine: String? = null,
    ) = LogEntry(
        timestamp = Date((atSeconds * 1000).roundToLong()),
        level = level,
        message = message,
        component = component,
        source = LogEntrySource.DittoSDK,
        rawLine = rawLine ?: message,
    )

    private fun match(entry: LogEntry, key: String, severity: Int) = LogPatternEngine.Match(
        pattern = LogPatternEngine.CompiledPattern(
            key = key,
            regex = Regex(".", RegexOption.IGNORE_CASE),
            severity = severity,
            recommendation = "fix it",
            levelFilter = null,
            tagFilter = null,
            userTag = null,
            source = PatternSource.BUNDLED,
        ),
        entry = entry,
    )

    private fun connectionEntry(verb: String, atSeconds: Double, id: String) = entry(
        message = "physical connection $verb remote=pkA role=Client transport_type=Awdl connection_id=$id",
        atSeconds = atSeconds,
    )

    private fun session(durationSeconds: Double?) = ConnectionSession(
        start = Date(0),
        end = durationSeconds?.let { Date((it * 1000).roundToLong()) },
        remotePeer = "pkA",
        transport = "Awdl",
        role = "Client",
        connectionId = "1",
    )

    // ── Empty input ─────────────────────────────────────────────────────────

    @Test
    fun `an empty buffer produces an empty renderable snapshot`() {
        // Act
        val analytics = LogAnalytics.compute(emptyList(), emptyList())

        // Assert
        assertTrue(analytics.isEmpty)
        assertEquals(0, analytics.counts.totalLines)
        assertTrue(analytics.volumeByLevel.isEmpty())
        assertTrue(analytics.problemsOverTime.isEmpty())
        assertNull(analytics.startTime)
        assertNull(analytics.rangeDescription)
        // Duration buckets are always present so the row list never reflows.
        assertEquals(LogAnalytics.DURATION_BINS.size, analytics.connectionDurations.size)
    }

    // ── Counts ──────────────────────────────────────────────────────────────

    @Test
    fun `level counts follow entry levels`() {
        // Arrange
        val entries = listOf(
            entry(level = DittoLogLevel.Error),
            entry(level = DittoLogLevel.Error),
            entry(level = DittoLogLevel.Warning),
            entry(level = DittoLogLevel.Info),
            entry(level = DittoLogLevel.Debug),
            entry(level = DittoLogLevel.Verbose),
        )

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert
        assertEquals(2, analytics.counts.errors)
        assertEquals(1, analytics.counts.warnings)
        assertEquals(6, analytics.counts.totalLines)
    }

    @Test
    fun `problems counts occurrences while problemEntries counts distinct entries`() {
        // Arrange — one line matched by three patterns. `problems` is the honest
        // "how much went wrong" total; `problemEntries` is what the Problems tab
        // can actually list. A badge sourced from `problems` would promise three
        // rows where only one exists.
        val shared = entry("boom", atSeconds = 10.0, level = DittoLogLevel.Error)
        val matches = listOf(
            match(shared, "a", 3),
            match(shared, "b", 3),
            match(shared, "c", 3),
        )

        // Act
        val analytics = LogAnalytics.compute(listOf(shared), matches)

        // Assert
        assertEquals(3, analytics.counts.problems)
        assertEquals(1, analytics.counts.problemEntries)
    }

    @Test
    fun `critical counts occurrences while criticalEntries counts distinct entries`() {
        // Arrange
        val shared = entry("boom", atSeconds = 10.0, level = DittoLogLevel.Error)
        val other = entry("bang", atSeconds = 11.0, level = DittoLogLevel.Error)
        val matches = listOf(
            match(shared, "a", 5),
            match(shared, "b", 5),
            match(other, "c", 4),
        )

        // Act
        val analytics = LogAnalytics.compute(listOf(shared, other), matches)

        // Assert
        assertEquals(2, analytics.counts.critical)
        assertEquals(1, analytics.counts.criticalEntries)
        assertEquals(2, analytics.counts.problemEntries)
        assertEquals(3, analytics.counts.problems)
    }

    @Test
    fun `severity below 5 is not critical`() {
        // Arrange
        val logEntry = entry("uh oh", atSeconds = 1.0, level = DittoLogLevel.Error)

        // Act
        val analytics = LogAnalytics.compute(listOf(logEntry), listOf(match(logEntry, "a", 4)))

        // Assert
        assertEquals(0, analytics.counts.critical)
        assertEquals(0, analytics.counts.criticalEntries)
        assertEquals(1, analytics.counts.problemEntries)
    }

    // ── Bin width selection ─────────────────────────────────────────────────

    @Test
    fun `bin width candidates match the cross-platform spec`() {
        assertEquals(
            listOf(1_000L, 5_000L, 30_000L, 60_000L, 300_000L, 600_000L, 1_800_000L),
            LogAnalytics.VOLUME_BIN_CANDIDATES_MS,
        )
        assertEquals(40, LogAnalytics.VOLUME_BIN_TARGET_BUCKETS)
    }

    @Test
    fun `bin width scales with the time range`() {
        // Ladder: the finest candidate whose width keeps the bucket count at or
        // below the 40-bucket target.
        // 1s→1s, 40s→1s, 200s→5s, 20m→30s, 40m→60s, 13,7h→30m, overflow→30m.
        val cases = listOf(
            1_000L to 1_000L,
            40_000L to 1_000L,
            200_000L to 5_000L,
            1_200_000L to 30_000L,
            2_400_000L to 60_000L,
            49_320_000L to 1_800_000L,
            Long.MAX_VALUE / 2 to 1_800_000L,
        )

        for ((rangeMs, expected) in cases) {
            assertEquals("rangeMs=$rangeMs", expected, LogAnalytics.pickBinWidthMs(rangeMs))
        }
    }

    @Test
    fun `bin width clamps a non-positive range to the finest candidate`() {
        assertEquals(1_000L, LogAnalytics.pickBinWidthMs(0L))
        assertEquals(1_000L, LogAnalytics.pickBinWidthMs(-5_000L))
    }

    // ── Volume histogram ────────────────────────────────────────────────────

    @Test
    fun `entries are bucketed by bin start and split by level`() {
        // Arrange — a 40s span bins at 1s, so these land in three buckets.
        val entries = listOf(
            entry(atSeconds = 0.0, level = DittoLogLevel.Info),
            entry(atSeconds = 0.5, level = DittoLogLevel.Error),
            entry(atSeconds = 1.0, level = DittoLogLevel.Info),
            entry(atSeconds = 40.0, level = DittoLogLevel.Warning),
        )

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert
        assertEquals(3, analytics.volumeByLevel.size)
        assertEquals(listOf(0L, 1_000L, 40_000L), analytics.volumeByLevel.map { it.startMs })
        assertEquals(1, analytics.volumeByLevel[0].counts[DittoLogLevel.Info])
        assertEquals(1, analytics.volumeByLevel[0].counts[DittoLogLevel.Error])
        assertEquals(2, analytics.volumeByLevel[0].total)
        assertEquals(1, analytics.volumeByLevel[2].counts[DittoLogLevel.Warning])
    }

    @Test
    fun `volume bins come back in ascending time order`() {
        // Arrange — deliberately unsorted input; bins are keyed by a hash map
        // internally, whose iteration order is not stable.
        val entries = listOf(entry(atSeconds = 30.0), entry(atSeconds = 0.0), entry(atSeconds = 15.0))

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert
        val starts = analytics.volumeByLevel.map { it.startMs }
        assertEquals(starts.sorted(), starts)
    }

    @Test
    fun `the level stack order is fixed bottom to top`() {
        assertEquals(
            listOf(
                DittoLogLevel.Verbose,
                DittoLogLevel.Debug,
                DittoLogLevel.Info,
                DittoLogLevel.Warning,
                DittoLogLevel.Error,
            ),
            LogAnalytics.LEVEL_STACK_ORDER,
        )
    }

    // ── Problems histogram ──────────────────────────────────────────────────

    @Test
    fun `a problem bin reports the worst severity it contains`() {
        // Arrange
        val first = entry("a", atSeconds = 0.0, level = DittoLogLevel.Error)
        val second = entry("b", atSeconds = 0.2, level = DittoLogLevel.Error)
        val matches = listOf(match(first, "low", 2), match(second, "high", 5))

        // Act
        val analytics = LogAnalytics.compute(listOf(first, second), matches)

        // Assert
        assertEquals(1, analytics.problemsOverTime.size)
        assertEquals(2, analytics.problemsOverTime[0].count)
        assertEquals(5, analytics.problemsOverTime[0].maxSeverity)
    }

    @Test
    fun `problem bins come back in ascending time order`() {
        // Arrange — a 40s span bins at 1s; matches are supplied newest first.
        val late = entry("late", atSeconds = 40.0, level = DittoLogLevel.Error)
        val early = entry("early", atSeconds = 0.0, level = DittoLogLevel.Error)
        val matches = listOf(match(late, "a", 3), match(early, "b", 3))

        // Act
        val analytics = LogAnalytics.compute(listOf(early, late), matches)

        // Assert
        assertEquals(listOf(0L, 40_000L), analytics.problemsOverTime.map { it.startMs })
    }

    // ── Duration bucketing ──────────────────────────────────────────────────

    @Test
    fun `duration buckets match the cross-platform spec`() {
        assertEquals(
            listOf("0–1s", "1–5s", "5–30s", "30s–5m", "5m+"),
            LogAnalytics.DURATION_BINS.map { it.first },
        )
    }

    @Test
    fun `durations land in the right bucket at every boundary`() {
        // Buckets are half-open (`duration < maxSeconds`), so a value sitting
        // exactly on a boundary belongs to the next bucket up.
        val cases = listOf(
            0.0 to 0,
            0.9 to 0,
            1.0 to 1,
            4.9 to 1,
            5.0 to 2,
            29.9 to 2,
            30.0 to 3,
            299.9 to 3,
            300.0 to 4,
            10_000.0 to 4,
        )

        for ((duration, expectedIndex) in cases) {
            // Act
            val bins = LogAnalytics.binDurations(listOf(session(duration)))

            // Assert
            assertEquals("duration=$duration", 1, bins[expectedIndex].count)
            assertEquals("duration=$duration", 1, bins.sumOf { it.count })
        }
    }

    @Test
    fun `open sessions are excluded from the duration buckets`() {
        // Act
        val bins = LogAnalytics.binDurations(listOf(session(null)))

        // Assert
        assertEquals(0, bins.sumOf { it.count })
        assertEquals(LogAnalytics.DURATION_BINS.size, bins.size)
        assertTrue(bins.all { it.isEmpty })
    }

    @Test
    fun `connection sessions are reconstructed from the entry buffer`() {
        // Arrange
        val entries = listOf(
            connectionEntry("started", atSeconds = 0.0, id = "1"),
            connectionEntry("ended", atSeconds = 7.0, id = "1"),
        )

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert — 7s lands in the "5–30s" bucket.
        assertEquals(1, analytics.connectionDurations[2].count)
        assertEquals(1, analytics.sessions.size)
    }

    @Test
    fun `sessions are tracked over the full buffer not the analysis window`() {
        // Arrange — the SwiftUI port rebuilds the tracker over the same capped
        // window it analyses, so a `started` that aged out of the window can
        // never be paired. Roughly a third of real sessions span a wider gap.
        val start = connectionEntry("started", atSeconds = 0.0, id = "1")
        val end = connectionEntry("ended", atSeconds = 7.0, id = "1")
        val window = listOf(end) // the `started` line has aged out
        val fullBuffer = listOf(start, end)

        // Act
        val windowedOnly = LogAnalytics.compute(window, emptyList())
        val withFullBuffer = LogAnalytics.compute(window, emptyList(), sessionEntries = fullBuffer)

        // Assert
        assertEquals(0, windowedOnly.connectionDurations.sumOf { it.count })
        assertEquals(1, withFullBuffer.connectionDurations[2].count)
        // Counts still describe the analysis window, not the session buffer.
        assertEquals(1, withFullBuffer.counts.totalLines)
    }

    // ── Metadata ────────────────────────────────────────────────────────────

    @Test
    fun `tags are the distinct components sorted`() {
        // Arrange
        val entries = listOf(
            entry(atSeconds = 0.0, component = LogComponent.SYNC),
            entry(atSeconds = 1.0, component = LogComponent.AUTH),
            entry(atSeconds = 2.0, component = LogComponent.SYNC),
        )

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert
        assertEquals(listOf("Auth", "Sync"), analytics.tags)
    }

    @Test
    fun `the time range spans the earliest and latest entry regardless of input order`() {
        // Arrange
        val entries = listOf(entry(atSeconds = 500.0), entry(atSeconds = 100.0), entry(atSeconds = 300.0))

        // Act
        val analytics = LogAnalytics.compute(entries, emptyList())

        // Assert
        assertEquals(Date(100_000), analytics.startTime)
        assertEquals(Date(500_000), analytics.endTime)
        assertTrue(analytics.rangeDescription!!.contains("→"))
        assertFalse(analytics.isEmpty)
    }

    @Test
    fun `human duration formatting picks a sensible unit`() {
        val cases = listOf(
            0.5 to "<1s",
            45.0 to "45s",
            90.0 to "1.5m",
            5_400.0 to "1.5h",
            129_600.0 to "1.5d",
        )

        for ((seconds, expected) in cases) {
            assertEquals("seconds=$seconds", expected, LogAnalytics.humanDuration(seconds))
        }
    }
}
