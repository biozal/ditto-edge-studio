package com.costoda.dittoedgestudio.data

import com.costoda.dittoedgestudio.data.logging.LogFileParser
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class LogFileParserTest {

    // ── JSONL parsing ─────────────────────────────────────────────────────────

    @Test
    fun `parseJSONL parses entry with fractional seconds`() {
        val json = """{"time":"2026-03-08T14:22:11.456789Z","level":"info","target":"ditto::sync","message":"Sync started"}"""
        val entries = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK)

        assertEquals(1, entries.size)
        val entry = entries.first()
        assertEquals(DittoLogLevel.Info, entry.level)
        assertEquals("Sync started", entry.message)
        assertEquals(LogComponent.SYNC, entry.component)
        assertNotNull(entry.timestamp)
    }

    @Test
    fun `parseJSONL reads 6-digit fractional seconds as microseconds not milliseconds`() {
        // Arrange — every `ditto_logs` record carries 6 fractional digits. Under
        // the old SimpleDateFormat pattern `…ss.SSSSSS'Z'`, `S` means
        // *milliseconds*, so `.784135` was added as 784 135 ms and this instant
        // came back as 20:56:55 — 13m04s late. That corrupted the analytics time
        // range, both histograms, the connection durations and the date filter.
        val json = """{"timestamp":"2026-09-05T20:43:51.784135Z","level":"INFO","message":"starting Ditto..."}"""

        // Act
        val entry = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK).single()

        // Assert — truncated to Date's millisecond resolution.
        assertEquals(Instant.parse("2026-09-05T20:43:51.784Z").toEpochMilli(), entry.timestamp.time)
    }

    @Test
    fun `parseJSONL parses every fractional precision the SDK can emit`() {
        // Arrange — 0, 3, 6 and 9 fractional digits all denote the same second.
        val texts = listOf(
            "2026-09-05T20:43:51Z" to "2026-09-05T20:43:51Z",
            "2026-09-05T20:43:51.784Z" to "2026-09-05T20:43:51.784Z",
            "2026-09-05T20:43:51.784135Z" to "2026-09-05T20:43:51.784Z",
            "2026-09-05T20:43:51.784135926Z" to "2026-09-05T20:43:51.784Z",
        )

        for ((input, expected) in texts) {
            // Act
            val json = """{"timestamp":"$input","level":"INFO","message":"m"}"""
            val entry = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK).single()

            // Assert
            assertEquals(input, Instant.parse(expected).toEpochMilli(), entry.timestamp.time)
        }
    }

    @Test
    fun `parseJSONL parses explicit numeric offsets in both extended and basic form`() {
        // Arrange — `+01:00` and `+0100` denote 19:43:51Z.
        for (input in listOf("2026-09-05T20:43:51.784135+01:00", "2026-09-05T20:43:51.784135+0100")) {
            // Act
            val json = """{"timestamp":"$input","level":"INFO","message":"m"}"""
            val entry = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK).single()

            // Assert
            assertEquals(input, Instant.parse("2026-09-05T19:43:51.784Z").toEpochMilli(), entry.timestamp.time)
        }
    }

    @Test
    fun `parseJSONL reads a timestamp with no zone designator as UTC`() {
        // Arrange — the shape the old isoBasic/isoWithMillis parsers covered via
        // their explicit UTC timeZone.
        val json = """{"timestamp":"2026-09-05T20:43:51.784135","level":"INFO","message":"m"}"""

        // Act
        val entry = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK).single()

        // Assert
        assertEquals(Instant.parse("2026-09-05T20:43:51.784Z").toEpochMilli(), entry.timestamp.time)
    }

    @Test
    fun `parseJSONL parses entry without fractional seconds`() {
        val json = """{"time":"2026-03-08T14:22:11Z","level":"warning","target":"ditto::auth","message":"Token expiring soon"}"""
        val entries = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK)

        assertEquals(1, entries.size)
        val entry = entries.first()
        assertEquals(DittoLogLevel.Warning, entry.level)
        assertEquals("Token expiring soon", entry.message)
        assertEquals(LogComponent.AUTH, entry.component)
    }

    @Test
    fun `parseJSONL defaults to info for unknown level`() {
        val json = """{"time":"2026-03-08T14:22:11Z","level":"unknown_level","message":"Some message"}"""
        val entries = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK)

        assertEquals(1, entries.size)
        assertEquals(DittoLogLevel.Info, entries.first().level)
    }

    @Test
    fun `parseJSONL maps target field to correct LogComponent`() {
        val cases = listOf(
            "ditto::sync" to LogComponent.SYNC,
            "ditto::store" to LogComponent.STORE,
            "ditto::query" to LogComponent.QUERY,
            "ditto::observer" to LogComponent.OBSERVER,
            "ditto::transport::bluetooth" to LogComponent.TRANSPORT,
            "ditto::auth" to LogComponent.AUTH,
        )
        cases.forEach { (target, expected) ->
            val json = """{"time":"2026-03-08T14:22:11Z","level":"info","target":"$target","message":"msg"}"""
            val entry = LogFileParser.parseJSONL(json, LogEntrySource.DittoSDK).firstOrNull()
            assertNotNull("Expected entry for target=$target", entry)
            assertEquals("Expected $expected for target=$target", expected, entry!!.component)
        }
    }

    @Test
    fun `parseJSONL with multiple lines returns all entries`() {
        val content = """
            {"time":"2026-03-08T14:22:11Z","level":"info","message":"First"}
            {"time":"2026-03-08T14:22:12Z","level":"error","message":"Second"}
            {"time":"2026-03-08T14:22:13Z","level":"debug","message":"Third"}
        """.trimIndent()
        val entries = LogFileParser.parseJSONL(content, LogEntrySource.DittoSDK)
        assertEquals(3, entries.size)
        assertEquals(DittoLogLevel.Error, entries[1].level)
    }

    // ── App log parsing ───────────────────────────────────────────────────────

    @Test
    fun `parseRawLogLine parses app log format with tag and timestamp`() {
        // Test Timber-style plain-text parsing by using parseJSONL fallback
        // and the heuristic component detection for a non-JSON line
        val raw = "Info|Ditto sync started for database test-db"
        val entry = LogFileParser.parseRawLogLine(raw, LogEntrySource.DittoSDK)

        assertNotNull(entry)
        assertEquals(DittoLogLevel.Info, entry!!.level)
        assertEquals("Ditto sync started for database test-db", entry.message)
    }

    @Test
    fun `parseRawLogLine returns info for unparseable level`() {
        val raw = "UNKNOWN|Some message"
        val entry = LogFileParser.parseRawLogLine(raw, LogEntrySource.DittoSDK)
        assertNotNull(entry)
        assertEquals(DittoLogLevel.Info, entry!!.level)
    }

    @Test
    fun `parseRawLogLine handles missing pipe separator`() {
        val raw = "Just a plain message without pipe"
        val entry = LogFileParser.parseRawLogLine(raw, LogEntrySource.DittoSDK)
        assertNotNull(entry)
        assertEquals(raw, entry!!.message)
    }

    // ── Component heuristic ───────────────────────────────────────────────────

    @Test
    fun `component heuristic prefers transport operation names over a query substring`() {
        // SwiftUI's `heuristic(from:)` puts four named SDK transport operations —
        // and the bare `tcp`/`awdl` tokens — ahead of `query`, precisely so a
        // long flattened line that happens to mention "query" is not stolen from
        // Transport. Only those probes win; see LogComponentTest for the
        // complementary case where a generic "[transport::…]" tag does NOT beat
        // `query`, on either platform.
        assertEquals(
            LogComponent.TRANSPORT,
            LogComponent.heuristic("add_ble_transport: query_config=default"),
        )
        assertEquals(
            LogComponent.TRANSPORT,
            LogComponent.heuristic("tcp connection dropped while query pending"),
        )
    }

    @Test
    fun `component from target maps correctly`() {
        assertEquals(LogComponent.SYNC, LogComponent.from("ditto::sync"))
        assertEquals(LogComponent.STORE, LogComponent.from("ditto::store::writes"))
        assertEquals(LogComponent.QUERY, LogComponent.from("ditto::query::parser"))
        assertEquals(LogComponent.TRANSPORT, LogComponent.from("ditto_discovery_mdns"))
        assertEquals(LogComponent.OTHER, LogComponent.from("ditto::unknown"))
    }

    // ── Level string parsing ──────────────────────────────────────────────────

    @Test
    fun `parseLevelString handles all standard aliases`() {
        val cases = mapOf(
            "error" to DittoLogLevel.Error,
            "err" to DittoLogLevel.Error,
            "warning" to DittoLogLevel.Warning,
            "warn" to DittoLogLevel.Warning,
            "info" to DittoLogLevel.Info,
            "i" to DittoLogLevel.Info,
            "debug" to DittoLogLevel.Debug,
            "dbg" to DittoLogLevel.Debug,
            "verbose" to DittoLogLevel.Verbose,
            "verb" to DittoLogLevel.Verbose,
            "trace" to DittoLogLevel.Verbose,
        )
        cases.forEach { (input, expected) ->
            assertEquals("Failed for input '$input'", expected, LogFileParser.parseLevelString(input))
        }
    }

    @Test
    fun `parseLevelString defaults to info for unknown input`() {
        assertEquals(DittoLogLevel.Info, LogFileParser.parseLevelString("xyz"))
        assertEquals(DittoLogLevel.Info, LogFileParser.parseLevelString(""))
    }
}
