package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeParseException
import java.util.Date
import java.util.Locale
import java.util.zip.GZIPInputStream

object LogFileParser {

    /**
     * `+0100` -> `+01:00`. The `java.time` ISO parsers want the extended offset
     * form; some producers emit the basic one.
     */
    private val basicOffset = Regex("""([+-]\d{2})(\d{2})$""")

    // Timber plain-text format: "2026/03/08 14:22:11:456 INFO [DittoManager] Message"
    private val appLogFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss:SSS", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }
    private val appLogRegex = Regex(
        """^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}:\d{3})\s+(\w+)(?:\s+\[([^\]]+)])?\s+(.+)$""",
    )

    /** Parse a gzip-compressed JSONL file exported by DittoLogger.exportToFile() */
    fun parseGzipJsonlFile(file: File): List<LogEntry> {
        if (!file.exists() || !file.canRead()) return emptyList()
        return runCatching {
            val entries = mutableListOf<LogEntry>()
            GZIPInputStream(file.inputStream()).use { gzip ->
                BufferedReader(InputStreamReader(gzip)).useLines { lines ->
                    lines.forEach { line ->
                        val trimmed = line.trim()
                        if (trimmed.isNotEmpty()) {
                            parseJsonLine(trimmed, LogEntrySource.DittoSDK)?.let { entries.add(it) }
                        }
                    }
                }
            }
            entries
        }.getOrDefault(emptyList())
    }

    /** Parse a plain JSONL file (one JSON object per line) */
    fun parseJSONLFile(file: File): List<LogEntry> {
        if (!file.exists() || !file.canRead()) return emptyList()
        return runCatching {
            file.bufferedReader().useLines { lines ->
                lines.mapNotNull { line ->
                    val trimmed = line.trim()
                    if (trimmed.isEmpty()) null
                    else parseJsonLine(trimmed, LogEntrySource.DittoSDK)
                }.toList()
            }
        }.getOrDefault(emptyList())
    }

