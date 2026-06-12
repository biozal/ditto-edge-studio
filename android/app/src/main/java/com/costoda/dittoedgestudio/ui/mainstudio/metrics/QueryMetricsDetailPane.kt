package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.QueryMetrics

/**
 * Content Pane (detail pane) for the Query Metrics scene-driven section (Task 4.3d).
 *
 * Fetches the [QueryMetrics] for [historyId] from [metricsRepository] and renders
 * the DQL statement, execution stats, and EXPLAIN output — the same content as the
 * `QueryMetricsDetail` private composable in the legacy self-contained QueryMetricsScreen.
 *
 * Handles the metric-gone-after-clear-all case: if the metric is not found (null) after
 * loading it shows an empty-state message identical to the no-selection placeholder.
 */
@Composable
fun QueryMetricsDetailPane(
    historyId: Long,
    metricsRepository: QueryMetricsRepository,
    modifier: Modifier = Modifier,
) {
    var record by remember(historyId) { mutableStateOf<QueryMetrics?>(null) }
    var loaded by remember(historyId) { mutableStateOf(false) }

    LaunchedEffect(historyId) {
        runCatching { record = metricsRepository.getByHistoryId(historyId) }
        loaded = true
    }

    if (!loaded) return

    if (record == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "Select a query to view details",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    val metric = record!!
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = "DQL Statement",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = metric.queryText.ifBlank { "—" },
                    modifier = Modifier.padding(8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                QueryStatBadge(
                    label = "Time",
                    value = formatQueryExecutionTime(metric.executionTimeMs),
                    valueColor = queryExecutionTimeColor(metric.executionTimeMs),
                )
                QueryStatBadge(label = "Results", value = "${metric.docsReturned} docs")
                QueryStatBadge(
                    label = "Index",
                    value = if (metric.indexesUsed.isNotEmpty()) "✓ Yes" else "✗ No",
                    valueColor = if (metric.indexesUsed.isNotEmpty()) Color(0xFF4CAF50)
                    else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        if (!metric.explainPlan.isNullOrBlank()) {
            item {
                Text(
                    text = "EXPLAIN Output",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = metric.explainPlan,
                        modifier = Modifier.padding(8.dp),
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                    )
                }
            }
        }
    }
}

@Composable
private fun QueryStatBadge(
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
) {
    Surface(
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = valueColor,
            )
        }
    }
}
