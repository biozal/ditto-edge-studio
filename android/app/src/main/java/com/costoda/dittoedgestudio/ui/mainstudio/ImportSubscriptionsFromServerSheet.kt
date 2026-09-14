@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.domain.model.DqlGenerator
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import kotlinx.coroutines.launch
import org.koin.compose.koinInject

private data class ImportableSubscription(
    val deviceName: String,
    val deviceInfo: String,
    val collectionName: String,
    val query: String,
    var isSelected: Boolean = false,
)

/**
 * Import subscriptions reported by the Ditto Server's `__small_peer_info` via the
 * HTTP API (parity with the SwiftUI `ImportSubscriptionsView`): fetches every peer's
 * `local_subscriptions`, filters out system collections (`__*`), dedupes against the
 * subscriptions already registered, and batch-imports the user's selection through
 * the studio session (so live registration + Room persistence match Add-by-hand).
 */
@Composable
fun ImportSubscriptionsFromServerSheet(
    viewModel: MainStudioViewModel,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val queryExecution: QueryExecutionService = koinInject()
    val scope = rememberCoroutineScope()
    val existing by viewModel.subscriptions.collectAsState()

    var importables by remember { mutableStateOf<List<ImportableSubscription>?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var importStatus by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            val result = queryExecution.execute("SELECT * FROM __small_peer_info", "HTTP")
            result.documents.flatMap { row -> importablesFromRow(row, existingQueries = existing) }
        }.onSuccess { importables = it }
            .onFailure { loadError = it.message ?: "Failed to fetch subscriptions from the server" }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Import subscriptions from server",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Select subscriptions reported by peers and the cloud. System collections are skipped.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            when {
                loadError != null -> Text(
                    text = loadError!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
                importables == null -> Text(
                    text = "Loading…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                importables!!.isEmpty() -> Text(
                    text = "Nothing importable — the peers have no new subscriptions.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                else -> LazyColumn(modifier = Modifier.height(320.dp)) {
                    items(importables!!, key = { "${it.deviceName}|${it.query}" }) { item ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Checkbox(
                                checked = item.isSelected,
                                onCheckedChange = { checked ->
                                    importables = importables!!.map {
                                        if (it.deviceName == item.deviceName && it.query == item.query) {
                                            it.copy(isSelected = checked)
                                        } else {
                                            it
                                        }
                                    }
                                },
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = item.collectionName,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    text = item.query,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    text = "${item.deviceName} • ${item.deviceInfo}".trim(' ', '•'),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }

            importStatus?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Done") }
                Spacer(modifier = Modifier.weight(1f))
                Button(
                    onClick = {
                        val selected = importables.orEmpty().filter { it.isSelected }
                        importStatus = "Importing 0 of ${selected.size}…"
                        scope.launch {
                            var done = 0
                            for (item in selected) {
                                val result = viewModel.addSubscription(item.collectionName, item.query)
                                if (result.isSuccess) {
                                    done++
                                    importStatus = "Imported $done of ${selected.size}…"
                                }
                            }
                            importStatus = "Imported $done of ${selected.size}"
                            onDismiss()
                        }
                    },
                    enabled = importables.orEmpty().any { it.isSelected } && importStatus == null,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Import")
                }
            }
        }
    }
}

/** Maps one `__small_peer_info` row into importable subscriptions. */
private fun importablesFromRow(
    row: Map<String, Any?>,
    existingQueries: List<com.costoda.dittoedgestudio.domain.model.DittoSubscription>,
): List<ImportableSubscription> {
    val deviceName = (row["device_name"] as? String) ?: (row["_id"] as? String) ?: "Unknown peer"
    val platform = (row["ditto_sdk_platform"] as? String) ?: "Unknown"
    val version = (row["ditto_sdk_version"] as? String) ?: ""
    val deviceInfo = "$platform $version".trim()

    val localSubs = row["local_subscriptions"] as? Map<*, *> ?: return emptyList()
    val queries = localSubs["queries"] as? List<*> ?: return emptyList()

    return queries.mapNotNull { q ->
        val query = (q as? Map<*, *>)?.get("query") as? String ?: return@mapNotNull null
        val collection = DqlGenerator.collectionName(query) ?: return@mapNotNull null
        // System collections (__presence etc.) and existing subs are skipped (parity).
        if (collection.startsWith("__")) return@mapNotNull null
        if (existingQueries.any { it.query.trim() == query.trim() }) return@mapNotNull null
        ImportableSubscription(
            deviceName = deviceName,
            deviceInfo = deviceInfo,
            collectionName = collection,
            query = query,
        )
    }
}