    /** Parse a JSONL content string */
    fun parseJSONL(content: String, source: LogEntrySource): List<LogEntry> {
        return content.lines().mapNotNull { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty()) null else parseJsonLine(trimmed, source)
        }
    }

    /** Parse a single raw log line from DittoLogger.observeLogEvents() — format: "level|message" */
    fun parseRawLogLine(raw: String, source: LogEntrySource): LogEntry? {
        val pipeIdx = raw.indexOf('|')
        if (pipeIdx < 0) {
            return LogEntry(
                timestamp = Date(),
                level = DittoLogLevel.Info,
                message = raw,
                component = LogComponent.heuristic(raw),
                source = source,
                rawLine = raw,
            )
        }
        val levelStr = raw.substring(0, pipeIdx).trim()
        val message = raw.substring(pipeIdx + 1)
        val level = parseLevelString(levelStr)
        return LogEntry(
            timestamp = Date(),
            level = level,
            message = message,
            component = LogComponent.heuristic(message),
            source = source,
            rawLine = raw,
        )
    }

    /** Parse a single structured event from DittoLogger.observeLogEvents() */
    fun fromDittoLogEvent(level: DittoLogLevel, message: String): LogEntry {
        return LogEntry(
            timestamp = Date(),
            level = level,
            message = message,
            component = LogComponent.heuristic(message),
            source = LogEntrySource.DittoSDK,
            rawLine = "${level.name}|$message",
        )
    }

    /** Parse a Timber plain-text app log file */
    fun parseAppLogFile(file: File): List<LogEntry> {
        if (!file.exists() || !file.canRead()) return emptyList()
        return runCatching {
            file.bufferedReader().useLines { lines ->
                lines.mapNotNull { line ->
                    parseAppLogLine(line.trim())
                }.toList()
            }
        }.getOrDefault(emptyList())
    }

    /** Parse all app log files in a directory */
    fun parseDirectory(dir: File): List<LogEntry> {
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        val files = dir.listFiles { f -> f.name.startsWith("app-") && f.name.endsWith(".log") }
            ?: return emptyList()
        return files.sortedBy { it.name }.flatMap { parseAppLogFile(it) }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private fun parseJsonLine(line: String, source: LogEntrySource): LogEntry? {
        return runCatching {
            val obj = JSONObject(line)
            val timestamp = parseIsoTimestamp(
                obj.optString("time").ifBlank { obj.optString("timestamp") },
            ) ?: Date()
            val levelStr = obj.optString("level").ifBlank { obj.optString("lvl") }
            val level = parseLevelString(levelStr)
            val message = obj.optString("message").ifBlank { obj.optString("msg", line) }
            val target = obj.optString("target").ifBlank { obj.optString("component") }
            // Deliberate, documented divergence from SwiftUI: when the record
            // carries no `target`/`component` key, SwiftUI classifies it as
            // `.other` (its parser calls `from(target:)` unconditionally with the
            // empty string) while we fall back to the message heuristic.
            //
            // Measured over all 33 real captures under
            // `…/ditto_edge_studio/*/database/ditto_logs/*.log(.gz)` — 746 282
            // JSON Lines records, gzipped files included — **every** record has a
            // non-blank `target`, so this branch never fires on SDK log files and
            // the two platforms cannot disagree because of it. It is kept because
            // it is strictly better on the paths that *can* reach it (imported
            // third-party JSONL, and `parseAppLogLine` below, which has no SwiftUI
            // counterpart): a blank tag with a message body that names its
            // subsystem is classified rather than dumped into `Other`.
            val component = if (target.isNotBlank()) LogComponent.from(target)
            else LogComponent.heuristic(message)
            LogEntry(
                timestamp = timestamp,
                level = level,
                message = message,
                component = component,
                source = source,
                rawLine = line,
            )
        }.getOrNull() ?: LogEntry(
            timestamp = Date(),
            level = DittoLogLevel.Info,
            message = line,
            component = LogComponent.OTHER,
            source = source,
            rawLine = line,
        )
    }

    private fun parseAppLogLine(line: String): LogEntry? {
        if (line.isBlank()) return null
        val match = appLogRegex.find(line) ?: return LogEntry(
            timestamp = Date(),
            level = DittoLogLevel.Info,
            message = line,
            component = LogComponent.OTHER,
            source = LogEntrySource.Application,
            rawLine = line,
        )
        val (timestampStr, levelStr, tag, message) = match.destructured
        // SimpleDateFormat is not thread-safe and this object is a singleton.
        val timestamp = runCatching { synchronized(appLogFormat) { appLogFormat.parse(timestampStr) } }
            .getOrNull() ?: Date()
        val level = parseLevelString(levelStr)
        val component = if (tag.isNotBlank()) LogComponent.from(tag) else LogComponent.heuristic(message)
        return LogEntry(
            timestamp = timestamp,
            level = level,
            message = message,
            component = component,
            source = LogEntrySource.Application,
            rawLine = line,
        )
    }

    /**
     * Parses the SDK's ISO-8601 timestamps at **any** fractional precision.
     *
     * This must not use [SimpleDateFormat]. In its pattern language `S` is
     * *milliseconds*, not fraction-of-second, so `yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'`
     * reads the microseconds in `2026-09-05T20:43:51.784135Z` as 784 135 **ms**
     * and returns `20:56:55` — 13 minutes late. Every `ditto_logs` record carries
     * 6-digit fractional seconds, so that pattern (tried first) corrupted every
     * timestamp read from a `.log`/`.log.gz` file, and with it the analytics time
     * range, both histograms, the connection durations and the date filter.
     *
     * `java.time` parses fraction-of-second correctly at 0-9 digits. It is
     * available natively here (minSdk 28; `java.time` is API 26+).
     */
    private fun parseIsoTimestamp(value: String): Date? {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return null
        val normalized = trimmed.replace(basicOffset, "$1:$2")
        return parseInstant(normalized)?.let(Date::from)
    }

    private fun parseInstant(text: String): Instant? {
        // `…Z`, any fractional precision — the shape the SDK writes.
        try {
            return Instant.parse(text)
        } catch (_: DateTimeParseException) {
            // try next
        }
        // Explicit numeric offset, e.g. `…+01:00`.
        try {
            return OffsetDateTime.parse(text).toInstant()
        } catch (_: DateTimeParseException) {
            // try next
        }
        // No zone designator at all. The SDK writes UTC, so read it as UTC —
        // the same assumption the old parsers encoded via their `timeZone`.
        return try {
            LocalDateTime.parse(text).toInstant(ZoneOffset.UTC)
        } catch (_: DateTimeParseException) {
            null
        }
    }

    internal fun parseLevelString(levelStr: String): DittoLogLevel = when (levelStr.lowercase()) {
        "error", "err", "e" -> DittoLogLevel.Error
        "warning", "warn", "w" -> DittoLogLevel.Warning
        "info", "i" -> DittoLogLevel.Info
        "debug", "dbg", "d" -> DittoLogLevel.Debug
        "verbose", "verb", "v", "trace" -> DittoLogLevel.Verbose
        else -> DittoLogLevel.Info
    }
}
