package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.LogPattern
import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.costoda.dittoedgestudio.domain.model.parseLevelFilter
import com.costoda.dittoedgestudio.domain.model.severityLabel
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LogPatternEngineTest {

    private fun entry(
        level: DittoLogLevel = DittoLogLevel.Info,
        message: String = "hello",
        component: LogComponent = LogComponent.SYNC,
    ) = LogEntry(
        timestamp = Date(0),
        level = level,
        message = message,
        component = component,
        source = LogEntrySource.DittoSDK,
        rawLine = "",
    )

    private fun patternOf(
        key: String,
        pattern: String,
        severity: Int = 3,
        recommendation: String = "fix it",
        levelFilter: String? = null,
        tagFilter: String? = null,
        userTag: String? = null,
        source: PatternSource = PatternSource.BUNDLED,
    ) = LogPattern(
        key = key,
        body = LogPatternBody(pattern, severity, recommendation, levelFilter, tagFilter, userTag),
        severity = severity,
        levelFilter = parseLevelFilter(levelFilter),
        source = source,
    )

    // ── Level filter token parsing ──────────────────────────────────────────

    @Test
    fun `level filter tokens map to SDK levels including extension spellings`() {
        assertNull(parseLevelFilter(null))
        assertNull(parseLevelFilter(""))
        assertEquals(DittoLogLevel.Error, parseLevelFilter("error"))
        assertEquals(DittoLogLevel.Warning, parseLevelFilter("warn"))
        assertEquals(DittoLogLevel.Warning, parseLevelFilter("warning"))
        assertEquals(DittoLogLevel.Info, parseLevelFilter("info"))
        assertEquals(DittoLogLevel.Debug, parseLevelFilter("debug"))
        assertEquals(DittoLogLevel.Verbose, parseLevelFilter("trace"))
        assertEquals(DittoLogLevel.Verbose, parseLevelFilter("verbose"))
        assertNull(parseLevelFilter("bogus"))
    }

    @Test
    fun `level filter parsing is case-insensitive`() {
        assertEquals(DittoLogLevel.Error, parseLevelFilter("ERROR"))
        assertEquals(DittoLogLevel.Warning, parseLevelFilter("Warn"))
    }

    // ── Scan semantics ──────────────────────────────────────────────────────

    @Test
    fun `message matching is case-insensitive`() {
        val engine = LogPatternEngine(mapOf("p" to patternOf("p", "deadlock")))
        val matches = engine.scan(entry(message = "possible DEADLOCK detected"))
        assertEquals(1, matches.size)
        assertEquals("p", matches[0].key)
    }

    @Test
    fun `level filter is an exact equality, not at-least`() {
        val patterns = mapOf(
            "err" to patternOf("err", "deadlock", levelFilter = "error"),
            "wrn" to patternOf("wrn", "deadlock", levelFilter = "warn"),
        )
        val engine = LogPatternEngine(patterns)

        // An ERROR line must not fire the WARN-scoped variant.
        val errorMatches = engine.scan(entry(level = DittoLogLevel.Error, message = "deadlock elapsed"))
        assertEquals(listOf("err"), errorMatches.map { it.key })

        val warnMatches = engine.scan(entry(level = DittoLogLevel.Warning, message = "deadlock elapsed"))
        assertEquals(listOf("wrn"), warnMatches.map { it.key })
    }

    @Test
    fun `tag filter matches against component display name and is case-sensitive`() {
        val engine = LogPatternEngine(
            mapOf("p" to patternOf("p", "msg", tagFilter = "Sync")),
        )
        assertTrue(engine.scan(entry(message = "msg here", component = LogComponent.SYNC)).isNotEmpty())
        assertTrue(engine.scan(entry(message = "msg here", component = LogComponent.STORE)).isEmpty())
    }

    @Test
    fun `user tag is carried on the compiled pattern`() {
        val engine = LogPatternEngine(
            mapOf("p" to patternOf("p", "msg", userTag = "auth-flow")),
        )
        assertEquals("auth-flow", engine.scan(entry(message = "msg here"))[0].userTag)
    }

    @Test
    fun `scanAll returns chronological matches across entries`() {
        val engine = LogPatternEngine(mapOf("p" to patternOf("p", "err")))
        val entries = listOf(
            entry(message = "nothing"),
            entry(message = "err one"),
            entry(message = "err two"),
        )
        val matches = engine.scanAll(entries)
        assertEquals(2, matches.size)
        assertEquals("err one", matches[0].entry.message)
        assertEquals("err two", matches[1].entry.message)
    }

    @Test
    fun `scanAll caps the window to the newest maxEntries`() {
        val engine = LogPatternEngine(mapOf("p" to patternOf("p", "hit")))
        val entries = (1..10).map { entry(message = if (it <= 5) "hit $it" else "miss $it") }
        // cap at 5: only the LAST 5 entries are scanned, which are all "miss".
        assertTrue(engine.scanAll(entries, maxEntries = 5).isEmpty())
        // Full scan finds the 5 hits.
        assertEquals(5, engine.scanAll(entries, maxEntries = 10).size)
    }

    @Test
    fun `editor test-line matcher respects pattern, level and tag filters`() {
        val engine = LogPatternEngine(emptyMap())
        val body = LogPatternBody("Query too big", 5, "split the query", levelFilter = "warn", tagFilter = "Sync")
        assertTrue(
            engine.matches(body, DittoLogLevel.Warning, LogComponent.SYNC.displayName, "Query too big. It exceeded"),
        )
        assertFalse(
            engine.matches(body, DittoLogLevel.Error, LogComponent.SYNC.displayName, "Query too big. It exceeded"),
        )
        assertFalse(
            engine.matches(body, DittoLogLevel.Warning, LogComponent.STORE.displayName, "Query too big. It exceeded"),
        )
        assertFalse(
            engine.matches(body, DittoLogLevel.Warning, LogComponent.SYNC.displayName, "unrelated"),
        )
    }

    // ── Validation (ReDoS guards) ───────────────────────────────────────────

    @Test
    fun `blank key is rejected`() {
        assertNotNull(LogPatternEngine.rejectReason("", validBody(), PatternSource.BUNDLED))
    }

    @Test
    fun `empty pattern and recommendation are rejected`() {
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(pattern = ""), PatternSource.BUNDLED))
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(recommendation = ""), PatternSource.BUNDLED))
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(recommendation = "  "), PatternSource.BUNDLED))
    }

    @Test
    fun `severity outside 1 to 5 is rejected`() {
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(severity = 0), PatternSource.BUNDLED))
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(severity = 6), PatternSource.BUNDLED))
        assertNull(LogPatternEngine.rejectReason("k", validBody(severity = 1), PatternSource.BUNDLED))
        assertNull(LogPatternEngine.rejectReason("k", validBody(severity = 5), PatternSource.BUNDLED))
    }

    @Test
    fun `user patterns are rejected beyond the length cap`() {
        val longPattern = "a".repeat(LogPatternEngine.MAX_USER_PATTERN_LENGTH + 1)
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(pattern = longPattern), PatternSource.USER))
        assertNull(LogPatternEngine.rejectReason("k", validBody(pattern = longPattern), PatternSource.BUNDLED))
    }

    @Test
    fun `nested quantifiers are rejected for user patterns only`() {
        val redos = validBody(pattern = "(a+)+")
        assertEquals(
            "pattern nests a quantifier inside a quantified group, which can backtrack exponentially",
            LogPatternEngine.rejectReason("k", redos, PatternSource.USER),
        )
        assertNull(LogPatternEngine.rejectReason("k", redos, PatternSource.BUNDLED))
    }

    @Test
    fun `invalid regex is rejected`() {
        assertNotNull(LogPatternEngine.rejectReason("k", validBody(pattern = "(["), PatternSource.USER))
    }

    @Test
    fun `unknown level_filter token is rejected`() {
        val body = LogPatternBody("boom", 3, "fix it", levelFilter = "critikal")
        assertEquals(
            "unknown level_filter 'critikal' (expected error|warning|info|debug|verbose)",
            LogPatternEngine.rejectReason("k", body, PatternSource.USER),
        )
        assertNull(
            LogPatternEngine.rejectReason(
                "k",
                LogPatternBody("boom", 3, "fix it", levelFilter = "error"),
                PatternSource.USER,
            ),
        )
    }

    @Test
    fun `invalid tag_filter regex is rejected`() {
        val body = LogPatternBody("boom", 3, "fix it", tagFilter = "([")
        assertTrue(
            LogPatternEngine.rejectReason("k", body, PatternSource.BUNDLED)!!
                .startsWith("tag_filter is not a valid regex"),
        )
    }

    @Test
    fun `nested quantifier tag_filter is rejected for user patterns only`() {
        val body = LogPatternBody("boom", 3, "fix it", tagFilter = "(a+)+")
        assertTrue(
            LogPatternEngine.rejectReason("k", body, PatternSource.USER)!!
                .startsWith("tag_filter nests a quantifier"),
        )
        assertNull(LogPatternEngine.rejectReason("k", body, PatternSource.BUNDLED))
    }

    @Test
    fun `user tag is trimmed at compile time`() {
        val pattern = LogPattern(
            key = "p",
            body = LogPatternBody("msg", 3, "fix it", userTag = "  auth-flow  "),
            severity = 3,
            levelFilter = null,
            source = PatternSource.USER,
        )
        val engine = LogPatternEngine(mapOf("p" to pattern))
        assertEquals("auth-flow", engine.scan(entry(message = "a msg"))[0].userTag)
    }

    @Test
    fun `bundled catalog default loads and scans a known signature`() {
        // Mirrors the extension's deadlock_critical bundled pattern.
        val body = LogPatternBody(
            pattern = "(?:deadlock|write transaction).*elapsed",
            severity = 5,
            recommendation = "Possible deadlock.",
            levelFilter = "error",
        )
        val engine = LogPatternEngine(
            mapOf("deadlock_critical" to LogPattern("deadlock_critical", body, 5, DittoLogLevel.Error, PatternSource.BUNDLED)),
        )
        val matches = engine.scan(
            entry(level = DittoLogLevel.Error, message = "write transaction blocked; elapsed=51000ms"),
        )
        assertEquals(1, matches.size)
        assertEquals(5, matches[0].severity)
        assertEquals(severityLabel(5), "CRITICAL")
    }

    // ── Bundled-catalog fixtures (ported from the VS Code extension's
    //    src/logAnalyzer/patterns/__fixtures__) ──────────────────────────────

    private fun catalogEngine(): LogPatternEngine {
        // JVM unit tests run with the module dir as working directory.
        val raw = java.io.File("src/main/assets/problem_patterns.json").readText()
        val bodies: Map<String, LogPatternBody> =
            kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                .decodeFromString(raw)
        val patterns = bodies.mapValues { (key, body) ->
            LogPattern(key, body, body.severity, parseLevelFilter(body.levelFilter), PatternSource.BUNDLED)
        }
        return LogPatternEngine(patterns)
    }

    private fun sdkEntry(level: DittoLogLevel, message: String) = entry(
        level = level,
        message = message,
        component = LogComponent.SYNC,
    )

    @Test
    fun `catalog contains the four v5-1 replication-eviction patterns`() {
        val engine = catalogEngine()
        val keys = engine.compiled.map { it.key }
        assertEquals(13, keys.size)
        for (k in listOf(
            "replication_metadata_corrupt_recovery",
            "replication_consecutive_resets",
            "replication_reset_local_trigger",
            "post_eviction_cleanup_frequent",
        )) {
            assertTrue("$k missing from catalog", keys.contains(k))
        }
    }

    @Test
    fun `fixture — metadata corrupt recovery matches at WARN`() {
        val engine = catalogEngine()
        val message = "session metadata database was corrupt on open; deleting and " +
            "reinitializing this peer's metadata, then retrying " +
            "{\"remote.peer_id\":\"peer-9f2a\",\"error\":\"corruption: checksum mismatch\"}"
        assertEquals(
            listOf("replication_metadata_corrupt_recovery"),
            engine.scan(sdkEntry(DittoLogLevel.Warning, message)).map { it.key },
        )
        assertTrue(engine.scan(sdkEntry(DittoLogLevel.Info, message)).isEmpty())
    }

    @Test
    fun `fixture — consecutive resets match at WARN, first-reset INFO does not`() {
        val engine = catalogEngine()
        val warnMessage = "resetting replication state with remote peer; sync performance " +
            "may be temporarily degraded {\"consecutive_resets\":3}"
        val infoMessage = "resetting replication state with remote peer; sync performance " +
            "may be temporarily degraded"
        assertEquals(
            listOf("replication_consecutive_resets"),
            engine.scan(sdkEntry(DittoLogLevel.Warning, warnMessage)).map { it.key },
        )
        assertTrue(engine.scan(sdkEntry(DittoLogLevel.Info, infoMessage)).isEmpty())
    }

    @Test
    fun `fixture — local-trigger reset matches at WARN, benign INFO does not`() {
        val engine = catalogEngine()
        val warnMessage = "replication reset was triggered by local peer {\"error\":\"metadata was corrupt on open\"}"
        val infoMessage = "replication reset was triggered by local peer {\"error\":\"session forgotten\"}"
        assertEquals(
            listOf("replication_reset_local_trigger"),
            engine.scan(sdkEntry(DittoLogLevel.Warning, warnMessage)).map { it.key },
        )
        assertTrue(engine.scan(sdkEntry(DittoLogLevel.Info, infoMessage)).isEmpty())
    }

    @Test
    fun `fixture — post-eviction cleanup matches at INFO (no level filter)`() {
        val engine = catalogEngine()
        val message = "post-eviction session cleanup is running too frequently, which may " +
            "cause excessive local overhead {\"run_count\":3,\"window_ms\":30000}"
        assertEquals(
            listOf("post_eviction_cleanup_frequent"),
            engine.scan(sdkEntry(DittoLogLevel.Info, message)).map { it.key },
        )
    }

    private fun validBody(
        pattern: String = "boom",
        severity: Int = 3,
        recommendation: String = "fix it",
    ) = LogPatternBody(pattern, severity, recommendation)
}
