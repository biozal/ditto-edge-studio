package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ClearAll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun QueryMetricsScreen(
    metricsRepository: QueryMetricsRepository,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    var records by remember { mutableStateOf<List<QueryMetrics>>(emptyList()) }
    var selectedRecord by remember { mutableStateOf<QueryMetrics?>(null) }
    val isTablet = LocalConfiguration.current.screenWidthDp >= 600

    LaunchedEffect(Unit) {
        runCatching {
            records = metricsRepository.getAllMetrics()
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Header
        Surface(tonalElevation = 2.dp) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Query Metrics",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "${records.size} records",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(onClick = {
                    scope.launch {
                        runCatching { metricsRepository.deleteAll() }
                        records = emptyList()
                        selectedRecord = null
                    }
                }) {
                    Icon(Icons.Outlined.ClearAll, contentDescription = "Clear all")
                }
            }
        }
        HorizontalDivider()

        if (records.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = "No queries executed yet",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Execute a query to see performance metrics",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            return@Column
        }

        if (isTablet) {
            Row(Modifier.fillMaxSize()) {
                QueryMetricsList(
                    records = records,
                    selectedRecord = selectedRecord,
                    onSelect = { selectedRecord = it },
                    modifier = Modifier.weight(0.4f).fillMaxHeight(),
                )
                VerticalDivider()
                QueryMetricsDetail(
                    record = selectedRecord,
                    modifier = Modifier.weight(0.6f).fillMaxHeight(),
                )
            }
        } else {
            if (selectedRecord == null) {
                QueryMetricsList(
                    records = records,
                    selectedRecord = null,
                    onSelect = { selectedRecord = it },
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                QueryMetricsDetail(
                    record = selectedRecord,
                    modifier = Modifier.fillMaxSize(),
                    onBack = { selectedRecord = null },
                )
            }
        }
    }
}

@Composable
private fun QueryMetricsList(
    records: List<QueryMetrics>,
    selectedRecord: QueryMetrics?,
    onSelect: (QueryMetrics) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(records.sortedByDescending { it.capturedAt }) { record ->
            val isSelected = record == selectedRecord
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(record) },
                color = if (isSelected) MaterialTheme.colorScheme.secondaryContainer
                else MaterialTheme.colorScheme.surface,
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = formatTimestamp(record.capturedAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = formatExecutionTime(record.executionTimeMs),
                        style = MaterialTheme.typography.bodyMedium,
                        color = executionTimeColor(record.executionTimeMs),
                        fontFamily = FontFamily.Monospace,
                    )
                    Text(
                        text = record.queryText.ifBlank { "Unknown query" },
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            HorizontalDivider()
        }
    }
}

@Composable
private fun QueryMetricsDetail(
    record: QueryMetrics?,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    if (record == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "Select a query to view details",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    LazyColumn(
        modifier = modifier,
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
                    text = record.queryText.ifBlank { "—" },
                    modifier = Modifier.padding(8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatBadge(
                    label = "Time",
                    value = formatExecutionTime(record.executionTimeMs),
                    valueColor = executionTimeColor(record.executionTimeMs),
                )
                StatBadge(label = "Results", value = "${record.docsReturned} docs")
                StatBadge(
                    label = "Index",
                    value = if (record.indexesUsed.isNotEmpty()) "✓ Yes" else "✗ No",
                    valueColor = if (record.indexesUsed.isNotEmpty()) Color(0xFF4CAF50)
                    else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        if (!record.explainPlan.isNullOrBlank()) {
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
                        text = record.explainPlan,
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
private fun StatBadge(
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

@Composable
private fun executionTimeColor(ms: Long): Color = when {
    ms < 10 -> Color(0xFF4CAF50)
    ms < 100 -> MaterialTheme.colorScheme.onSurface
    else -> Color(0xFFFF9800)
}

private fun formatExecutionTime(ms: Long): String = when {
    ms < 1000 -> "${ms} ms"
    else -> "${"%.2f".format(ms / 1000.0)} s"
}

private fun formatTimestamp(epochMs: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(epochMs))
