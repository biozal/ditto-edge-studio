package com.costoda.dittoedgestudio.domain.model

/**
 * One metric series sample (parity with the VS Code extension's
 * `SystemMetricSample`). The SDK 5.1 `system:metrics` virtual collection
 * FLUSHES the registry on every read, so each row carries a per-read delta —
 * running totals are accumulated host-side, keyed by metric + sorted labels.
 */
data class SystemMetricSample(
    /** Bare metric name, e.g. `ditto.network.dsoq.connection.opened`. */
    val key: String,
    val labels: Map<String, String>,
    val description: String,
    val unit: String,
    /** `histogram` when the row carries `count`/`dcount`; otherwise `counter`. */
    val kind: SystemMetricKind,
    /** Running total since connect (counters: `delta`; histograms: `dcount`). */
    val sinceConnect: Double,
    /** The most recent read's delta alone. */
    val periodDelta: Double,
    /** Histograms only: accumulated `dsum` since connect. */
    val sumSinceConnect: Double? = null,
    /** Histograms only: latest cumulative absolute max. */
    val absMax: Double? = null,
)

enum class SystemMetricKind { COUNTER, HISTOGRAM }

/** Status of the `system:metrics` poller (parity with the extension's status enum). */
enum class SystemMetricsStatus {
    IDLE,
    /** "Collect system metrics" is off — the exporter is startup-gated, so nothing polls now. */
    SETTING_DISABLED,
    /** No live Ditto instance. */
    NO_CONNECTION,
    /** The SDK answered but the exporter wasn't installed (placeholder rows). */
    EXPORTER_DISABLED,
    READY,
    ERROR,
}

/** A snapshot of the accumulated dashboard state. */
data class SystemMetricsSnapshot(
    val samples: List<SystemMetricSample>,
    val status: SystemMetricsStatus,
    /** epoch ms of the first accumulation — the "since connect" zero point. */
    val sinceMs: Long = 0,
    val polledAtMs: Long = 0,
    val errorMessage: String? = null,
)

object SystemMetricsAccumulator {

    /** Stable per-series signature: metric key plus its sorted label map. */
    fun seriesSignature(key: String, labels: Map<String, String>): String {
        val sorted = labels.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
        return "$key{$sorted}"
    }

    /** Folds one flush of `system:metrics` rows into [samples]. Ignores garbage rows. */
    fun accumulate(
        rows: List<Map<String, Any?>>,
        samples: MutableMap<String, SystemMetricSample>,
    ) {
        for (row in rows) {
            val parsed = parseMetricRow(row) ?: continue
            val sig = seriesSignature(parsed.key, parsed.labels)
            val existing = samples[sig]
            if (existing != null) {
                samples[sig] = existing.copy(
                    sinceConnect = existing.sinceConnect + parsed.delta,
                    periodDelta = parsed.delta,
                    sumSinceConnect = if (parsed.kind == SystemMetricKind.HISTOGRAM) {
                        (existing.sumSinceConnect ?: 0.0) + parsed.deltaSum
                    } else {
                        existing.sumSinceConnect
                    },
                    absMax = parsed.absMax ?: existing.absMax,
                )
            } else {
                samples[sig] = SystemMetricSample(
                    key = parsed.key,
                    labels = parsed.labels,
                    description = parsed.description,
                    unit = parsed.unit,
                    kind = parsed.kind,
                    sinceConnect = parsed.delta,
                    periodDelta = parsed.delta,
                    sumSinceConnect = if (parsed.kind == SystemMetricKind.HISTOGRAM) parsed.deltaSum else null,
                    absMax = parsed.absMax,
                )
            }
        }
    }

    /** True when the SELECT answered but the exporter isn't installed. */
    fun isExporterDisabled(rows: List<Map<String, Any?>>): Boolean =
        rows.isNotEmpty() &&
            rows.all { it["key"] !is String } &&
            rows.any { it["status"] == "disabled" }

    private data class ParsedRow(
        val key: String,
        val labels: Map<String, String>,
        val description: String,
        val unit: String,
        val kind: SystemMetricKind,
        val delta: Double,
        val deltaSum: Double,
        val absMax: Double?,
    )

