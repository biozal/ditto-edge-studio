package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.QueryMetricsDetailPane
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.QueryMetricsListPane
import org.koin.compose.koinInject

/**
 * The "Query Metrics" scene-driven section entry-point composables (Task 4.3d).
 *
 * Two variants:
 *  - [QueryMetricsListSection]   — list-pane content (used by entry<QueryMetricsKey>)
 *  - [QueryMetricsDetailSection] — detail-pane content (used by entry<QueryMetricDetailKey>)
 *
 * The list pane owns loading/clearing state. The detail pane fetches by historyId from the
 * repository so it remains self-contained (no VM coupling needed).
 *
 * [QueryMetricsRepository] is injected via Koin (no session scope — it is a singleton
 * repository backed by the global Room database, identical to how the legacy
 * the legacy QueryMetricsScreen obtained it).
 */

/**
 * List-pane content for the Query Metrics section.
 *
 * @param selectedHistoryId The historyId currently shown in the detail pane (for row
 *   highlight). Pass null when nothing is selected.
 * @param onMetricPicked Called when the user taps a row. The caller (AppNavGraph) will
 *   push [com.costoda.dittoedgestudio.ui.navigation.QueryMetricDetailKey] onto the back
 *   stack; at ≥600dp the ListDetailSceneStrategy renders it side-by-side automatically.
 * @param onClearAll Called after a successful delete-all so the caller can strip any
 *   stale [com.costoda.dittoedgestudio.ui.navigation.QueryMetricDetailKey] from the stack.
 */
@Composable
fun QueryMetricsListSection(
    selectedHistoryId: Long?,
    onMetricPicked: (QueryMetrics) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val repository: QueryMetricsRepository = koinInject()
    QueryMetricsListPane(
        metricsRepository = repository,
        selectedHistoryId = selectedHistoryId,
        onMetricSelected = onMetricPicked,
        onClearAll = onClearAll,
        modifier = modifier.fillMaxSize(),
    )
}

/**
 * Detail-pane content for a single executed query.
 *
 * Fetches the metric by [historyId] from the repository. If the metric was deleted
 * (e.g. the user hit "Clear all" while this pane was visible) the empty state is shown.
 */
@Composable
fun QueryMetricsDetailSection(
    historyId: Long,
    modifier: Modifier = Modifier,
) {
    val repository: QueryMetricsRepository = koinInject()
    QueryMetricsDetailPane(
        historyId = historyId,
        metricsRepository = repository,
        modifier = modifier.fillMaxSize(),
    )
}
