package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.ditto.kotlin.DittoLogLevel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Aggregate statistics over a window of log entries — the data behind the three
 * histograms and the filter-tab badges.
 *
 * Pure value type with no I/O and no UI. [compute] is a single pass over the
 * entry window plus the pattern matches that were already produced for the
 * Problems section, so it adds no extra scanning cost. Run it off the main
 * dispatcher.
 *
 * Parity note: this mirrors `SwiftUI/EdgeStudio/Data/LogAnalytics.swift` and the
 * VS Code extension's `LogAnalyzerService`. The strategy may differ per platform;
 * the *outputs* may not. Every constant here is normative — see
 * `docs/LOG_ANALYZER_SPEC.md`.
 */
data class LogAnalytics(
    val counts: Counts = Counts(),
    val volumeByLevel: List<VolumeBin> = emptyList(),
    val problemsOverTime: List<ProblemBin> = emptyList(),
    val connectionDurations: List<DurationBin> = emptyDurationBins(),
    val sessions: List<ConnectionSession> = emptyList(),
    val startTime: Date? = null,
    val endTime: Date? = null,
    val tags: List<String> = emptyList(),
) {

    /**
     * ## `problems` vs `problemEntries`
     *
     * [problems] counts pattern **matches**: a line matched by three patterns
     * contributes three. [problemEntries] counts **distinct entries** with at
     * least one match. They diverge, and the difference is not cosmetic — the
     * Problems filter tab can only ever list distinct entries, so a badge
     * showing [problems] promises rows the table cannot produce. Badges MUST use
     * [problemEntries] / [criticalEntries].
     */
    data class Counts(
        val critical: Int = 0,
        val errors: Int = 0,
        val warnings: Int = 0,
        val problems: Int = 0,
        val problemEntries: Int = 0,
        val criticalEntries: Int = 0,
        val totalLines: Int = 0,
    )

    /** One time bin of the Log Volume by Level histogram. */
    data class VolumeBin(val startMs: Long, val counts: Map<DittoLogLevel, Int>) {
        val total: Int get() = counts.values.sum()
        val start: Date get() = Date(startMs)
    }

    /** One time bin of the Problems over Time histogram. */
    data class ProblemBin(val startMs: Long, val count: Int, val maxSeverity: Int) {
        val start: Date get() = Date(startMs)
    }

    /** One bucket of the Connection Durations row list. */
    data class DurationBin(val label: String, val count: Int) {
        /** True when no connection landed in this bucket. */
        val isEmpty: Boolean get() = count < 1
    }

    /** True when there is nothing worth rendering. */
    val isEmpty: Boolean get() = counts.totalLines == 0

    /** `06:50:47 → 20:35:08 (13.7h)`, or null when the window has no span. */
    val rangeDescription: String?
        get() {
            val start = startTime ?: return null
            val end = endTime ?: return null
            val formatter = SimpleDateFormat("HH:mm:ss", Locale.US)
            val span = (end.time - start.time) / 1000.0
            return "${formatter.format(start)} → ${formatter.format(end)} (${humanDuration(span)})"
        }

    companion object {

        // ── Binning constants ────────────────────────────────────────────────
        //
        // Normative for all three platforms — see `docs/LOG_ANALYZER_SPEC.md`.
        // `LogAnalyticsTest` pins these so a change here is a deliberate,
        // cross-platform decision rather than a local drift.

        /** Candidate bin widths, in milliseconds, coarsest last. */
        val VOLUME_BIN_CANDIDATES_MS: List<Long> =
            listOf(1_000L, 5_000L, 30_000L, 60_000L, 300_000L, 600_000L, 1_800_000L)

        /** Bin count the width picker aims for across the full time range. */
        const val VOLUME_BIN_TARGET_BUCKETS = 40

        /**
         * Stack order for the volume histogram, bottom to top. Fixed so the
         * stack does not reshuffle between refreshes.
         */
        val LEVEL_STACK_ORDER: List<DittoLogLevel> = listOf(
            DittoLogLevel.Verbose,
            DittoLogLevel.Debug,
            DittoLogLevel.Info,
            DittoLogLevel.Warning,
            DittoLogLevel.Error,
        )

        /**
         * Upper bounds, in seconds, for the connection-duration buckets. Buckets
         * are **half-open** (`duration < maxSeconds`), so a value sitting exactly
         * on a boundary belongs to the next bucket up. The final bucket is
         * unbounded.
         */
        val DURATION_BINS: List<Pair<String, Double>> = listOf(
            "0–1s" to 1.0,
            "1–5s" to 5.0,
            "5–30s" to 30.0,
            "30s–5m" to 300.0,
            "5m+" to Double.POSITIVE_INFINITY,
        )

        /** All duration buckets, zeroed — the axis never reflows as data arrives. */
        fun emptyDurationBins(): List<DurationBin> = DURATION_BINS.map { DurationBin(it.first, 0) }

        /**
         * Picks the finest bin width that keeps the bucket count at or below
         * [target], so a 10-minute window and a 14-hour window both render a
         * readable number of bars.
         */
        fun pickBinWidthMs(rangeMs: Long, target: Int = VOLUME_BIN_TARGET_BUCKETS): Long {
            val want = maxOf(rangeMs, 1L).toDouble() / maxOf(target, 1).toDouble()
            return VOLUME_BIN_CANDIDATES_MS.firstOrNull { it.toDouble() >= want }
                ?: VOLUME_BIN_CANDIDATES_MS.last()
        }

        // ── Compute ──────────────────────────────────────────────────────────

        /**
         * Aggregates [entries] (and the [matches] already produced for them by
         * [LogPatternEngine]) into a full analytics snapshot.
         *
         * @param entries the analysis window, in any order. Callers should pass
         *   the **same** population the pattern scan covered — badges computed
         *   over a window while the list filters the whole buffer under-report.
         * @param matches pattern matches over the same entries. Matches whose
         *   entry is outside [entries] are still counted toward `problems`.
         * @param sessionEntries entries used to reconstruct connection sessions.
         *   Defaults to [entries]. **Pass the full unwindowed buffer here** when
         *   [entries] is a capped window: a `started` line that ages out of the
         *   window can never be paired with its `ended`, and roughly a third of
         *   real sessions span more than 5 000 entries.
         */
        fun compute(
            entries: List<LogEntry>,
            matches: List<LogPatternEngine.Match>,
            sessionEntries: List<LogEntry> = entries,
        ): LogAnalytics {
            if (entries.isEmpty()) return LogAnalytics()

            // ── Pass 1: per-entry counts, time range, tags ───────────────────
            var errors = 0
            var warnings = 0
            var earliest = entries[0].timestamp
            var latest = entries[0].timestamp
            val tagSet = LinkedHashSet<String>()

            for (entry in entries) {
                when (entry.level) {
                    DittoLogLevel.Error -> errors++
                    DittoLogLevel.Warning -> warnings++
                    else -> Unit
                }
                if (entry.timestamp.time < earliest.time) earliest = entry.timestamp
                if (entry.timestamp.time > latest.time) latest = entry.timestamp
                tagSet.add(entry.component.displayName)
            }

            // ── Problem accounting ───────────────────────────────────────────
            var problems = 0
            var critical = 0
            val problemEntryIds = HashSet<UUID>()
            val criticalEntryIds = HashSet<UUID>()
            for (match in matches) {
                problems++
                problemEntryIds.add(match.entry.id)
                if (match.pattern.severity >= 5) {
                    critical++
                    criticalEntryIds.add(match.entry.id)
                }
            }

            val counts = Counts(
                critical = critical,
                errors = errors,
                warnings = warnings,
                problems = problems,
                problemEntries = problemEntryIds.size,
                criticalEntries = criticalEntryIds.size,
                totalLines = entries.size,
            )

            // ── Histograms ───────────────────────────────────────────────────
            val rangeMs = latest.time - earliest.time
            val binMs = pickBinWidthMs(maxOf(rangeMs, 1_000L))

            val volume = HashMap<Long, HashMap<DittoLogLevel, Int>>()
            for (entry in entries) {
                val bin = binStart(entry.timestamp, binMs)
                val levels = volume.getOrPut(bin) { HashMap() }
                levels[entry.level] = (levels[entry.level] ?: 0) + 1
            }

            val problemBins = HashMap<Long, ProblemBin>()
            for (match in matches) {
                val bin = binStart(match.entry.timestamp, binMs)
                val current = problemBins[bin]
                problemBins[bin] = if (current == null) {
                    ProblemBin(bin, 1, maxOf(1, match.pattern.severity))
                } else {
                    ProblemBin(bin, current.count + 1, maxOf(current.maxSeverity, match.pattern.severity))
                }
            }

            val tracker = LogConnectionTracker.track(sessionEntries)

            // Bins are accumulated in hash maps, whose iteration order is not
            // stable; the histograms must come back in ascending time order.
            return LogAnalytics(
                counts = counts,
                volumeByLevel = volume.entries
                    .sortedBy { it.key }
                    .map { VolumeBin(it.key, it.value.toMap()) },
                problemsOverTime = problemBins.entries
                    .sortedBy { it.key }
                    .map { it.value },
                connectionDurations = binDurations(tracker.closedSessions),
                sessions = tracker.sessions,
                startTime = earliest,
                endTime = latest,
                tags = tagSet.sorted(),
            )
        }

        /**
         * Buckets closed sessions by duration. Empty buckets are retained so the
         * row list stays stable as data arrives instead of reflowing. Open
         * sessions have no duration and are skipped.
         */
        fun binDurations(sessions: List<ConnectionSession>): List<DurationBin> {
            val counts = IntArray(DURATION_BINS.size)
            for (session in sessions) {
                val duration = session.duration ?: continue
                val index = DURATION_BINS.indexOfFirst { duration < it.second }
                if (index >= 0) counts[index]++
            }
            return DURATION_BINS.mapIndexed { index, bin -> DurationBin(bin.first, counts[index]) }
        }

        // ── Helpers ──────────────────────────────────────────────────────────

        /** `floor(epochMs / width) * width`, per the spec. */
        private fun binStart(date: Date, binMs: Long): Long = Math.floorDiv(date.time, binMs) * binMs

        /** `<1s`, `45s`, `1.5m`, `1.5h`, `1.5d`. */
        fun humanDuration(seconds: Double): String = when {
            seconds < 1 -> "<1s"
            seconds < 60 -> String.format(Locale.US, "%.0fs", seconds)
            seconds < 3600 -> String.format(Locale.US, "%.1fm", seconds / 60)
            seconds < 86_400 -> String.format(Locale.US, "%.1fh", seconds / 3600)
            else -> String.format(Locale.US, "%.1fd", seconds / 86_400)
        }
    }
}
