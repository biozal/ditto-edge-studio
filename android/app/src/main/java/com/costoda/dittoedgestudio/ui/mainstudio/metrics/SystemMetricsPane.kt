package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.SystemMetricSample
import com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot
import com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus
import java.util.Locale

/** The nine `ditto.network.dsoq.*` counters per the SDK 5.1 source (extension parity). */
internal val DSOQ_KEYS = listOf(
    "ditto.network.dsoq.connection.opened",
    "ditto.network.dsoq.connection.closed",
    "ditto.network.dsoq.handshake_failed",
    "ditto.network.dsoq.endpoint.connect_failed",
    "ditto.network.dsoq.tlv.decode_invalid",
    "ditto.network.dsoq.tlv.unknown_type_fatal",
    "ditto.network.dsoq.tlv.unknown_type_optional",
    "ditto.network.dsoq.stream.unreliable.datagram_dropped_no_stream",
    "ditto.network.dsoq.stream.reliable.implicit_refused",
)

private enum class NamespaceFilter(val label: String, val prefixes: List<String>?) {
    ALL("All", null),
    NETWORK("Network", listOf("ditto.network.")),
    STORE("Store", listOf("ditto.backend.")),
    SYNC("Sync", listOf("ditto.sync.", "ditto.replication.")),
    OTHER("Other", listOf()),
}

private fun matchesFilter(sample: SystemMetricSample, filter: NamespaceFilter): Boolean = when (filter) {
    NamespaceFilter.ALL -> true
    NamespaceFilter.OTHER -> NamespaceFilter.entries
        .filter { it.prefixes != null }
        .none { other -> other.prefixes!!.any { sample.key.startsWith(it) } }
    else -> filter.prefixes!!.any { sample.key.startsWith(it) }
}

internal fun formatMetricValue(value: Double): String {
    val longValue = value.toLong()
    return when {
        value == longValue.toDouble() -> "%,d".format(Locale.US, longValue)
        value < 10 -> "%.2f".format(Locale.US, value)
        else -> "%.1f".format(Locale.US, value)
    }
}

/**
 * The `system:metrics` dashboard (SDK 5.1; parity with the extension's Database Metrics
 * system-metrics section): summary cards for connection counters, a namespace-filtered
 * counter table, and the dsoq opened-vs-closed divergence alert.
 */
@Composable
fun SystemMetricsPane(
    snapshot: SystemMetricsSnapshot,
    modifier: Modifier = Modifier,
) {
    var filter by remember { mutableStateOf(NamespaceFilter.ALL) }

    Column(modifier = modifier.fillMaxSize().padding(12.dp)) {
        when (snapshot.status) {
            SystemMetricsStatus.SETTING_DISABLED -> StatusMessage(
                "System metrics collection is off. Enable \"Collect system metrics\" in Settings — " +
                    "it takes effect the next time you open a database.",
            )
            SystemMetricsStatus.EXPORTER_DISABLED -> StatusMessage(
                "The SDK exporter wasn't enabled for this session. " +
                    "Close and re-open the database after enabling \"Collect system metrics\".",
            )
            SystemMetricsStatus.NO_CONNECTION -> StatusMessage("No active database connection.")
            SystemMetricsStatus.ERROR -> StatusMessage(
                "system:metrics read failed: ${snapshot.errorMessage ?: "unknown error"}",
                isError = true,
            )
            SystemMetricsStatus.IDLE, SystemMetricsStatus.READY -> ReadyBody(
                snapshot = snapshot,
                filter = filter,
                onFilterChange = { filter = it },
            )
        }
    }
}

@Composable
private fun StatusMessage(text: String, isError: Boolean = false) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(8.dp),
    )
}

@Composable
private fun ReadyBody(
    snapshot: SystemMetricsSnapshot,
    filter: NamespaceFilter,
    onFilterChange: (NamespaceFilter) -> Unit,
) {
    val opened = snapshot.samples.firstOrNull { it.key == "ditto.network.dsoq.connection.opened" }?.sinceConnect
    val closed = snapshot.samples.firstOrNull { it.key == "ditto.network.dsoq.connection.closed" }?.sinceConnect

    // Divergence alert (extension parity): opened ≠ closed may signal a connection leak
    // or handshake problem.
    if (opened != null && closed != null && opened != closed) {
        Surface(
            color = MaterialTheme.colorScheme.errorContainer,
            shape = RoundedCornerShape(6.dp),
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Text(
                text = "dsoq connections opened (${
                    formatMetricValue(opened)
                }) ≠ closed (${formatMetricValue(closed)}) — possible connection leak or handshake issue. " +
                    "Check the Log Analyzer's Transport Conditions tab.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.padding(8.dp),
            )
        }
    }

    // Namespace filter chips.
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(bottom = 8.dp),
    ) {
        NamespaceFilter.entries.forEach { ns ->
            FilterChip(
                selected = filter == ns,
                onClick = { onFilterChange(ns) },
                label = { Text(ns.label, style = MaterialTheme.typography.labelSmall) },
            )
        }
    }

    val filtered = snapshot.samples.filter { matchesFilter(it, filter) }
    if (filtered.isEmpty()) {
        StatusMessage(
            if (snapshot.samples.isEmpty()) {
                "No metrics reported yet — they accumulate while this section is visible."
            } else {
                "No metrics in this namespace."
            },
        )
        return
    }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items(filtered, key = { it.key + it.labels.toSortedMap().toString() }) { sample ->
            MetricRow(sample)
        }
    }
}

@Composable
private fun MetricRow(sample: SystemMetricSample) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                sample.key.removePrefix("ditto."),
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            if (sample.labels.isNotEmpty()) {
                Text(
                    sample.labels.toSortedMap().entries.joinToString(" ") { "${it.key}=${it.value}" },
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                formatMetricValue(sample.sinceConnect) +
                    if (sample.unit.isNotBlank()) " ${sample.unit}" else "",
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            val period = sample.periodDelta
            Text(
                if (period > 0) "▲ +${formatMetricValue(period)}" else "—",
                fontFamily = FontFamily.Monospace,
                fontSize = 10.sp,
                color = if (period > 0) {
                    androidx.compose.ui.graphics.Color(0xFF34C759)
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}
