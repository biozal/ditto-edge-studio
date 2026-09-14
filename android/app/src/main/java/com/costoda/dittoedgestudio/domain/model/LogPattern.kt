package com.costoda.dittoedgestudio.domain.model

import com.ditto.kotlin.DittoLogLevel
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A user- or bundled-defined log-analysis pattern (parity with the VS Code
 * extension's `problem_patterns.json` schema). Patterns scan the message body
 * of each log entry (case-insensitive).
 *
 * Serialized form is the map value in `problem_patterns.json` /
 * `user_patterns.json` — the map key is the pattern's [LogPattern.key].
 */
@Serializable
data class LogPatternBody(
    val pattern: String,
    val severity: Int,
    val recommendation: String,
    @SerialName("level_filter") val levelFilter: String? = null,
    @SerialName("tag_filter") val tagFilter: String? = null,
    @SerialName("user_tag") val userTag: String? = null,
)

/** Where a pattern came from. Bundled patterns are read-only. */
enum class PatternSource { BUNDLED, USER }

/**
 * A validated pattern ready for compilation. Invalid patterns never become a
 * [LogPattern] — the store records a rejection reason instead
 * ([com.costoda.dittoedgestudio.data.logging.LogPatternStore.patternErrors]).
 */
data class LogPattern(
    val key: String,
    val body: LogPatternBody,
    val severity: Int,
    val levelFilter: DittoLogLevel?,
    val source: PatternSource,
)

/**
 * Maps the VS Code `level_filter` tokens onto [DittoLogLevel]. Accepts both the
 * webview spellings (`warn`, `trace`) and SDK spellings (`warning`, `verbose`).
 * Returns null when the token is absent/blank (no level scoping).
 */
fun parseLevelFilter(token: String?): DittoLogLevel? = when (token?.trim()?.lowercase()) {
    null, "" -> null
    "error" -> DittoLogLevel.Error
    "warn", "warning" -> DittoLogLevel.Warning
    "info" -> DittoLogLevel.Info
    "debug" -> DittoLogLevel.Debug
    "trace", "verbose" -> DittoLogLevel.Verbose
    else -> null
}

/** Severity 5 (critical) down to 1 (info), parity with the VS Code extension. */
fun severityLabel(severity: Int): String = when (severity) {
    5 -> "CRITICAL"
    4 -> "HIGH"
    3 -> "MEDIUM"
    2 -> "LOW"
    else -> "INFO"
}
