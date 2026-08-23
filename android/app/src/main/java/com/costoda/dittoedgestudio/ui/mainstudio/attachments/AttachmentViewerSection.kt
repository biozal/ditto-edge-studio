package com.costoda.dittoedgestudio.ui.mainstudio.attachments

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import java.io.File

/**
 * Inline viewer for the attachments detected in a query result row's selected document.
 *
 * Rendering:
 *   - Header row: field name + human-readable size + content-type metadata
 *   - For image MIME type attachments that have been downloaded (file present in [cachedFiles]),
 *     a 200dp-tall inline preview thumbnail
 *   - "View" button — invokes [onView]; the VM downloads to the cache and updates the map
 *   - "Open" button — for non-images, launches `Intent.ACTION_VIEW` over a FileProvider URI
 *     once the file is cached
 *   - "Delete" button — defers to [onDelete] (caller opens a confirmation sheet)
 */
@Composable
fun AttachmentViewerSection(
    attachments: List<AttachmentInfo>,
    cachedFiles: Map<String, File>,
    onView: (AttachmentInfo) -> Unit,
    onDelete: (AttachmentInfo) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (attachments.isEmpty()) return
    Column(modifier = modifier.padding(top = 12.dp)) {
        Text(
            text = "Attachments",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        for (att in attachments) {
            AttachmentRow(
                attachment = att,
                cachedFile = cachedFiles[att.id],
                onView = { onView(att) },
                onDelete = { onDelete(att) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun AttachmentRow(
    attachment: AttachmentInfo,
    cachedFile: File?,
    onView: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val contentType = attachment.metadata["type"].orEmpty()
    val isImage = contentType.startsWith("image/")

    Card(modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp)) {
            // Header line: field name + size + content-type
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = attachment.fieldName,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = humanSize(attachment.len),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (contentType.isNotBlank()) {
                Text(
                    text = contentType,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }

            // Inline preview for cached images.
            if (isImage && cachedFile != null) {
                val bitmap = remember(cachedFile.absolutePath, cachedFile.lastModified()) {
                    android.graphics.BitmapFactory.decodeFile(cachedFile.absolutePath)
                }
                if (bitmap != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = "Attachment preview",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                    )
                }
            }

            // Actions row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (cachedFile == null) {
                    TextButton(onClick = onView) {
                        Icon(
                            Icons.Outlined.Visibility,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 4.dp),
                        )
                        Text(text = if (isImage) "View" else "Download")
                    }
                } else if (!isImage) {
                    TextButton(onClick = { openWithSystem(context, cachedFile, contentType) }) {
                        Icon(
                            Icons.Outlined.Visibility,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 4.dp),
                        )
                        Text(text = "Open")
                    }
                }
                Spacer(modifier = Modifier.width(8.dp))
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete attachment")
                }
            }
        }
    }
}

private fun humanSize(bytes: Long): String {
    return when {
        bytes < 1024L -> bytes.toString() + " B"
        bytes < 1024L * 1024L -> String.format(java.util.Locale.US, "%.1f KB", bytes / 1024.0)
        bytes < 1024L * 1024L * 1024L -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
        else -> String.format(java.util.Locale.US, "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
    }
}

private fun openWithSystem(context: android.content.Context, file: File, contentType: String) {
    val authority = context.packageName + ".fileprovider"
    val uri = FileProvider.getUriForFile(context, authority, file)
    val mimeType: String = if (contentType.isBlank()) {
        "application/octet-stream"
    } else {
        contentType
    }
    val intent = Intent(Intent.ACTION_VIEW)
    intent.setDataAndType(uri, mimeType)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    val chooser = Intent.createChooser(intent, "Open with")
    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(chooser)
}
