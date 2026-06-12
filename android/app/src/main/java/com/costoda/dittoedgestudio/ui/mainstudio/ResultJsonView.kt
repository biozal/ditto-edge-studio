package com.costoda.dittoedgestudio.ui.mainstudio

import android.view.MotionEvent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun ResultJsonView(
    documents: List<Map<String, Any?>>,
    onDocumentSelected: (Map<String, Any?>) -> Unit,
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

    LazyColumn(modifier = modifier) {
        itemsIndexed(documents) { index, doc ->
            DocumentCard(
                index = index,
                document = doc,
                onClick = { onDocumentSelected(doc) },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DocumentCard(
    index: Int,
    document: Map<String, Any?>,
    onClick: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    var showContextMenu by remember { mutableStateOf(false) }
    val id = document["_id"]?.toString() ?: "doc_$index"
    val jsonString = remember(document) { formatJson(document) }
    val clipboardManager = LocalClipboardManager.current
    val scope = rememberCoroutineScope()

    // Right-click (secondary button) context menu affordance for desktop windowing.
    // Detects the secondary-button press via the underlying MotionEvent.BUTTON_SECONDARY
    // flag on the PointerEvent's motionEvent — the most reliable API for secondary-button
    // detection in Compose on Android (the stable Kotlin-level PointerButtons.isSecondaryPressed
    // extension is Android-platform only and has resolution issues in alpha builds).
    val rightClickModifier = Modifier.pointerInput(Unit) {
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
    }

    Box(modifier = Modifier.fillMaxWidth()) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 2.dp)
                .then(rightClickModifier),
            shape = MaterialTheme.shapes.small,
            tonalElevation = 1.dp,
        ) {
            Column(
                modifier = Modifier
                    .clickable {
                        expanded = !expanded
                        if (!expanded) onClick()
                    }
                    .padding(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (expanded) Icons.Filled.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = if (expanded) "Collapse" else "Expand",
                        modifier = Modifier.height(18.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "#${index + 1}  $id",
                        color = MaterialTheme.colorScheme.onSurface,
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp,
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 4.dp),
                    )
                }
                if (expanded) {
                    Spacer(Modifier.height(4.dp))
                    HorizontalDivider()
                    Spacer(Modifier.height(4.dp))
                    SelectionContainer {
                        Text(
                            text = jsonString,
                            color = MaterialTheme.colorScheme.onSurface,
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                            ),
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.surfaceContainerLowest)
                                .padding(8.dp),
                        )
                    }
                }
            }
        }

        // Right-click context menu — "Copy JSON" copies the full document JSON.
        DropdownMenu(
            expanded = showContextMenu,
            onDismissRequest = { showContextMenu = false },
        ) {
            DropdownMenuItem(
                text = { Text("Copy JSON") },
                onClick = {
                    showContextMenu = false
                    scope.launch {
                        clipboardManager.setText(AnnotatedString(jsonString))
                    }
                },
            )
        }
    }
}

private fun formatJson(doc: Map<String, Any?>): String {
    return runCatching {
        val json = JSONObject(doc as Map<*, *>)
        json.toString(2)
    }.getOrElse {
        doc.entries.joinToString(",\n") { (k, v) -> "  \"$k\": $v" }
            .let { "{\n$it\n}" }
    }
}
