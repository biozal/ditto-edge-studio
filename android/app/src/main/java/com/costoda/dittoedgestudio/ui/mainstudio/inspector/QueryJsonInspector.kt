package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import com.costoda.dittoedgestudio.ui.mainstudio.attachments.AttachmentViewerSection
import org.json.JSONObject
import java.io.File

@Composable
fun QueryJsonInspector(
    selectedDocument: Map<String, Any?>?,
    cachedAttachments: Map<String, File>,
    onViewAttachment: (AttachmentInfo) -> Unit,
    onDeleteAttachment: (AttachmentInfo) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (selectedDocument == null) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "Select a result to inspect",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        return
    }

    val jsonString = remember(selectedDocument) {
        runCatching {
            JSONObject(selectedDocument as Map<*, *>).toString(2)
        }.getOrElse {
            selectedDocument.entries.joinToString(",\n") { (k, v) -> "  \"$k\": $v" }
                .let { "{\n$it\n}" }
        }
    }

    val attachments = remember(selectedDocument) {
        AttachmentInfo.detectTokens(selectedDocument)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        SelectionContainer {
            Text(
                text = jsonString,
                style = MaterialTheme.typography.bodySmall.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                ),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(12.dp),
            )
        }

        if (attachments.isNotEmpty()) {
            AttachmentViewerSection(
                attachments = attachments,
                cachedFiles = cachedAttachments,
                onView = onViewAttachment,
                onDelete = onDeleteAttachment,
            )
        }
    }
}
