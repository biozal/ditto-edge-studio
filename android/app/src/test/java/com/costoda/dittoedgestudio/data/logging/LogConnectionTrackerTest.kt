package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import kotlin.math.roundToLong
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors `SwiftUI/EdgeStudioUnitTests/Logging/LogConnectionTrackerTests.swift`,
 * plus the `span.connection_id` cases the SwiftUI port does not yet handle.
 */
class LogConnectionTrackerTest {

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun entry(
        message: String,
        atSeconds: Double,
        rawLine: String? = null,
        level: DittoLogLevel = DittoLogLevel.Info,
    ) = LogEntry(
        timestamp = Date((atSeconds * 1000).roundToLong()),
        level = level,
        message = message,
        component = LogComponent.TRANSPORT,
        source = LogEntrySource.DittoSDK,
        rawLine = rawLine ?: message,
    )

    /** The flattened encoding the live `DittoLogger` callback delivers. */
    private fun flatLine(
        verb: String,
        remote: String = "pkRemoteA",
        role: String = "Client",
        transport: String = "Awdl",
        connectionId: String = "9",
    ) = "physical connection $verb remote=$remote role=$role " +
        "transport_type=$transport connection_id=$connectionId"

    /**
     * The JSON Lines encoding the SDK writes into `ditto_logs` `.log`, which
     * [LogFileParser] puts on [LogEntry.rawLine] while `message` keeps only the
     * bare verb. Shape copied from a real capture.
     */
    private fun jsonEntry(
        verb: String,
        atSeconds: Double,
        remote: String = "pkRemoteA",
        role: String = "Client",
        transport: String = "Awdl",
        connectionId: String? = "9",
        spanConnectionId: String? = null,
    ): LogEntry {
        val message = "physical connection $verb"
        val topLevelId = connectionId?.let { """"connection_id":"$it",""" } ?: ""
        val span = if (spanConnectionId != null) {
            """"span":{"connection_id":"$spanConnectionId","remote_peer":"pkRemoteA","name":"physical_connection"},"""
        } else {
            """"span":{"name":"transport_connection_manager_finalizing"},"""
        }
        val raw = """{"timestamp":"2026-09-05T20:44:02.068216Z","level":"INFO","message":"$message",""" +
            """"remote":"$remote","role":"$role","transport_type":"$transport",""" +
            topLevelId + span + """"target":"ditto_multiplexer::connection"}"""
        return entry(message, atSeconds, rawLine = raw)
    }

    // ── Extraction: flattened (live) encoding ───────────────────────────────

    @Test
    fun `extracts fields from the flattened live-callback encoding`() {
        // Arrange
        val logEntry = entry(flatLine("started", transport = "Websocket"), atSeconds = 100.0)

        // Act
        val event = LogConnectionEvent.extract(logEntry)

        // Assert
        assertEquals(LogConnectionEvent.Kind.STARTED, event?.kind)
        assertEquals("pkRemoteA", event?.remotePeer)
        assertEquals("Client", event?.role)
        assertEquals("Websocket", event?.transport)
        assertEquals("9", event?.connectionId)
    }

    @Test
    fun `a flattened line with no fields reports unknowns rather than failing`() {
        // Act
        val event = LogConnectionEvent.extract(entry("physical connection started", atSeconds = 1.0))

        // Assert
        assertEquals(LogConnectionEvent.Kind.STARTED, event?.kind)
        assertEquals("unknown", event?.remotePeer)
        assertNull(event?.connectionId)
    }

    // ── Extraction: JSON Lines (historical) encoding ────────────────────────

    @Test
    fun `extracts fields from the JSON Lines file encoding`() {
        // Arrange — the message body carries no key=value pairs at all here, so
        // a regex-only extractor would report every field as "unknown".
        val logEntry = jsonEntry("started", atSeconds = 100.0, transport = "Tcp", connectionId = "11")

        // Act
        val event = LogConnectionEvent.extract(logEntry)

        // Assert
        assertEquals(LogConnectionEvent.Kind.STARTED, event?.kind)
        assertEquals("pkRemoteA", event?.remotePeer)
        assertEquals("Tcp", event?.transport)
        assertEquals("11", event?.connectionId)
    }

    @Test
    fun `connection id is read from the nested span when the top-level key is absent`() {
        // Arrange — measured over five real captures, 127 of 156
        // `physical connection …` records carry the id only as
        // `span.connection_id`. Reading only the top-level key drops the exact
        // match key on the majority of records.
        val logEntry = jsonEntry("started", atSeconds = 100.0, connectionId = null, spanConnectionId = "12")

        // Act
        val event = LogConnectionEvent.extract(logEntry)

        // Assert
        assertEquals("12", event?.connectionId)
    }

