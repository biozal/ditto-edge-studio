package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ClearAll
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.catch
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
 *  - Collect [metricsRepository]'s per-database Flow (lifecycle-aware), so new captures
 *    appear live without a manual refresh. The header's refresh button remains as a
 *    harmless manual escape: it re-subscribes the Flow (and clears a shown load error).
 *  - Surface load failures as an inline error text instead of swallowing them into an
 *    empty list.
 *  - Show "Clear all" button in the header; clears this database's rows and notifies
 *    the caller via [onClearAll] (so the detail pane can reset its selection on parent
 *    side).
 *  - Calls [onMetricSelected] when the user taps a row; the caller decides whether to push
 *    [QueryMetricDetailKey] (compact) or let the ListDetailSceneStrategy show it side-by-side
 *    (expanded).
 *
 * @param databaseId The Ditto databaseId string whose captures are listed.
 * @param selectedMetricsId The metrics-row id ([QueryMetrics.id]) currently shown in the
 *   detail pane; used to highlight the active row. Keyed on the row's own primary key —
 *   NOT historyId, which is non-unique (history dedups re-runs) and would highlight
 *   every capture of a repeated query. Pass null if nothing is selected.
 * @param onMetricSelected Callback when the user taps a row.
 * @param onClearAll Callback after a successful clear-all so the caller can remove a
 *   stale [QueryMetricDetailKey] from the back stack.
 */
@Composable
fun QueryMetricsListPane(
    metricsRepository: QueryMetricsRepository,
    databaseId: String,
    selectedMetricsId: Long?,
    onMetricSelected: (QueryMetrics) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    var loadError by remember { mutableStateOf<String?>(null) }
    // Bump to re-subscribe the Flow (manual refresh escape); the Flow itself already
    // emits on every Room change, so this is only needed to recover from a shown error.
    var refreshKey by remember { mutableIntStateOf(0) }

    val records by remember(databaseId, refreshKey) {
        metricsRepository.observeByDatabase(databaseId)
            .catch { e ->
                loadError = e.message ?: "Failed to load query metrics"
                emit(emptyList())
            }
    }.collectAsStateWithLifecycle(initialValue = emptyList())

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
                // No "Query Metrics" title here: the scaffold's top app bar
                // already shows the section name, and repeating it inside a
                // ~200dp list pane left it fighting two 48dp icon buttons and
                // the record count for the same row. `weight(1f)` hands out
                // *remaining* space, so the title was squeezed to its minimum
                // intrinsic width and wrapped one character per line — "Q / u /
                // e / ry" — with the count drawn over the top of it.
                Text(
                    text = "${records.size} records",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {
                        scope.launch {
                            // Only pop any open detail when the delete actually
                            // succeeded — otherwise the detail would vanish while the
                            // rows still exist in Room. The collected Flow empties the
                            // list automatically on success.
                            try {
                                metricsRepository.deleteAllByDatabase(databaseId)
                                onClearAll()
                            } catch (c: CancellationException) {
                                // Never swallow cancellation (runCatching would).
                                throw c
                            } catch (e: Exception) {
                                loadError = e.message ?: "Failed to clear query metrics"
                            }
                        }
                    },
                    enabled = records.isNotEmpty(),
                ) {
                    Icon(
                        Icons.Outlined.ClearAll,
                        contentDescription = "Clear all",
                        tint = if (records.isEmpty()) MaterialTheme.colorScheme.outline
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = {
                    loadError = null
                    refreshKey++
                }) {
                    Icon(
                        Icons.Outlined.Refresh,
                        contentDescription = "Refresh records",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        HorizontalDivider()

        loadError?.let { message ->
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

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
            // Already ordered captured_at DESC, id DESC by the DAO query.
            items(records, key = { it.id }) { record ->
                val isSelected = record.id == selectedMetricsId
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
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = formatQueryTimestamp(record.capturedAt),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = formatQueryExecutionTime(record.executionTimeMs),
                                style = MaterialTheme.typography.bodyMedium,
                                color = queryExecutionTimeColor(record.executionTimeMs),
                                fontFamily = FontFamily.Monospace,
                            )
                            Spacer(Modifier.width(6.dp))
                            // Index-used indicator — matches the SwiftUI row's green/orange dot.
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(
                                        color = if (record.indexesUsed.isNotEmpty()) Color(0xFF4CAF50)
                                        else Color(0xFFFF9800),
                                        shape = CircleShape,
                                    ),
                            )
                        }
                        Text(
                            text = record.queryText.ifBlank { "Unknown query" },
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurface,
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
