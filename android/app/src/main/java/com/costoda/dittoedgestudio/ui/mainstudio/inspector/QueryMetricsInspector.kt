package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.QueryMetrics

@Composable
fun QueryMetricsInspector(
    metrics: QueryMetrics?,
    modifier: Modifier = Modifier,
) {
    if (metrics == null) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "Run a query to see metrics",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        return
    }

    val bytesReadLabel = formatBytes(metrics.bytesRead)
    val indexesLabel = if (metrics.indexesUsed.isEmpty()) "None"
    else metrics.indexesUsed.joinToString(", ")

    LazyColumn(modifier = modifier.padding(12.dp)) {
        item {
            MetricRow("Execution Time", "${metrics.executionTimeMs} ms")
            MetricRow("Documents Examined", "${metrics.docsExamined}")
            MetricRow("Documents Returned", "${metrics.docsReturned}")
            MetricRow("Bytes Read", bytesReadLabel)
            MetricRow("Indexes Used", indexesLabel)

            if (metrics.explainPlan != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = "EXPLAIN Plan",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.height(4.dp))
                SelectionContainer {
                    Text(
                        text = metrics.explainPlan,
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                        ),
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        )
    }
    HorizontalDivider(thickness = 0.5.dp)
}

private fun formatBytes(bytes: Long): String = when {
    bytes < 1_024 -> "$bytes B"
    bytes < 1_048_576 -> "${"%.1f".format(bytes / 1_024.0)} KB"
    else -> "${"%.1f".format(bytes / 1_048_576.0)} MB"
}
