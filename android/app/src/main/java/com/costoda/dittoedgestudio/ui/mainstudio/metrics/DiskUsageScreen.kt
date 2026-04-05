package com.costoda.dittoedgestudio.ui.mainstudio.metrics

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.DataObject
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel

@Composable
fun DiskUsageScreen(
    viewModel: DiskUsageViewModel,
    modifier: Modifier = Modifier,
) {
    val metrics by viewModel.metrics.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val lastUpdated by viewModel.lastUpdatedText.collectAsState()

    LaunchedEffect(Unit) {
        while (isActive) {
            viewModel.refresh()
            delay(15_000)
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Surface(tonalElevation = 2.dp) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Disk Usage",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = lastUpdated,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { viewModel.refresh() }) {
                    Icon(Icons.Outlined.Refresh, contentDescription = "Refresh")
                }
            }
        }

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
                    text = "No disk usage data available",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Column
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                TotalStorageCard(totalFormatted = snap.totalStorageBytesFormatted)
            }

            item {
                Text(
                    text = "STORAGE BREAKDOWN",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }

            item {
                StorageBreakdownList(
                    storeBytes = snap.storeBytes,
                    storeBytesFormatted = snap.storeBytesFormatted,
                    replicationBytes = snap.replicationBytes,
                    replicationBytesFormatted = snap.replicationBytesFormatted,
                    attachmentsBytes = snap.attachmentsBytes,
                    attachmentsBytesFormatted = snap.attachmentsBytesFormatted,
                    authBytes = snap.authBytes,
                    authBytesFormatted = snap.authBytesFormatted,
                    walShmBytes = snap.walShmBytes,
                    walShmBytesFormatted = snap.walShmBytesFormatted,
                    logsBytes = snap.logsBytes,
                    logsBytesFormatted = snap.logsBytesFormatted,
                    otherBytes = snap.otherBytes,
                    otherBytesFormatted = snap.otherBytesFormatted,
                    totalBytes = snap.totalStorageBytes,
                )
            }

            if (snap.collectionBreakdown.isNotEmpty()) {
                item {
                    Text(
                        text = "COLLECTIONS (${snap.collectionBreakdown.size})",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
                items(snap.collectionBreakdown) { info ->
                    MetricCard(
                        title = info.collectionName,
                        value = info.estimatedBytesFormatted,
                        subtitle = info.documentCountFormatted,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
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
            }
        }
    }
}

@Composable
private fun TotalStorageCard(totalFormatted: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = "Total Storage",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Text(
                text = totalFormatted,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                ),
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@Composable
private fun StorageBreakdownList(
    storeBytes: Long,
    storeBytesFormatted: String,
    replicationBytes: Long,
    replicationBytesFormatted: String,
    attachmentsBytes: Long,
    attachmentsBytesFormatted: String,
    authBytes: Long,
    authBytesFormatted: String,
    walShmBytes: Long,
    walShmBytesFormatted: String,
    logsBytes: Long,
    logsBytesFormatted: String,
    otherBytes: Long,
    otherBytesFormatted: String,
    totalBytes: Long,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StorageCategoryRow(
            icon = Icons.Outlined.Storage,
            label = "Store",
            bytes = storeBytes,
            formatted = storeBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.Sync,
            label = "Replication",
            bytes = replicationBytes,
            formatted = replicationBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.AttachFile,
            label = "Attachments",
            bytes = attachmentsBytes,
            formatted = attachmentsBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.Lock,
            label = "Auth",
            bytes = authBytes,
            formatted = authBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.DataObject,
            label = "WAL/SHM",
            bytes = walShmBytes,
            formatted = walShmBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.Description,
            label = "Logs",
            bytes = logsBytes,
            formatted = logsBytesFormatted,
            totalBytes = totalBytes,
        )
        StorageCategoryRow(
            icon = Icons.Outlined.FolderOpen,
            label = "Other",
            bytes = otherBytes,
            formatted = otherBytesFormatted,
            totalBytes = totalBytes,
        )
    }
}

@Composable
private fun StorageCategoryRow(
    icon: ImageVector,
    label: String,
    bytes: Long,
    formatted: String,
    totalBytes: Long,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
            )
            LinearProgressIndicator(
                progress = { bytes.toFloat() / maxOf(totalBytes, 1).toFloat() },
                modifier = Modifier.fillMaxWidth(),
                trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                text = formatted,
                style = MaterialTheme.typography.labelMedium.copy(
                    fontFamily = FontFamily.Monospace,
                ),
                textAlign = androidx.compose.ui.text.style.TextAlign.End,
            )
        }
    }
}
