package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogPattern
import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.costoda.dittoedgestudio.domain.model.parseLevelFilter
import com.ditto.kotlin.DittoLogLevel

/**
 * Compiles and scans [LogPattern]s against log entries (parity port of the VS
 * Code extension's `PatternEngine`).
 *
 * Scan semantics (mirrors the extension exactly):
 * - The pattern regex matches the entry **message body only**, case-insensitive.
 * - `level_filter` is an **exact** equality, not "at least", so tiered patterns
 *   (e.g. deadlock at Error vs Warning) stay mutually exclusive.
 * - `tag_filter` is a case-sensitive regex against the line's tag — here the
 *   entry's component display name (e.g. "Sync").
 * - Matching patterns contribute their `user_tag` to the entry.
 */
class LogPatternEngine(patterns: Map<String, LogPattern>) {

    data class CompiledPattern(
        val key: String,
        val regex: Regex,
        val severity: Int,
        val recommendation: String,
        val levelFilter: DittoLogLevel?,
        val tagFilter: Regex?,
        val userTag: String?,
        val source: PatternSource,
    )

    data class Match(val pattern: CompiledPattern, val entry: LogEntry)

    val compiled: List<CompiledPattern> = patterns.values.map { it.toCompiled() }

    /** Returns every pattern matching this entry (usually zero). */
    fun scan(entry: LogEntry): List<CompiledPattern> {
        val tag = entry.component.displayName
        return compiled.filter { p ->
            (p.levelFilter == null || entry.level == p.levelFilter) &&
                (p.tagFilter == null || p.tagFilter.containsMatchIn(tag)) &&
                p.regex.containsMatchIn(entry.message)
        }
    }

    /**
     * Scans the newest [maxEntries] of [entries] and returns all matches in
     * chronological order. Callers should run this off the main thread; the
     * cap bounds worst-case cost on chatty logs.
     */
    fun scanAll(entries: List<LogEntry>, maxEntries: Int = MAX_SCAN_ENTRIES): List<Match> {
        val window = if (entries.size > maxEntries) entries.takeLast(maxEntries) else entries
        return window.flatMap { entry -> scan(entry).map { Match(it, entry) } }
    }

    /** True if [message] matches this pattern's regex — for the editor's test line. */
    fun matches(pattern: LogPatternBody, level: DittoLogLevel, tag: String, message: String): Boolean {
        val compiledKey = "" // key irrelevant for a one-off match check
        val lp = LogPattern(compiledKey, pattern, pattern.severity, parseLevelFilter(pattern.levelFilter), PatternSource.USER)
        val compiled = runCatching { lp.toCompiled() }.getOrNull() ?: return false
        return (compiled.levelFilter == null || level == compiled.levelFilter) &&
            (compiled.tagFilter == null || compiled.tagFilter.containsMatchIn(tag)) &&
            compiled.regex.containsMatchIn(message)
    }

    companion object {
        /**
         * Upper bound on entries scanned per pass. The UI tab sources are capped
         * at 10k each; scanning more than this per refresh would jank phones.
         */
        const val MAX_SCAN_ENTRIES = 5_000

        /** Parity with the extension's MAX_USER_PATTERN_LENGTH. */
        const val MAX_USER_PATTERN_LENGTH = 512

        /**
         * Nested-quantifier shapes — `(a+)+`, `(\w+\s*)+`, `(a*){2,}` — the class
         * of pattern whose backtracking cost is exponential in the input length
         * (java.util.regex has no timeout). Bundled patterns are ours and covered
         * by tests, so they skip the check. Parity with the extension's ReDoS guard.
         */
        private val NESTED_QUANTIFIER = Regex("""\([^)]*[+*][^)]*\)\s*[+*{]""")

        /**
         * Returns a human-readable rejection reason, or null if the pattern is
         * valid for [source]. Mirrors the extension: severity must be 1..5 and a
         * recommendation is required; user patterns get additional safety checks
         * (length cap, nested-quantifier rejection, regex compilation).
         */
        fun rejectReason(key: String, body: LogPatternBody, source: PatternSource): String? {
            if (key.isBlank()) return "key must not be blank"
            if (body.pattern.isEmpty()) return "pattern must be a non-empty string"
            if (body.severity !in 1..5) return "severity must be 1–5"
            if (body.recommendation.isBlank()) return "recommendation is required"

            // Unknown level_filter tokens are rejected (VS Code parity: an unknown
            // token can never equal a line's level, so the pattern would silently
            // match nothing — surfacing the typo is friendlier).
            body.levelFilter?.takeIf { it.isNotBlank() }?.let { token ->
                if (com.costoda.dittoedgestudio.domain.model.parseLevelFilter(token) == null) {
                    return "unknown level_filter '$token' (expected error|warning|info|debug|verbose)"
                }
            }

            if (source == PatternSource.USER) {
                if (body.pattern.length > MAX_USER_PATTERN_LENGTH) {
                    return "pattern exceeds $MAX_USER_PATTERN_LENGTH characters"
                }
                if (NESTED_QUANTIFIER.containsMatchIn(body.pattern)) {
                    return "pattern nests a quantifier inside a quantified group, " +
                        "which can backtrack exponentially"
                }
            }
            runCatching { body.pattern.toRegex(RegexOption.IGNORE_CASE) }
                .onFailure { return "pattern is not a valid regex: ${it.message}" }

            // tag_filter gets the same treatment — an invalid one would otherwise
            // throw during engine compilation (and crash the Logging screen when
            // it arrives via a hand-edited user_patterns.json).
            body.tagFilter?.takeIf { it.isNotBlank() }?.let { tag ->
                if (source == PatternSource.USER && NESTED_QUANTIFIER.containsMatchIn(tag)) {
                    return "tag_filter nests a quantifier inside a quantified group, " +
                        "which can backtrack exponentially"
                }
                runCatching { tag.toRegex() }
                    .onFailure { return "tag_filter is not a valid regex: ${it.message}" }
            }

            return null
        }

        private fun LogPattern.toCompiled(): CompiledPattern = CompiledPattern(
            key = key,
            regex = body.pattern.toRegex(RegexOption.IGNORE_CASE),
            severity = severity,
            recommendation = body.recommendation,
            levelFilter = levelFilter,
            tagFilter = body.tagFilter?.trim()?.takeIf { it.isNotEmpty() }?.toRegex(),
            userTag = body.userTag?.trim()?.takeIf { it.isNotEmpty() },
            source = source,
        )
    }
}
