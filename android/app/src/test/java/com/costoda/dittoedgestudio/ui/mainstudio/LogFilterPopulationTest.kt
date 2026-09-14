package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The analysis population — filter the whole buffer first, window second.
 *
 * The property under test throughout is that **the badges and the list describe
 * the same set**. Windowing first (what this replaced) kept that property but
 * blinded search and the date filter to anything older than the newest 5 000;
 * filtering the whole buffer but counting over the tail (what SwiftUI does)
 * un-blinds search but makes the badges describe a different set of rows.
 */
class LogFilterPopulationTest {

    private fun entry(
        index: Int,
        message: String = "line-$index",
        level: DittoLogLevel = DittoLogLevel.Info,
        component: LogComponent = LogComponent.SYNC,
        timeMs: Long = index * 1_000L,
    ) = LogEntry(
        timestamp = Date(timeMs),
        level = level,
        message = message,
        component = component,
        source = LogEntrySource.DittoSDK,
        rawLine = message,
    )

    private fun buffer(count: Int) = (0 until count).map { entry(it) }

    // ── The defect this replaced ────────────────────────────────────────────

    @Test
    fun `search reaches entries older than the analysis window`() {
        // Arrange — 12 000 entries where the needle is only in the oldest 7 000.
        // Windowing first returned nothing here, and the screen said "No log
        // entries" for a string the buffer plainly contains.
        val entries = (0 until 12_000).map { entry(it, message = if (it < 7_000) "needle-$it" else "chaff-$it") }

        // Act
        val population = logAnalysisPopulation(
            full = entries,
            filter = LogPopulationFilter(searchQuery = "needle"),
            maxWindow = 5_000,
        )

        // Assert
        assertEquals(7_000, population.matchedCount)
        assertEquals(5_000, population.entries.size)
        assertTrue(population.entries.all { it.message.startsWith("needle") })
    }

    @Test
    fun `the badge population is the population the list filters`() {
        // Arrange — the invariant. Whatever the filter, the counts a badge is
        // computed from and the rows the list can render come from one list.
        val entries = (0 until 8_000).map {
            entry(it, message = if (it % 2 == 0) "keep-$it" else "drop-$it")
        }

        // Act
        val population = logAnalysisPopulation(
            full = entries,
            filter = LogPopulationFilter(searchQuery = "keep"),
            maxWindow = 5_000,
        )
        val displayed = logDisplayEntries(
            population = population.entries,
            filterTab = LogFilterTab.ALL,
            problemIds = emptySet(),
            criticalIds = emptySet(),
            selectedLevels = DittoLogLevel.entries.toSet(),
            maxDisplayed = Int.MAX_VALUE,
        )

        // Assert — the All badge reads `counts.totalLines`, which is computed
        // over `population.entries`; with no tab or chip narrowing, the list is
        // exactly that set.
        assertEquals(population.entries.size, displayed.size)
    }

    // ── Windowing ───────────────────────────────────────────────────────────

    @Test
    fun `keeps the newest matches when more match than fit`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val population = logAnalysisPopulation(
            full = entries,
            filter = LogPopulationFilter(searchQuery = "line"),
            maxWindow = 5,
        )

