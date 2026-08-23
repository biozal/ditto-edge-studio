package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.IndexField
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Editable row state for one index key. Two or more rows produce a
 * composite index (Ditto SDK 5.1+). */
private class FieldDraft {
    var name by mutableStateOf("")
    var ascending by mutableStateOf(true)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddIndexSheet(
    collections: List<DittoCollection>,
    onAdd: suspend (collection: String, fields: List<IndexField>) -> String?,
    onDismiss: () -> Unit,
) {
    var selectedCollection by remember {
        mutableStateOf(collections.firstOrNull()?.name ?: "")
    }
    // The sheet can open before the collections observer has emitted; if the
    // remembered selection is still blank when collections arrive, default to the
    // first one. Never overwrites a selection the user already made.
    LaunchedEffect(collections) {
        if (selectedCollection.isBlank()) {
            collections.firstOrNull()?.let { selectedCollection = it.name }
        }
    }
    val fields = remember { mutableStateListOf(FieldDraft()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isCreating by remember { mutableStateOf(false) }
    var collectionDropdownExpanded by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    ModalBottomSheet(
        // Block dismissal (swipe, scrim tap, back) while a create is in flight so the
        // DQL isn't cancelled mid-flight — same blocked-dismissal design as the
        // subscription editor sheet.
        onDismissRequest = { if (!isCreating) onDismiss() },
        sheetGesturesEnabled = !isCreating,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Add Index",
                style = MaterialTheme.typography.titleMedium,
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Collection picker
            ExposedDropdownMenuBox(
                expanded = collectionDropdownExpanded,
                onExpandedChange = { collectionDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = selectedCollection,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Collection") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = collectionDropdownExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(
                    expanded = collectionDropdownExpanded,
                    onDismissRequest = { collectionDropdownExpanded = false },
                ) {
                    collections.forEach { collection ->
                        DropdownMenuItem(
                            text = { Text(collection.name) },
                            onClick = {
                                selectedCollection = collection.name
                                collectionDropdownExpanded = false
                            },
                        )
                    }
                    if (collections.isEmpty()) {
                        DropdownMenuItem(
                            text = {
                                Text(
                                    "No collections available",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            },
                            onClick = { collectionDropdownExpanded = false },
                            enabled = false,
                        )
                    }
                }
            }

            // Index fields — one row per key, in index order. key(draft) keeps each
            // row's focus/IME state attached to its draft across removals.
            fields.forEachIndexed { index, draft ->
                key(draft) {
                    FieldRow(
                        index = index,
                        draft = draft,
                        canRemove = fields.size > 1,
                        onRemove = { fields.remove(draft) },
                        onNameEdited = { errorMessage = null },
                    )
                }
            }

            TextButton(onClick = { fields.add(FieldDraft()) }) {
                Icon(
                    imageVector = Icons.Outlined.Add,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.size(4.dp))
                Text("Add field")
            }

            // Info note
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(
                    imageVector = Icons.Outlined.Info,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = "One field creates a standard index; two or more fields create a " +
                        "composite index. Field order matters: put equality-filtered fields " +
                        "first, then range or sort fields.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Error message
            errorMessage?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
                TextButton(
                    enabled = !isCreating,
                    onClick = {
                        val specs = fields
                            .map { IndexField(name = it.name.trim(), ascending = it.ascending) }
                            .filter { it.name.isNotEmpty() }
                        if (selectedCollection.isBlank() || specs.isEmpty()) {
                            errorMessage = "Collection and at least one field are required"
                            return@TextButton
                        }
                        val names = specs.map { it.name }
                        val duplicate = names.firstOrNull { n -> names.count { it == n } > 1 }
                        if (duplicate != null) {
                            errorMessage = "Duplicate field '$duplicate' — each field can appear only once in an index."
                            return@TextButton
                        }
                        scope.launch {
                            isCreating = true
                            try {
                                val error = onAdd(selectedCollection, specs)
                                if (error == null) {
                                    onDismiss()
                                } else {
                                    errorMessage = error
                                }
                            } catch (ce: CancellationException) {
                                // The studio session was closed (or the sheet left
                                // composition) mid-create. Don't leave the spinner
                                // stuck and don't misreport it as an index failure.
                                errorMessage = "Studio closed before the index could be created"
                                throw ce
                            } finally {
                                isCreating = false
                            }
                        }
                    },
                ) {
                    Text(if (isCreating) "Creating…" else "Create Index")
                }
            }
        }
    }
}

@Composable
private fun FieldRow(
    index: Int,
    draft: FieldDraft,
    canRemove: Boolean,
    onRemove: () -> Unit,
    onNameEdited: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = draft.name,
            onValueChange = {
                draft.name = it
                onNameEdited()
            },
            label = { Text("Field ${index + 1}") },
            placeholder = { Text("e.g. movie_id") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        FilterChip(
            selected = draft.ascending,
            onClick = { draft.ascending = true },
            label = { Text("ASC") },
        )
        FilterChip(
            selected = !draft.ascending,
            onClick = { draft.ascending = false },
            label = { Text("DESC") },
        )
        IconButton(
            onClick = onRemove,
            enabled = canRemove,
        ) {
            Icon(
                imageVector = Icons.Outlined.Close,
                contentDescription = "Remove field",
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun AddIndexSheetPreview() {
    EdgeStudioTheme {
        AddIndexSheet(
            collections = listOf(
                DittoCollection(name = "tasks", docCount = 42),
                DittoCollection(name = "users", docCount = 7),
            ),
            onAdd = { _, _ -> null },
            onDismiss = {},
        )
    }
}
