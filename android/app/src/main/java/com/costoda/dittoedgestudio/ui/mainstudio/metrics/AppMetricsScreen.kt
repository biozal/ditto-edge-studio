package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import kotlinx.coroutines.launch

@Composable
fun AppMetricsScreen(
    viewModel: AppMetricsViewModel,
    modifier: Modifier = Modifier,
) {
    val metrics by viewModel.metrics.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val lastUpdated by viewModel.lastUpdatedText.collectAsState()
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) { viewModel.startAutoRefresh() }
    DisposableEffect(Unit) { onDispose { viewModel.stopAutoRefresh() } }

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
                    text = "App Metrics",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = lastUpdated,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { scope.launch { viewModel.refresh() } }) {
                    Icon(Icons.Outlined.Refresh, contentDescription = "Refresh")
                }
            }
        }
        HorizontalDivider()

        if (isLoading && metrics == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            return@Column
        }

        val snap = metrics
        if (snap == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "No metrics available",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Column
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { MetricsSectionHeader("Process") }
            item { MetricsGrid(snap.processMetrics()) }

            item { MetricsSectionHeader("Queries") }
            item { MetricsGrid(snap.queryMetrics()) }

            item { MetricsSectionHeader("Storage") }
            item { MetricsGrid(snap.storageMetrics()) }

            if (snap.collectionBreakdown.isNotEmpty()) {
                item { MetricsSectionHeader("Collections") }
                items(snap.collectionBreakdown) { info ->
                    MetricCard(
                        title = info.collectionName,
                        value = info.estimatedBytesFormatted,
                        subtitle = info.documentCountFormatted,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricsSectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun MetricsGrid(items: List<Pair<String, String>>) {
    val chunked = items.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
        chunked.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                row.forEach { (title, value) ->
                    MetricCard(title = title, value = value, modifier = Modifier.weight(1f))
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

private fun AppMetrics.processMetrics(): List<Pair<String, String>> = listOf(
    "Resident Memory" to residentMemoryFormatted,
    "Virtual Memory" to virtualMemoryFormatted,
    "CPU Time" to cpuTimeFormatted,
    "Open FDs" to "$openFileDescriptors",
    "Uptime" to uptimeFormatted,
)

private fun AppMetrics.queryMetrics(): List<Pair<String, String>> = listOf(
    "Total Queries" to "$totalQueryCount",
    "Avg Latency" to avgLatencyFormatted,
    "Last Latency" to lastLatencyFormatted,
)

private fun AppMetrics.storageMetrics(): List<Pair<String, String>> = listOf(
    "Store" to storeBytesFormatted,
    "Replication" to replicationBytesFormatted,
    "Attachments" to attachmentsBytesFormatted,
    "Auth" to authBytesFormatted,
    "WAL/SHM" to walShmBytesFormatted,
    "Logging" to logsBytesFormatted,
    "Other" to otherBytesFormatted,
    "Total" to totalStorageBytesFormatted,
)