        // Assert — newest, not oldest.
        assertEquals(listOf("line-15", "line-16", "line-17", "line-18", "line-19"), population.entries.map { it.message })
        assertEquals(20, population.matchedCount)
        assertTrue(population.isWindowed)
    }

    @Test
    fun `is not windowed when every match fits`() {
        // Arrange
        val entries = buffer(10)

        // Act
        val population = logAnalysisPopulation(entries, LogPopulationFilter(), maxWindow = 5_000)

        // Assert
        assertFalse(population.isWindowed)
        assertEquals(10, population.matchedCount)
        assertEquals(10, population.bufferCount)
    }

    @Test
    fun `an inactive filter takes the plain tail without allocating a copy`() {
        // Arrange — the steady state has to stay as cheap as the takeLast it
        // replaced, so the fast path must return the buffer itself.
        val entries = buffer(100)

        // Act
        val population = logAnalysisPopulation(entries, LogPopulationFilter(), maxWindow = 5_000)

        // Assert
        assertSame(entries, population.entries)
    }

    @Test
    fun `an empty buffer yields an empty population`() {
        // Arrange / Act
        val population = logAnalysisPopulation(emptyList(), LogPopulationFilter(searchQuery = "x"), maxWindow = 5_000)

        // Assert
        assertEquals(LogPopulation.EMPTY, population)
    }

    // ── Which filters belong to the population ──────────────────────────────

    @Test
    fun `date range filters the whole buffer`() {
        // Arrange — one entry per second; keep the 10th to 20th.
        val entries = buffer(100)

        // Act
        val population = logAnalysisPopulation(
            full = entries,
            filter = LogPopulationFilter(
                dateFilterEnabled = true,
                dateRangeStartMillis = 10_000L,
                dateRangeEndMillis = 20_000L,
            ),
            maxWindow = 5_000,
        )

        // Assert — inclusive at both ends, as the date pickers' full-day bounds
        // assume.
        assertEquals(11, population.entries.size)
        assertEquals("line-10", population.entries.first().message)
        assertEquals("line-20", population.entries.last().message)
    }

    @Test
    fun `component applies only where the source has components`() {
        // Arrange
        val entries = listOf(
            entry(0, component = LogComponent.SYNC),
            entry(1, component = LogComponent.TRANSPORT),
        )

        // Act
        val onSdk = logAnalysisPopulation(
            entries,
            LogPopulationFilter(component = LogComponent.SYNC, componentApplies = true),
            maxWindow = 5_000,
        )
        val onOtherSource = logAnalysisPopulation(
            entries,
            LogPopulationFilter(component = LogComponent.SYNC, componentApplies = false),
            maxWindow = 5_000,
        )

        // Assert
        assertEquals(1, onSdk.entries.size)
        assertEquals(2, onOtherSource.entries.size)
    }

    @Test
    fun `search matches user tags as well as messages`() {
        // Arrange — SwiftUI's search matches the pattern tag column too, so a
        // tag-only query must not come back empty.
        val tagged = entry(0, message = "nothing quotable here")
        val entries = listOf(tagged, entry(1, message = "unrelated"))
        val tags = mapOf<UUID, List<String>>(tagged.id to listOf("auth-failure"))

        // Act
        val population = logAnalysisPopulation(
            full = entries,
            filter = LogPopulationFilter(searchQuery = "auth"),
            searchTagsById = tags,
            maxWindow = 5_000,
        )

        // Assert
        assertEquals(listOf(tagged.id), population.entries.map { it.id })
    }

    @Test
    fun `search is case insensitive and whitespace tolerant`() {
        // Arrange
        val entries = listOf(entry(0, message = "Physical Connection Started"))

        // Act
        val population = logAnalysisPopulation(
            entries,
            LogPopulationFilter(searchQuery = "  connection  "),
            maxWindow = 5_000,
        )

        // Assert
        assertEquals(1, population.entries.size)
    }

    @Test
    fun `a blank search does not narrow the population`() {
        // Arrange — a whitespace-only query is the user mid-edit, not a filter.
        val entries = buffer(10)

        // Act
        val population = logAnalysisPopulation(entries, LogPopulationFilter(searchQuery = "   "), maxWindow = 5_000)

        // Assert
        assertFalse(LogPopulationFilter(searchQuery = "   ").isActive)
        assertEquals(10, population.entries.size)
    }

    @Test
    fun `isActive reports whether a second pattern scan is needed`() {
        // Arrange / Act / Assert — false means the population is the plain tail
        // of the buffer, so the window scan can be reused.
        assertFalse(LogPopulationFilter().isActive)
        assertFalse(LogPopulationFilter(component = LogComponent.SYNC, componentApplies = false).isActive)
        assertFalse(LogPopulationFilter(component = LogComponent.ALL, componentApplies = true).isActive)
        assertFalse(LogPopulationFilter(dateFilterEnabled = true).isActive)
        assertTrue(LogPopulationFilter(searchQuery = "x").isActive)
        assertTrue(LogPopulationFilter(component = LogComponent.SYNC, componentApplies = true).isActive)
        assertTrue(LogPopulationFilter(dateFilterEnabled = true, dateRangeStartMillis = 1L).isActive)
    }

    // ── The display stage ───────────────────────────────────────────────────

    @Test
    fun `level chips apply on every source, not just the SDK one`() {
        // Arrange — chips used to be wired to the SDK tab only, leaving App
        // Logs / Transports / Connections with no level control at all. The
        // display stage has no notion of source, which is the fix.
        val entries = listOf(
            entry(0, level = DittoLogLevel.Info),
            entry(1, level = DittoLogLevel.Error),
        )

        // Act
        val displayed = logDisplayEntries(
            population = entries,
            filterTab = LogFilterTab.ALL,
            problemIds = emptySet(),
            criticalIds = emptySet(),
            selectedLevels = setOf(DittoLogLevel.Error),
            maxDisplayed = Int.MAX_VALUE,
        )

        // Assert
        assertEquals(listOf(DittoLogLevel.Error), displayed.map { it.level })
    }

    @Test
    fun `level chips are ignored while a non-All tab owns the level`() {
        // Arrange — a stale chip selection must not subtract rows from the tab
        // the user just picked (spec §3).
        val entries = listOf(
            entry(0, level = DittoLogLevel.Error),
            entry(1, level = DittoLogLevel.Info),
        )

        // Act
        val displayed = logDisplayEntries(
            population = entries,
            filterTab = LogFilterTab.ERROR,
            problemIds = emptySet(),
            criticalIds = emptySet(),
            // Chips say "Info only", which would otherwise empty the Errors tab.
            selectedLevels = setOf(DittoLogLevel.Info),
            maxDisplayed = Int.MAX_VALUE,
        )

        // Assert
        assertEquals(1, displayed.size)
        assertEquals(DittoLogLevel.Error, displayed.single().level)
    }

    @Test
    fun `the Problems and Critical tabs select on the scan's id sets`() {
        // Arrange
        val problem = entry(0, level = DittoLogLevel.Debug)
        val critical = entry(1, level = DittoLogLevel.Debug)
        val quiet = entry(2)
        val population = listOf(problem, critical, quiet)

        // Act
        val problems = logDisplayEntries(
            population,
            LogFilterTab.PROBLEM,
            problemIds = setOf(problem.id, critical.id),
            criticalIds = setOf(critical.id),
            selectedLevels = DittoLogLevel.entries.toSet(),
            maxDisplayed = Int.MAX_VALUE,
        )
        val criticals = logDisplayEntries(
            population,
            LogFilterTab.CRITICAL,
            problemIds = setOf(problem.id, critical.id),
            criticalIds = setOf(critical.id),
            selectedLevels = DittoLogLevel.entries.toSet(),
            maxDisplayed = Int.MAX_VALUE,
        )

        // Assert — a DEBUG line can be Critical: severity is a pattern property,
        // not a level.
        assertEquals(setOf(problem.id, critical.id), problems.map { it.id }.toSet())
        assertEquals(listOf(critical.id), criticals.map { it.id })
    }

    @Test
    fun `the render cap keeps the newest rows`() {
        // Arrange
        val entries = buffer(500)

        // Act
        val displayed = logDisplayEntries(
            population = entries,
            filterTab = LogFilterTab.ALL,
            problemIds = emptySet(),
            criticalIds = emptySet(),
            selectedLevels = DittoLogLevel.entries.toSet(),
            maxDisplayed = 200,
        )

        // Assert
        assertEquals(200, displayed.size)
        assertEquals("line-499", displayed.last().message)
    }
}
