@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.JsonImportService
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Import JSON data into a collection (port of SwiftUI's `ImportDataView`):
 * pick a JSON file containing an array of objects (each needs `_id`), choose an
 * existing or new collection, pick upsert vs initial-insert mode, and watch
 * progress. Runs in batches of 50 with per-document fallback (see
 * [JsonImportService]).
 */
@Composable
fun ImportJsonSheet(
    importService: JsonImportService,
    collections: List<DittoCollection>,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var selectedFileLabel by remember { mutableStateOf<String?>(null) }
    var fileBytes by remember { mutableStateOf<String?>(null) }
    var collection by remember { mutableStateOf("") }
    var useInitialMode by remember { mutableStateOf(false) }
    var expandedCollections by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    var progressText by remember { mutableStateOf<String?>(null) }
    var resultText by remember { mutableStateOf<String?>(null) }
    var errorText by remember { mutableStateOf<String?>(null) }

    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        resultText = null
        errorText = null
        if (uri != null) {
            scope.launch {
                try {
                    val bytes = withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    } ?: throw JsonImportService.ImportException("Could not read the selected file")
                    val text = String(bytes, Charsets.UTF_8)
                    fileBytes = text
                    selectedFileLabel = uri.lastPathSegment ?: "file"
                    // Validation errors surface immediately (parity with SwiftUI picking flow).
                    importService.validate(text)
                } catch (e: Exception) {
                    fileBytes = null
                    selectedFileLabel = null
                    errorText = e.message ?: "Invalid file"
                }
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Import JSON Data",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "File must be a JSON array of objects; every object needs an \"_id\" field. " +
                    "Imported in batches of 50.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = { filePicker.launch(arrayOf("application/json", "text/*", "*/*")) },
                    enabled = !importing,
                ) {
                    Text(selectedFileLabel ?: "Choose JSON file…")
                }
            }

            // Target collection: existing via dropdown, or a new name.
            ExposedDropdownMenuBox(
                expanded = expandedCollections,
                onExpandedChange = { expandedCollections = it },
            ) {
                OutlinedTextField(
                    value = collection,
                    onValueChange = { collection = it },
                    label = { Text("Collection") },
                    placeholder = { Text("existing or new name") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expandedCollections) },
                    singleLine = true,
                    enabled = !importing,
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryEditable),
                )
                ExposedDropdownMenu(
                    expanded = expandedCollections,
                    onDismissRequest = { expandedCollections = false },
                ) {
                    collections.forEach { c ->
                        DropdownMenuItem(
                            text = { Text(c.name) },
                            onClick = {
                                collection = c.name
                                expandedCollections = false
                            },
                        )
                    }
                }
            }

            // Insert mode (SwiftUI InsertType parity).
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = !useInitialMode,
                        onClick = { useInitialMode = false },
                        enabled = !importing,
                    )
                    Text("Upsert (update existing)", style = MaterialTheme.typography.bodySmall)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = useInitialMode,
                        onClick = { useInitialMode = true },
                        enabled = !importing,
                    )
                    Text("Initial import", style = MaterialTheme.typography.bodySmall)
                }
            }

            progressText?.let {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            resultText?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
            errorText?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onDismiss,
                    enabled = !importing,
                    modifier = Modifier.weight(1f),
                ) { Text("Cancel") }
                Button(
                    onClick = {
                        val data = fileBytes ?: return@Button
                        importing = true
                        errorText = null
                        resultText = null
                        progressText = null
                        scope.launch {
                            try {
                                val result = importService.importData(
                                    documentData = data,
                                    collection = collection.trim(),
                                    insertType = if (useInitialMode) {
                                        JsonImportService.InsertType.INITIAL
                                    } else {
                                        JsonImportService.InsertType.REGULAR
                                    },
                                    onProgress = { current, total, docId ->
                                        progressText = "Importing $current of $total${docId?.let { " ($it)" } ?: ""}"
                                    },
                                )
                                progressText = null
                                resultText = "Imported ${result.successCount} document(s)" +
                                    if (result.failureCount > 0) {
                                        ", ${result.failureCount} failed: ${result.errors.take(3).joinToString("; ")}"
                                    } else {
                                        ""
                                    }
                            } catch (e: Exception) {
                                progressText = null
                                errorText = e.message ?: "Import failed"
                            }
                            importing = false
                        }
                    },
                    enabled = !importing && fileBytes != null && collection.isNotBlank(),
                    modifier = Modifier.weight(1f).padding(start = 8.dp),
                ) {
                    Text(if (importing) "Importing…" else "Import")
                }
            }
        }
    }
}