    private fun parseMetricRow(row: Map<String, Any?>): ParsedRow? {
        val key = row["key"] as? String ?: return null
        if (key.isEmpty()) return null
        val labels = (row["labels"] as? Map<*, *>)
            ?.mapNotNull { (k, v) ->
                (k as? String)?.let { kk -> (v as? String)?.let { vv -> kk to vv } }
            }
            ?.toMap()
            ?: emptyMap()
        val isHistogram = num(row["count"]) != null || num(row["dcount"]) != null
        return ParsedRow(
            key = key,
            labels = labels,
            description = (row["description"] as? String) ?: "",
            unit = (row["unit"] as? String) ?: "",
            kind = if (isHistogram) SystemMetricKind.HISTOGRAM else SystemMetricKind.COUNTER,
            delta = num(row[if (isHistogram) "dcount" else "delta"]) ?: 0.0,
            deltaSum = num(row["dsum"]) ?: 0.0,
            absMax = num(row["abs_max"]),
        )
    }

    private fun num(value: Any?): Double? = when (value) {
        is Number -> value.toDouble().takeIf { it.isFinite() }
        else -> null
    }
}

/**
 * A pinned `system:metrics` series — the metric key plus the label map that,
 * together, identify one series. Deliberately NOT the whole sample: values change
 * every poll, pins do not.
 *
 * [id] is the same scheme as [SystemMetricsAccumulator.seriesSignature], the
 * SwiftUI `SystemMetricSeriesRef.id`, and the VS Code extension's `seriesId`, so
 * all four agree on what "the same series" means.
 */
data class SystemMetricSeriesRef(
    val key: String,
    val labels: Map<String, String>,
) {
    val id: String get() = "$key|$labelLine"

    /** The `key=value,key=value` line rendered under a row's metric name. */
    val labelLine: String
        get() = labels.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
}

fun SystemMetricSample.toSeriesRef(): SystemMetricSeriesRef = SystemMetricSeriesRef(key, labels)

/** Stable per-series identity shared with [SystemMetricSeriesRef.id]. */
val SystemMetricSample.seriesId: String get() = toSeriesRef().id

/**
 * Reordering rules for the pinned list, kept out of the UI so the index arithmetic —
 * the part that is easy to get subtly wrong — can be tested directly.
 *
 * The rules match the SwiftUI `SystemMetricsPinOrdering` and the VS Code extension's
 * drag handler, so reordering pins on one platform gives the same result on another.
 */
object SystemMetricsPinOrdering {

    /**
     * Moves the entry at [from] to [to], clamping both to the list. Backs the
     * live swap-as-you-drag on Android and the Move Up / Move Down commands
     * elsewhere; an out-of-range or same-slot move is a no-op.
     */
    fun move(
        pins: List<SystemMetricSeriesRef>,
        from: Int,
        to: Int,
    ): List<SystemMetricSeriesRef> {
        if (from !in pins.indices || to !in pins.indices || from == to) return pins
        return pins.toMutableList().apply { add(to, removeAt(from)) }
    }

    /**
     * Moves [draggedId] to sit immediately before (or after) [targetId].
     *
     * The dragged entry is removed *first* and the insertion point resolved against
     * what remains — the reason a downward drag lands where the pointer is rather
     * than one slot short of it. A drop on the dragged row itself, or on a target
     * no longer in the list (unpinned mid-drag), is a no-op.
     */
    fun moved(
        pins: List<SystemMetricSeriesRef>,
        draggedId: String,
        targetId: String,
        insertBefore: Boolean,
    ): List<SystemMetricSeriesRef> {
        if (draggedId == targetId) return pins
        val dragged = pins.firstOrNull { it.id == draggedId } ?: return pins
        val rest = pins.filterNot { it.id == draggedId }.toMutableList()
        val targetIndex = rest.indexOfFirst { it.id == targetId }
        if (targetIndex == -1) return pins
        rest.add(if (insertBefore) targetIndex else targetIndex + 1, dragged)
        return rest
    }
}
