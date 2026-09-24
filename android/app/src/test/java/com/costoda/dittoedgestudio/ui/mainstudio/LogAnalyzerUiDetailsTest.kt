package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.data.logging.LogEntryContext
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import com.costoda.dittoedgestudio.data.logging.sdkLogLevelConfigValue
import com.costoda.dittoedgestudio.data.logging.sdkLogLevelFromConfigValue

/**
 * Small parity details of the Log Analyzer UI that each carried a divergence
 * from the SwiftUI reference.
 */
class LogAnalyzerUiDetailsTest {

    private fun entry(message: String, raw: String = message) = LogEntry(
        timestamp = Date(0),
        level = DittoLogLevel.Info,
        message = message,
        component = LogComponent.SYNC,
        source = LogEntrySource.DittoSDK,
        rawLine = raw,
    )

    // ── Badge formatting ────────────────────────────────────────────────────

    @Test
    fun `badges render the full number`() {
        // Arrange / Act / Assert — SwiftUI renders 5000. Abbreviating to "5.0k"
        // made a full 5 000-entry analysis window indistinguishable from a
        // nearly-full 4 950 one, which is exactly what the badge is for.
        assertEquals("0", formatBadgeCount(0))
        assertEquals("999", formatBadgeCount(999))
        assertEquals("4950", formatBadgeCount(4_950))
        assertEquals("5000", formatBadgeCount(5_000))
        assertEquals("120000", formatBadgeCount(120_000))
    }

    // ── Copy With Context ───────────────────────────────────────────────────

    @Test
    fun `copy with context joins before, focused and after raw lines`() {
        // Arrange — SwiftUI: `context.before + [entry] + context.after`, mapped
        // over rawLine and newline-joined.
        val focused = entry("focused", raw = """{"message":"focused"}""")
        val context = LogEntryContext(
            before = listOf(entry("b1", raw = "raw-b1"), entry("b2", raw = "raw-b2")),
            after = listOf(entry("a1", raw = "raw-a1")),
        )

        // Act
        val text = copyWithContextText(focused, context)

        // Assert
        assertEquals(
            listOf("raw-b1", "raw-b2", """{"message":"focused"}""", "raw-a1"),
            text.split("\n"),
        )
    }

    @Test
    fun `copy with context uses raw lines, not parsed messages`() {
        // Arrange — the JSON-Lines encoding keeps remote / role / transport_type
        // beside the message rather than inside it, so pasting parsed messages
        // would drop what the reader needs.
        val focused = entry(
            "physical connection started",
            raw = """{"message":"physical connection started","transport_type":"Awdl"}""",
        )

        // Act
        val text = copyWithContextText(focused, LogEntryContext.EMPTY)

        // Assert
        assertEquals(focused.rawLine, text)
    }

    @Test
    fun `copy with context degrades to the focused line when there is no context`() {
        // Arrange / Act
        val focused = entry("alone")

        // Assert — an empty clipboard would be worse than a one-line one.
        assertEquals("alone", copyWithContextText(focused, LogEntryContext.EMPTY))
    }

    // ── Persisted SDK log level ─────────────────────────────────────────────

    @Test
    fun `every log level round-trips through the stored config value`() {
        // Arrange / Act / Assert — the vocabulary is fixed by the Database
        // Editor's dropdown and by rows already in the Room database.
        DittoLogLevel.entries.forEach { level ->
            assertEquals(level, sdkLogLevelFromConfigValue(sdkLogLevelConfigValue(level)))
        }
    }

    @Test
    fun `stored config values match the database editor's vocabulary`() {
        // Arrange / Act / Assert
        assertEquals("error", sdkLogLevelConfigValue(DittoLogLevel.Error))
        assertEquals("warning", sdkLogLevelConfigValue(DittoLogLevel.Warning))
        assertEquals("info", sdkLogLevelConfigValue(DittoLogLevel.Info))
        assertEquals("debug", sdkLogLevelConfigValue(DittoLogLevel.Debug))
        assertEquals("verbose", sdkLogLevelConfigValue(DittoLogLevel.Verbose))
    }

    @Test
    fun `an unreadable stored level is null rather than a guess`() {
        // Arrange / Act / Assert — the caller falls back to the SDK's current
        // level instead of silently rewriting a config it could not read.
        assertNull(sdkLogLevelFromConfigValue(null))
        assertNull(sdkLogLevelFromConfigValue(""))
        assertNull(sdkLogLevelFromConfigValue("chatty"))
    }

    @Test
    fun `stored levels are read case and whitespace insensitively`() {
        // Arrange / Act / Assert
        assertEquals(DittoLogLevel.Debug, sdkLogLevelFromConfigValue(" Debug "))
        assertEquals(DittoLogLevel.Warning, sdkLogLevelFromConfigValue("WARN"))
        assertEquals(DittoLogLevel.Verbose, sdkLogLevelFromConfigValue("trace"))
    }

    @Test
    fun `the default database log level is one this screen can read`() {
        // Arrange — DittoDatabase.logLevel defaults to "info"; a value the
        // toolbar could not parse would silently fall back to the SDK's level
        // and make the persisted choice look ignored.
        //
        // (`DittoLogger.minimumLogLevel` itself cannot be asserted here: reading
        // it loads the native dittoffi library, which is not on the JVM test
        // library path.)
        val parsed = sdkLogLevelFromConfigValue("info")

        // Assert
        assertEquals(DittoLogLevel.Info, parsed)
    }
}
