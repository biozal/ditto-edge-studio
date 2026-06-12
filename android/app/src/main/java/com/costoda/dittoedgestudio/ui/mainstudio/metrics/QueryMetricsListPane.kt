package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Data Panel (list pane) for the Query Metrics scene-driven section (Task 4.3d).
 *
 * Renders the executed-query list previously hand-rolled inside the self-contained
 * QueryMetricsScreen. Extracted so the [ListDetailSceneStrategy] can provide the two
 * panes (list + detail) at the navigation level rather than inside a single composable.
 *
 * Responsibilities:
 *  - Load all metrics on first composition via [metricsRepository].
 *  - Show "Clear all" button in the header; clears both the DB and notifies the caller
 *    via [onClearAll] (so the detail pane can reset its selection on parent side).
 *  - Calls [onMetricSelected] when the user taps a row; the caller decides whether to push
 *    [QueryMetricDetailKey] (compact) or let the ListDetailSceneStrategy show it side-by-side
 *    (expanded).
 *
 * @param selectedHistoryId The historyId currently shown in the detail pane; used to
 *   highlight the active row. Pass null if nothing is selected.
 * @param onMetricSelected Callback when the user taps a row.
 * @param onClearAll Callback after a successful clear-all so the caller can remove a
 *   stale [QueryMetricDetailKey] from the back stack.
 */
@Composable
fun QueryMetricsListPane(
    metricsRepository: QueryMetricsRepository,
    selectedHistoryId: Long?,
    onMetricSelected: (QueryMetrics) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    var records by remember { mutableStateOf<List<QueryMetrics>>(emptyList()) }

    LaunchedEffect(Unit) {
        runCatching { records = metricsRepository.getAllMetrics() }
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Header
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 2.dp,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Query Metrics",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
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
                        onClearAll()
                    }
                }) {
                    Icon(
                        Icons.Outlined.ClearAll,
                        contentDescription = "Clear all",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
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

        LazyColumn {
            items(records.sortedByDescending { it.capturedAt }) { record ->
                val isSelected = record.historyId == selectedHistoryId
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onMetricSelected(record) },
                    color = if (isSelected) MaterialTheme.colorScheme.secondaryContainer
                    else MaterialTheme.colorScheme.surface,
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = formatQueryTimestamp(record.capturedAt),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = formatQueryExecutionTime(record.executionTimeMs),
                            style = MaterialTheme.typography.bodyMedium,
                            color = queryExecutionTimeColor(record.executionTimeMs),
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
}

// ---------------------------------------------------------------------------
// Internal formatting helpers (package-internal so QueryMetricsDetailPane can reuse)
// ---------------------------------------------------------------------------

internal fun formatQueryExecutionTime(ms: Long): String = when {
    ms < 1000 -> "$ms ms"
    else -> "${"%.2f".format(ms / 1000.0)} s"
}

internal fun formatQueryTimestamp(epochMs: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(epochMs))

@Composable
internal fun queryExecutionTimeColor(ms: Long): androidx.compose.ui.graphics.Color = when {
    ms < 10L -> androidx.compose.ui.graphics.Color(0xFF4CAF50)
    ms < 100L -> MaterialTheme.colorScheme.onSurface
    else -> androidx.compose.ui.graphics.Color(0xFFFF9800)
}
