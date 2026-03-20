package com.costoda.dittoedgestudio.data

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

/** Pure filter logic tests — no Android or DittoLogger dependencies required. */
class LogEntryFilterTest {

    private fun makeEntry(
        level: DittoLogLevel = DittoLogLevel.Info,
        message: String = "test message",
        component: LogComponent = LogComponent.SYNC,
        source: LogEntrySource = LogEntrySource.DittoSDK,
        timestampMs: Long = System.currentTimeMillis(),
    ) = LogEntry(
        timestamp = Date(timestampMs),
        level = level,
        message = message,
        component = component,
        source = source,
        rawLine = "${level.name}|$message",
    )

    // ── Date range filter ─────────────────────────────────────────────────────

    @Test
    fun `date range filter includes entries inside range`() {
        val start = Date(1_000L)
        val end = Date(3_000L)
        val entry = makeEntry(timestampMs = 2_000L)
        val result = applyDateFilter(listOf(entry), start, end)
        assertEquals(1, result.size)
    }

    @Test
    fun `date range filter excludes entries before range`() {
        val start = Date(2_000L)
        val end = Date(4_000L)
        val entry = makeEntry(timestampMs = 1_000L)
        val result = applyDateFilter(listOf(entry), start, end)
        assertTrue(result.isEmpty())
    }

    @Test
    fun `date range filter excludes entries after range`() {
        val start = Date(1_000L)
        val end = Date(2_000L)
        val entry = makeEntry(timestampMs = 3_000L)
        val result = applyDateFilter(listOf(entry), start, end)
        assertTrue(result.isEmpty())
    }

    @Test
    fun `date range filter is inclusive on both boundaries`() {
        val start = Date(1_000L)
        val end = Date(3_000L)
        val atStart = makeEntry(timestampMs = 1_000L)
        val atEnd = makeEntry(timestampMs = 3_000L)
        val result = applyDateFilter(listOf(atStart, atEnd), start, end)
        assertEquals(2, result.size)
    }

    // ── Level filter ──────────────────────────────────────────────────────────

    @Test
    fun `level filter includes only selected levels`() {
        val entries = listOf(
            makeEntry(level = DittoLogLevel.Error),
            makeEntry(level = DittoLogLevel.Warning),
            makeEntry(level = DittoLogLevel.Info),
        )
        val result = applyLevelFilter(entries, setOf(DittoLogLevel.Error, DittoLogLevel.Warning))
        assertEquals(2, result.size)
        assertTrue(result.all { it.level in setOf(DittoLogLevel.Error, DittoLogLevel.Warning) })
    }

    @Test
    fun `level filter with empty set returns no entries`() {
        val entries = listOf(makeEntry(level = DittoLogLevel.Info))
        val result = applyLevelFilter(entries, emptySet())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `level filter with all levels returns all entries`() {
        val entries = DittoLogLevel.entries.map { makeEntry(level = it) }
        val result = applyLevelFilter(entries, DittoLogLevel.entries.toSet())
        assertEquals(entries.size, result.size)
    }

    // ── Component filter ──────────────────────────────────────────────────────

    @Test
    fun `component filter ALL returns all entries`() {
        val entries = listOf(
            makeEntry(component = LogComponent.SYNC),
            makeEntry(component = LogComponent.STORE),
            makeEntry(component = LogComponent.AUTH),
        )
        val result = applyComponentFilter(entries, LogComponent.ALL)
        assertEquals(3, result.size)
    }

    @Test
    fun `component filter returns only matching component`() {
        val entries = listOf(
            makeEntry(component = LogComponent.SYNC),
            makeEntry(component = LogComponent.STORE),
            makeEntry(component = LogComponent.SYNC),
        )
        val result = applyComponentFilter(entries, LogComponent.SYNC)
        assertEquals(2, result.size)
        assertTrue(result.all { it.component == LogComponent.SYNC })
    }

    // ── Search filter ─────────────────────────────────────────────────────────

    @Test
    fun `search filter is case-insensitive`() {
        val entries = listOf(
            makeEntry(message = "Ditto SYNC started"),
            makeEntry(message = "unrelated log entry"),
        )
        val result = applySearchFilter(entries, "sync started")
        assertEquals(1, result.size)
        assertEquals("Ditto SYNC started", result.first().message)
    }

    @Test
    fun `search filter with empty query returns all entries`() {
        val entries = listOf(makeEntry(), makeEntry(), makeEntry())
        val result = applySearchFilter(entries, "")
        assertEquals(3, result.size)
    }

    @Test
    fun `search filter with no match returns empty list`() {
        val entries = listOf(makeEntry(message = "some log message"))
        val result = applySearchFilter(entries, "XYZ_NOT_FOUND")
        assertTrue(result.isEmpty())
    }

    // ── Combined filters ──────────────────────────────────────────────────────

    @Test
    fun `combined filters apply independently`() {
        val entries = listOf(
            makeEntry(level = DittoLogLevel.Error, message = "auth failure", component = LogComponent.AUTH),
            makeEntry(level = DittoLogLevel.Info, message = "sync ok", component = LogComponent.SYNC),
            makeEntry(level = DittoLogLevel.Error, message = "sync error", component = LogComponent.SYNC),
        )
        var result = applyLevelFilter(entries, setOf(DittoLogLevel.Error))
        result = applyComponentFilter(result, LogComponent.SYNC)
        result = applySearchFilter(result, "error")
        assertEquals(1, result.size)
        assertEquals("sync error", result.first().message)
    }

    // ── Helper filter functions (pure, no Android deps) ───────────────────────

    private fun applyDateFilter(entries: List<LogEntry>, start: Date, end: Date): List<LogEntry> =
        entries.filter { !it.timestamp.before(start) && !it.timestamp.after(end) }

    private fun applyLevelFilter(entries: List<LogEntry>, levels: Set<DittoLogLevel>): List<LogEntry> =
        entries.filter { it.level in levels }

    private fun applyComponentFilter(entries: List<LogEntry>, component: LogComponent): List<LogEntry> =
        if (component == LogComponent.ALL) entries else entries.filter { it.component == component }

    private fun applySearchFilter(entries: List<LogEntry>, query: String): List<LogEntry> =
        if (query.isBlank()) entries else entries.filter { it.message.contains(query, ignoreCase = true) }
}
