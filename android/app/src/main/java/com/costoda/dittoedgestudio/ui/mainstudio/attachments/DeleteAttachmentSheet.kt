package com.costoda.dittoedgestudio.ui.mainstudio.attachments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo

/**
 * Bottom-sheet that lets the user select which attachments on the current document to remove.
 *
 * The selected list is returned via [onConfirm]; the caller (`QueryEditorViewModel.deleteAttachments`)
 * issues one DQL `UPDATE c SET <field> = NULL WHERE _id = '<id>'` per selected attachment.
 *
 * Defaults: nothing pre-selected — the user must explicitly tick rows before Delete is enabled.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun DeleteAttachmentSheet(
    attachments: List<AttachmentInfo>,
    onDismiss: () -> Unit,
    onConfirm: (List<AttachmentInfo>) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val selected = remember { mutableStateOf(emptySet<String>()) }  // attachment ids

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text(text = "Delete Attachments", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Choose attachments to remove from the document.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))

            if (attachments.isEmpty()) {
                Text(
                    text = "No attachments detected on this document.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            } else {
                for (att in attachments) {
                    val isChecked = att.id in selected.value
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(
                            checked = isChecked,
                            onCheckedChange = { checked ->
                                selected.value = if (checked) {
                                    selected.value + att.id
                                } else {
                                    selected.value - att.id
                                }
                            },
                        )
                        Spacer(Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(text = att.fieldName, style = MaterialTheme.typography.titleSmall)
                            val mime = att.metadata["type"].orEmpty()
                            val subtitle = buildString {
                                append(humanSize(att.len))
                                if (mime.isNotBlank()) append(" · ").append(mime)
                            }
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        val toDelete = attachments.filter { it.id in selected.value }
                        onConfirm(toDelete)
                    },
                    enabled = selected.value.isNotEmpty(),
                ) { Text("Delete Selected") }
            }
        }
    }
}

private fun humanSize(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> String.format(java.util.Locale.US, "%.1f KB", bytes / 1024.0)
    bytes < 1024L * 1024 * 1024 -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024))
    else -> String.format(java.util.Locale.US, "%.2f GB", bytes / (1024.0 * 1024 * 1024))
}
