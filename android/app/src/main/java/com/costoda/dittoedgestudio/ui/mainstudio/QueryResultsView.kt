package com.costoda.dittoedgestudio.ui.mainstudio

import android.content.Context
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import com.costoda.dittoedgestudio.domain.model.QueryResult
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.costoda.dittoedgestudio.ui.mainstudio.attachments.AttachmentPickerSheet
import com.costoda.dittoedgestudio.ui.mainstudio.attachments.DeleteAttachmentSheet
import com.costoda.dittoedgestudio.ui.mainstudio.profile.ProfileViewerView

@Composable
fun QueryResultsView(
    queryResult: QueryResult?,
    displayedDocuments: List<Map<String, Any?>>,
    isExecuting: Boolean,
    executionError: String?,
    captureProfilingData: Boolean,
    lastQueryText: String,
    onDocumentSelected: (Map<String, Any?>) -> Unit,
    onAddConfirm: (uri: Uri, docId: String, collection: String, fieldName: String, metadata: Map<String, String>, context: Context) -> Unit,
    onDeleteConfirm: (docId: String, collection: String, attachments: List<AttachmentInfo>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    var addTargetRow by remember { mutableStateOf<Map<String, Any?>?>(null) }
    var deleteTargetRow by remember { mutableStateOf<Map<String, Any?>?>(null) }

    Column(modifier = modifier) {
        // ── View switcher ─────────────────────────────────────────────────────
        DittoConnectedButtonGroup(
            options = listOf("JSON", "TABLE", "PROFILE"),
            selectedIndex = selectedTabIndex,
            onSelect = { selectedTabIndex = it },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

        if (isExecuting) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        // ── Content ───────────────────────────────────────────────────────────
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            when {
                executionError != null && selectedTabIndex != 2 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = executionError,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
                queryResult == null && selectedTabIndex != 2 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "Run a query to see results",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                queryResult?.documents?.isEmpty() == true && selectedTabIndex != 2 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "No results",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                selectedTabIndex == 0 -> {
                    ResultJsonView(
                        documents = displayedDocuments,
                        onDocumentSelected = onDocumentSelected,
                        onAddAttachmentRequest = { addTargetRow = it },
                        onDeleteAttachmentRequest = { deleteTargetRow = it },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                selectedTabIndex == 1 -> {
                    ResultTableView(
                        documents = displayedDocuments,
                        onAddAttachmentRequest = { addTargetRow = it },
                        onDeleteAttachmentRequest = { deleteTargetRow = it },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                else -> {
                    ProfileViewerView(
                        profile = queryResult?.profile,
                        metricsEnabled = captureProfilingData,
                        lastQueryText = lastQueryText,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }

    // ── Attachment picker sheet ────────────────────────────────────────────────
    val addRow = addTargetRow
    if (addRow != null) {
        val context = LocalContext.current
        val docId = addRow["_id"] as? String
        val coll = currentCollectionFromQuery(lastQueryText)
        if (docId == null || coll == null) {
            addTargetRow = null
        } else {
            AttachmentPickerSheet(
                onDismiss = { addTargetRow = null },
                onConfirm = { uri, fieldName, metadata ->
                    onAddConfirm(uri, docId, coll, fieldName, metadata, context)
                    addTargetRow = null
                },
            )
        }
    }

    // ── Delete attachment sheet ────────────────────────────────────────────────
    val deleteRow = deleteTargetRow
    if (deleteRow != null) {
        val docId = deleteRow["_id"] as? String
        val coll = currentCollectionFromQuery(lastQueryText)
        val atts = remember(deleteRow) { AttachmentInfo.detectTokens(deleteRow) }
        if (docId == null || coll == null || atts.isEmpty()) {
            deleteTargetRow = null
        } else {
            DeleteAttachmentSheet(
                attachments = atts,
                onDismiss = { deleteTargetRow = null },
                onConfirm = { selected ->
                    onDeleteConfirm(docId, coll, selected)
                    deleteTargetRow = null
                },
            )
        }
    }
}
