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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.CollectionPayloadInfo
import com.costoda.dittoedgestudio.domain.model.DatabaseMetrics
import com.costoda.dittoedgestudio.domain.model.StorageCategory
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private enum class Section(val label: String) {
    Files("Files"),
    Collections("Collections"),
}

@Composable
fun DiskUsageScreen(
    viewModel: DiskUsageViewModel,
    modifier: Modifier = Modifier,
) {
    val metrics by viewModel.metrics.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val lastUpdatedAt by viewModel.lastUpdatedAt.collectAsStateWithLifecycle()

    // Persist the selected section across rotations and process death. Enum default-saver
    // serialises by name; safe so long as Section is kept as-is in the same package.
    var selectedSection by rememberSaveable { mutableStateOf(Section.Files) }

    Column(modifier = modifier.fillMaxSize()) {
        HeaderBar(
            metrics = metrics,
            isLoading = isLoading,
            lastUpdatedAt = lastUpdatedAt,
            onRefresh = { viewModel.refresh() },
        )
        HorizontalDivider()

        when {
            isLoading && metrics == null -> CenteredProgress()
            metrics == null -> CenteredMessage("No disk usage data available")
            else -> MetricsBody(
                snap = metrics!!,
                selected = selectedSection,
                onSelect = { selectedSection = it },
            )
        }
    }
}

@Composable
private fun HeaderBar(
    metrics: DatabaseMetrics?,
    isLoading: Boolean,
    lastUpdatedAt: Long?,
    onRefresh: () -> Unit,
) {
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
                text = if (metrics != null) "${metrics.totalStorageBytesFormatted} on disk" else "—",
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = lastUpdatedAt.formatRefreshedAt(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(8.dp))
            IconButton(onClick = onRefresh, enabled = !isLoading) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .size(20.dp)
                            .semantics { contentDescription = "Refreshing" },
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    Icon(
                        Icons.Outlined.Refresh,
                        contentDescription = "Refresh",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricsBody(
    snap: DatabaseMetrics,
    selected: Section,
    onSelect: (Section) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        SectionSelector(selected = selected, onSelect = onSelect)
        when (selected) {
            Section.Files -> FilesPane(snap)
            Section.Collections -> CollectionsPane(snap)
        }
    }
}

@Composable
private fun SectionSelector(
    selected: Section,
    onSelect: (Section) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
    ) {
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            Section.entries.forEachIndexed { index, section ->
                SegmentedButton(
                    selected = selected == section,
                    onClick = { onSelect(section) },
                    shape = SegmentedButtonDefaults.itemShape(
                        index = index,
                        count = Section.entries.size,
                    ),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = SulfurYellow,
                        activeContentColor = Color.Black,
                        activeBorderColor = SulfurYellow,
                    ),
                ) {
                    Text(section.label)
                }
            }
        }
    }
}

// region Files pane ----------------------------------------------------------------

@Composable
private fun FilesPane(snap: DatabaseMetrics) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(snap.storage, key = { it.key.name }) { category ->
            StorageCard(
                category = category,
                percentOfTotal = snap.percentOfTotal(category.key),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun StorageCard(
    category: StorageCategory,
    percentOfTotal: Double,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = category.label.uppercase(Locale.getDefault()),
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = category.bytesFormatted,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${formatPercent(percentOfTotal)} of total",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.size(6.dp))
            Text(
                text = category.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// endregion ------------------------------------------------------------------------

// region Collections pane ----------------------------------------------------------

@Composable
private fun CollectionsPane(snap: DatabaseMetrics) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { CollectionsSummary(snap) }
        if (snap.collections.isEmpty()) {
            item { EmptyCollectionsCard() }
        } else {
            items(snap.collections, key = { it.name }) { info ->
                CollectionCard(
                    info = info,
                    percentOfPayload = snap.percentOfPayload(info),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun CollectionsSummary(snap: DatabaseMetrics) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = "Collections by CBOR payload size",
            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "${snap.collections.size} collections · ${snap.collectionPayloadBytesFormatted} total",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CollectionCard(
    info: CollectionPayloadInfo,
    percentOfPayload: Double,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = info.name,
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = info.cborPayloadBytesFormatted,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${formatPercent(percentOfPayload)} of payload · ${info.documentCountFormatted}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EmptyCollectionsCard() {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 1.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No collections in this database",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// endregion ------------------------------------------------------------------------

@Composable
private fun CenteredProgress() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun CenteredMessage(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private val refreshedAtFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("hh:mm:ss a", Locale.getDefault())

@Composable
private fun Long?.formatRefreshedAt(): String {
    val ts = this ?: return "Never refreshed"
    val text = remember(ts) {
        Instant.ofEpochMilli(ts).atZone(ZoneId.systemDefault()).format(refreshedAtFormatter)
    }
    return "Refreshed at $text"
}

private fun formatPercent(value: Double): String =
    if (value <= 0.0) "0.0%" else "%.1f%%".format(value)
