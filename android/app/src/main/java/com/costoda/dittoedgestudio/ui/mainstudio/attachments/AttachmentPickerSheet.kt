package com.costoda.dittoedgestudio.ui.mainstudio.attachments

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

private const val SOFT_LIMIT_BYTES = 10L * 1024 * 1024     // 10 MB warning
private const val HARD_LIMIT_BYTES = 20L * 1024 * 1024     // 20 MB block

/**
 * Bottom-sheet picker for adding an attachment to the selected document.
 *
 * Flow: tap "Choose File" → Android system file picker via [ActivityResultContracts.OpenDocument]
 * → uri is captured; the sheet reads `len` via `ContentResolver.openFileDescriptor` and the MIME
 * via `getType(uri)`. The user names the target field; size is validated (10 MB soft warning,
 * 20 MB hard block). On confirm, [onConfirm] is invoked with `(uri, fieldName, metadata)`.
 *
 * The caller copies the URI to a temp file (Ditto's `newAttachment` takes a path, not a Uri).
 * That copy happens inside [com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel.addAttachment]
 * so the sheet stays free of IO concerns.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttachmentPickerSheet(
    onDismiss: () -> Unit,
    onConfirm: (uri: Uri, fieldName: String, metadata: Map<String, String>) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current

    var pickedUri by remember { mutableStateOf<Uri?>(null) }
    var sizeBytes by remember { mutableStateOf<Long?>(null) }
    var detectedMime by remember { mutableStateOf("") }
    var fieldName by remember { mutableStateOf("") }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri != null) {
            pickedUri = uri
            sizeBytes = context.contentResolver
                .openFileDescriptor(uri, "r")?.use { it.statSize }
            detectedMime = context.contentResolver.getType(uri).orEmpty()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text(text = "Add Attachment", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(12.dp))

            TextButton(onClick = { launcher.launch(arrayOf("*/*")) }) {
                Text(if (pickedUri == null) "Choose File…" else "Choose Different File…")
            }

            if (pickedUri != null) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Selected: ${pickedUri!!.lastPathSegment ?: "file"}",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = "Type: ${detectedMime.ifBlank { "(unknown)" }}",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    text = "Size: ${humanSize(sizeBytes ?: 0)}",
                    style = MaterialTheme.typography.bodySmall,
                )

                val size = sizeBytes ?: 0
                if (size > HARD_LIMIT_BYTES) {
                    Text(
                        text = "File exceeds 20 MB — too large to attach.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                } else if (size > SOFT_LIMIT_BYTES) {
                    Text(
                        text = "File exceeds 10 MB. Large attachments may affect sync performance.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = fieldName,
                onValueChange = { fieldName = it },
                label = { Text("Field name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            Spacer(Modifier.height(16.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Spacer(Modifier.padding(end = 8.dp))
                val canConfirm = pickedUri != null &&
                    fieldName.isNotBlank() &&
                    (sizeBytes ?: 0) <= HARD_LIMIT_BYTES
                Button(
                    onClick = {
                        val uri = pickedUri ?: return@Button
                        val md = if (detectedMime.isNotBlank()) mapOf("type" to detectedMime) else emptyMap()
                        onConfirm(uri, fieldName.trim(), md)
                    },
                    enabled = canConfirm,
                ) { Text("Add Attachment") }
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