    @Test
    fun `the top-level connection id wins over the span copy`() {
        // Arrange
        val logEntry = jsonEntry("ended", atSeconds = 100.0, connectionId = "8", spanConnectionId = "12")

        // Act & Assert
        assertEquals("8", LogConnectionEvent.extract(logEntry)?.connectionId)
    }

    @Test
    fun `a span-only session pairs across the two encodings`() {
        // Arrange — a JSON `started` carrying only `span.connection_id` must
        // still pair with a later flattened `ended`.
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(jsonEntry("started", atSeconds = 10.0, connectionId = null, spanConnectionId = "42"))
        tracker.consume(entry(flatLine("ended", connectionId = "42"), atSeconds = 22.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(12.0, tracker.closedSessions.first().duration!!, 0.0001)
    }

    @Test
    fun `a numeric connection id is read as a string`() {
        // Arrange — every capture inspected encodes it as a string, but a
        // numeric encoding must not silently drop the best match key.
        val raw = """{"timestamp":"2026-09-05T20:44:02.068216Z","level":"INFO",""" +
            """"message":"physical connection started","remote":"pkRemoteA","role":"Client",""" +
            """"transport_type":"Awdl","connection_id":9}"""

        // Act
        val event = LogConnectionEvent.extract(entry("physical connection started", 1.0, rawLine = raw))

        // Assert
        assertEquals("9", event?.connectionId)
    }

    // ── Records that are not lifecycle edges ────────────────────────────────

    @Test
    fun `non-connection lines produce no event`() {
        assertNull(LogConnectionEvent.extract(entry("Notifying a database change", 1.0)))
        assertNull(LogConnectionEvent.extract(entry("Mesh chooser requesting connection", 1.0)))
    }

    @Test
    fun `the extended-info duplicate is ignored so closes are not double counted`() {
        // The SDK emits a DEBUG "physical connection ended (extended info)"
        // record alongside the INFO one; counting both would close each session
        // twice and inflate the durations buckets.
        val logEntry = entry("physical connection ended (extended info)", 5.0, level = DittoLogLevel.Debug)
        assertNull(LogConnectionEvent.extract(logEntry))
    }

    @Test
    fun `shutting down is not treated as a lifecycle edge`() {
        assertNull(LogConnectionEvent.extract(entry("Physical connection shutting down", 5.0)))
    }

    // ── Pairing ─────────────────────────────────────────────────────────────

    @Test
    fun `pairs start and end into a closed session with a duration`() {
        // Arrange
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started"), 100.0))
        tracker.consume(entry(flatLine("ended"), 130.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(30.0, tracker.closedSessions.first().duration!!, 0.0001)
        assertEquals("Awdl", tracker.closedSessions.first().transport)
        assertEquals(0, tracker.unmatchedEnds)
    }

    @Test
    fun `an end with no matching start is counted not paired`() {
        // Arrange
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("ended"), 130.0))

        // Assert
        assertTrue(tracker.closedSessions.isEmpty())
        assertEquals(1, tracker.unmatchedEnds)
    }

    @Test
    fun `a start with no end stays open and has no duration`() {
        // Arrange
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started"), 100.0))

        // Assert
        assertTrue(tracker.closedSessions.isEmpty())
        assertEquals(1, tracker.sessions.size)
        assertNull(tracker.sessions.first().duration)
    }

    @Test
    fun `a reused connection id pairs with the most recent open session`() {
        // Arrange — the SDK reuses connection ids, so first-match (FIFO) pairing
        // would close the older session and report the wrong duration for both.
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started", connectionId = "8"), 100.0))
        tracker.consume(entry(flatLine("started", connectionId = "8"), 200.0))
        tracker.consume(entry(flatLine("ended", connectionId = "8"), 210.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(10.0, tracker.closedSessions.first().duration!!, 0.0001)
    }

    @Test
    fun `distinct connection ids do not cross-pair`() {
        // Arrange
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started", connectionId = "1"), 100.0))
        tracker.consume(entry(flatLine("started", connectionId = "2"), 110.0))
        tracker.consume(entry(flatLine("ended", connectionId = "1"), 150.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals("1", tracker.closedSessions.first().connectionId)
        assertEquals(50.0, tracker.closedSessions.first().duration!!, 0.0001)
        assertEquals(2, tracker.sessions.size) // one closed, one still open
    }

    @Test
    fun `sessions without a connection id fall back to remote and role`() {
        // Arrange — pre-`connection_id` log lines.
        val tracker = LogConnectionTracker()
        val started = "physical connection started remote=pkRemoteA role=Client transport_type=Awdl"
        val ended = "physical connection ended remote=pkRemoteA role=Client transport_type=Awdl"

        // Act
        tracker.consume(entry(started, 100.0))
        tracker.consume(entry(ended, 106.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(6.0, tracker.closedSessions.first().duration!!, 0.0001)
    }

    @Test
    fun `both encodings pair with each other`() {
        // Arrange — a panel opened mid-session reads historical JSON lines and
        // then live flattened ones; a session must be able to span the two.
        val tracker = LogConnectionTracker()

        // Act
        tracker.consume(jsonEntry("started", atSeconds = 100.0, connectionId = "7"))
        tracker.consume(entry(flatLine("ended", connectionId = "7"), 145.0))

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(45.0, tracker.closedSessions.first().duration!!, 0.0001)
    }

    // ── Reinit ──────────────────────────────────────────────────────────────

    @Test
    fun `a reinit closes every open session at that instant`() {
        // Arrange
        val tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started", connectionId = "1"), 100.0))
        tracker.consume(entry(flatLine("started", connectionId = "2"), 110.0))

        // Act — the flattened encoding the live callback delivers.
        tracker.consume(entry("ditto_init: starting Ditto... sdk.version=5.1.0", 200.0))

        // Assert
        assertEquals(2, tracker.closedSessions.size)
        assertEquals(listOf(Date(200_000)), tracker.reinits)
        assertTrue(tracker.closedSessions.all { it.end == Date(200_000) })
    }

    @Test
    fun `a started with no ended is closed by the next reinit`() {
        // Arrange — the defect this test pins. `ditto_init` fires when the user
        // switches databases, not when the app dies, so a connection that was
        // still open genuinely lasted right up to the init. Measured over the
        // real captures: 28 sessions across 14 inits were in exactly this state,
        // the longest of them open for 22.9 hours. While the re-init was
        // suppressed they never closed, never got a duration, and never entered
        // the Connection Durations histogram.
        val tracker = LogConnectionTracker()
        tracker.consume(jsonEntry("started", atSeconds = 0.0, connectionId = "1"))

        // Act — the JSON Lines encoding of the SDK's init record. It has a
        // `message`, so the message-scoped probe below sees "starting Ditto".
        val raw = """{"timestamp":"2026-09-05T20:43:51.793602Z","level":"INFO",""" +
            """"message":"starting Ditto...","app_id":"151d9b8a-f2a0-4d35-a037-6687df66be4a",""" +
            """"sdk.platform":"macOS","sdk.language":"Swift","sdk.version":"5.1.0"}"""
        tracker.consume(entry("starting Ditto...", 82_296.0, rawLine = raw))

        // Assert — one closed session, 22.86 h long, and nothing left open.
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(82_296.0, tracker.closedSessions.single().duration!!, 0.0001)
        assertEquals(listOf(Date(82_296_000)), tracker.reinits)
        assertTrue(tracker.sessions.none { it.end == null })
    }

    @Test
    fun `ditto_init inside a path value is not a reinit`() {
        // Arrange — in the JSON encoding `ditto_init` appears inside `path`
        // values of unrelated records (19 such lines in one 3.5k-line capture).
        // Matching the whole raw line would close every open session on each.
        val tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started"), 100.0))
        val raw = """{"timestamp":"2026-09-05T20:31:14.181952Z","level":"DEBUG",""" +
            """"message":"removing update file","path":"ditto_init/inbound_45814",""" +
            """"target":"ditto_sync_docs::documents_peer"}"""

        // Act
        tracker.consume(entry("removing update file", 150.0, rawLine = raw, level = DittoLogLevel.Debug))

        // Assert
        assertTrue(tracker.reinits.isEmpty())
        assertTrue(tracker.closedSessions.isEmpty())
    }

    @Test
    fun `ditto_init inside a span name is not a reinit when the record has no message`() {
        // Arrange — 22 records across the real captures carry no `message` key at
        // all. LogFileParser then falls back to putting the *whole raw JSON line*
        // in `LogEntry.message`, which drags `span.name` into it. This DEBUG
        // record does accompany a real init, but it is not the init marker — the
        // `starting Ditto...` INFO record 5–24 ms later is, and it is the one
        // that fires. Keying on this record instead would miss 3 of the 14 real
        // inits, which is why the probe does not use it.
        val raw = """{"timestamp":"2026-09-05T20:43:51.784135Z","level":"DEBUG","auto_vacuum":2,""" +
            """"backend":"sqlite3","target":"ditto_backend_sqlite3::builder",""" +
            """"span":{"name":"ditto_init"},"spans":[{"name":"ditto_init"}],"threadId":"ThreadId(16)"}"""
        val tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started"), 100.0))

        // Act — message == rawLine, exactly as LogFileParser produces it.
        tracker.consume(entry(raw, 150.0, rawLine = raw, level = DittoLogLevel.Debug))

        // Assert
        assertNull(LogConnectionEvent.extract(entry(raw, 150.0, rawLine = raw)))
        assertTrue(tracker.reinits.isEmpty())
        assertTrue(tracker.closedSessions.isEmpty())
    }

    @Test
    fun `a message-less JSON record is not a connection event either`() {
        // Arrange — the same fallback would otherwise let a `span` value
        // containing "physical connection" masquerade as a lifecycle edge.
        val raw = """{"timestamp":"2026-09-05T20:36:01.846717Z","level":"DEBUG","error":"ShutDown",""" +
            """"target":"ditto_multiplexer::connection",""" +
            """"span":{"connection_id":"12","name":"physical connection started"}}"""

        // Act & Assert
        assertNull(LogConnectionEvent.extract(entry(raw, 5.0, rawLine = raw, level = DittoLogLevel.Debug)))
    }

    // ── Reset ───────────────────────────────────────────────────────────────

    @Test
    fun `reset clears every list so Clear cannot resurrect old sessions`() {
        // Arrange
        val tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started"), 100.0))
        tracker.consume(entry(flatLine("ended"), 130.0))
        tracker.consume(entry("ditto_init: starting Ditto...", 140.0))
        tracker.consume(entry(flatLine("ended", connectionId = "99"), 150.0))

        // Act
        tracker.reset()

        // Assert
        assertTrue(tracker.sessions.isEmpty())
        assertTrue(tracker.closedSessions.isEmpty())
        assertTrue(tracker.reinits.isEmpty())
        assertEquals(0, tracker.unmatchedEnds)
    }

    // ── Bounds ──────────────────────────────────────────────────────────────

    @Test
    fun `open sessions are capped so an unterminated start cannot leak`() {
        // Arrange — a `started` whose `ended` never arrives (killed process,
        // truncated log) would otherwise grow this list without limit.
        val tracker = LogConnectionTracker()
        val overflow = LogConnectionTracker.SESSION_HISTORY_CAP * 2 + 10

        // Act
        repeat(overflow) { index ->
            tracker.consume(entry(flatLine("started", connectionId = "$index"), index.toDouble()))
        }

        // Assert
        assertTrue(tracker.sessions.size <= LogConnectionTracker.SESSION_HISTORY_CAP * 2)
        // The newest sessions are the ones retained.
        assertEquals("${overflow - 1}", tracker.sessions.last().connectionId)
    }

    @Test
    fun `closed sessions are capped`() {
        // Arrange
        val tracker = LogConnectionTracker()
        val overflow = LogConnectionTracker.SESSION_HISTORY_CAP * 2 + 10

        // Act
        repeat(overflow) { index ->
            tracker.consume(entry(flatLine("started", connectionId = "$index"), index.toDouble()))
            tracker.consume(entry(flatLine("ended", connectionId = "$index"), index + 0.5))
        }

        // Assert
        assertTrue(tracker.closedSessions.size <= LogConnectionTracker.SESSION_HISTORY_CAP * 2)
    }

    @Test
    fun `the reinit list is capped`() {
        // Arrange
        val tracker = LogConnectionTracker()
        val overflow = LogConnectionTracker.SESSION_HISTORY_CAP * 2 + 10

        // Act
        repeat(overflow) { index ->
            tracker.consume(entry("ditto_init: starting Ditto...", index.toDouble()))
        }

        // Assert
        assertTrue(tracker.reinits.size <= LogConnectionTracker.SESSION_HISTORY_CAP * 2)
    }

    // ── Batch ───────────────────────────────────────────────────────────────

    @Test
    fun `track builds a tracker from a whole buffer in order`() {
        // Arrange
        val entries = listOf(
            entry(flatLine("started", connectionId = "1"), 10.0),
            entry("unrelated chatter", 12.0),
            entry(flatLine("ended", connectionId = "1"), 14.0),
        )

        // Act
        val tracker = LogConnectionTracker.track(entries)

        // Assert
        assertEquals(1, tracker.closedSessions.size)
        assertEquals(4.0, tracker.closedSessions.first().duration!!, 0.0001)
    }
}
