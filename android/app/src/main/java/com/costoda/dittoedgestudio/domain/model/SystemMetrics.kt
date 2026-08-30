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
