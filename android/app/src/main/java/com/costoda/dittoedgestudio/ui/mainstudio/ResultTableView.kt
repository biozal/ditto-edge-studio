package com.costoda.dittoedgestudio.ui.mainstudio

import android.view.MotionEvent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import org.json.JSONObject

private const val CELL_MIN_WIDTH_DP = 120
private const val CELL_PADDING_DP = 8

@Composable
fun ResultTableView(
    documents: List<Map<String, Any?>>,
    onAddAttachmentRequest: (Map<String, Any?>) -> Unit,
    onDeleteAttachmentRequest: (Map<String, Any?>) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (documents.isEmpty()) {
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            Text(
                text = "No results",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    // Build column headers: _id first, then sorted remaining keys
    val columns = remember(documents) {
        val allKeys = documents.flatMap { it.keys }.toSet()
        buildList {
            if ("_id" in allKeys) add("_id")
            addAll(allKeys.filter { it != "_id" }.sorted())
        }
    }

    val scrollState: ScrollState = rememberScrollState()

    Column(modifier = modifier) {
        // Sticky header row
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(scrollState),
            ) {
                columns.forEach { col ->
                    Text(
                        text = col,
                        color = MaterialTheme.colorScheme.onSurface,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .widthIn(min = CELL_MIN_WIDTH_DP.dp)
                            .padding(CELL_PADDING_DP.dp),
                    )
                }
            }
        }
        HorizontalDivider()

        // Data rows
        LazyColumn {
            itemsIndexed(documents) { index, doc ->
                TableDataRow(
                    doc = doc,
                    columns = columns,
                    index = index,
                    scrollState = scrollState,
                    onAddAttachmentRequest = { onAddAttachmentRequest(doc) },
                    onDeleteAttachmentRequest = { onDeleteAttachmentRequest(doc) },
                )
                HorizontalDivider(thickness = 0.5.dp)
            }
        }
    }
}

/**
 * A single data row in the results table with right-click (secondary-button) and long-press
 * context menu support.
 *
 * The menu includes:
 * - "Copy JSON" — copies the full row document as pretty-printed JSON to the clipboard.
 * - "Add Attachment…" — opens the attachment picker sheet for this row.
 * - "Delete Attachment…" — opens the delete sheet; enabled only when the row has attachment tokens.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TableDataRow(
    doc: Map<String, Any?>,
    columns: List<String>,
    index: Int,
    scrollState: ScrollState,
    onAddAttachmentRequest: () -> Unit,
    onDeleteAttachmentRequest: () -> Unit,
) {
    var showContextMenu by remember { mutableStateOf(false) }
    val hasAttachments = remember(doc) { AttachmentInfo.detectTokens(doc).isNotEmpty() }
    // LocalClipboardManager is deprecated in favour of LocalClipboard (Compose UI 1.8+), but
    // the replacement's setClipEntry() is a suspend function and would still require a coroutine
    // scope. setText() is synchronous — no scope needed here.
    val clipboardManager = LocalClipboardManager.current
    val jsonString = remember(doc) { formatDocJson(doc) }

    Box(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    if (index % 2 == 0) MaterialTheme.colorScheme.surface
                    else MaterialTheme.colorScheme.surfaceContainerLowest,
                )
                .horizontalScroll(scrollState)
                .combinedClickable(
                    onClick = {},
                    onLongClick = { showContextMenu = true },
                )
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val event = awaitPointerEvent()
                        val motionEvent = event.motionEvent
                        if (motionEvent != null &&
                            motionEvent.action == MotionEvent.ACTION_DOWN &&
                            (motionEvent.buttonState and MotionEvent.BUTTON_SECONDARY) != 0
                        ) {
                            showContextMenu = true
                            event.changes.forEach { it.consume() }
                        }
                    }
                },
        ) {
            columns.forEach { col ->
                val value = doc[col]?.toString() ?: ""
                Text(
                    text = value,
                    color = MaterialTheme.colorScheme.onSurface,
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .widthIn(min = CELL_MIN_WIDTH_DP.dp)
                        .padding(CELL_PADDING_DP.dp),
                )
            }
        }

        // Context menu — opened by right-click (desktop) or long-press (touch).
        // "Copy JSON" copies the row document; attachment entries open the relevant sheet.
        DropdownMenu(
            expanded = showContextMenu,
            onDismissRequest = { showContextMenu = false },
        ) {
            DropdownMenuItem(
                text = { Text("Copy JSON") },
                onClick = {
                    showContextMenu = false
                    clipboardManager.setText(AnnotatedString(jsonString))
                },
            )
            DropdownMenuItem(
                text = { Text("Add Attachment…") },
                onClick = {
                    showContextMenu = false
                    onAddAttachmentRequest()
                },
            )
            DropdownMenuItem(
                text = { Text("Delete Attachment…") },
                enabled = hasAttachments,
                onClick = {
                    showContextMenu = false
                    onDeleteAttachmentRequest()
                },
            )
        }
    }
}

private fun formatDocJson(doc: Map<String, Any?>): String =
    runCatching {
        JSONObject(doc as Map<*, *>).toString(2)
    }.getOrElse {
        doc.entries.joinToString(",\n") { (k, v) -> "  \"$k\": $v" }.let { "{\n$it\n}" }
    }
