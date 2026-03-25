package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.GZIPInputStream

object LogFileParser {

    // ISO 8601 with and without fractional seconds
    private val isoWithFractional = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }
    private val isoWithMillis = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }
    private val isoBasic = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }
    private val isoWithOffset = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }
    private val isoWithMillisOffset = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }

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
        val timestamp = runCatching { appLogFormat.parse(timestampStr) }.getOrNull() ?: Date()
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

    private fun parseIsoTimestamp(value: String): Date? {
        if (value.isBlank()) return null
        // Normalize timezone offset for SimpleDateFormat compatibility
        val normalized = value.replace(Regex("([+-]\\d{2}):(\\d{2})$"), "$1$2")
        val parsers = listOf(
            isoWithFractional,
            isoWithMillis,
            isoBasic,
            isoWithMillisOffset,
            isoWithOffset,
        )
        for (parser in parsers) {
            try {
                return synchronized(parser) { parser.parse(normalized) }
            } catch (_: ParseException) {
                // try next
            }
        }
        return null
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
