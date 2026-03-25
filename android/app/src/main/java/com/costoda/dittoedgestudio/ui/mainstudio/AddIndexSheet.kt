package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoCollection

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddIndexSheet(
    collections: List<DittoCollection>,
    onAdd: (collection: String, fieldName: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedCollection by remember {
        mutableStateOf(collections.firstOrNull()?.name ?: "")
    }
    var fieldName by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var collectionDropdownExpanded by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
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

            // Field name input
            OutlinedTextField(
                value = fieldName,
                onValueChange = {
                    fieldName = it
                    errorMessage = null
                },
                label = { Text("Field Name") },
                placeholder = { Text("e.g. movie_id") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

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
                    text = "Each index covers one field. Multiple indexes can exist on the same collection.",
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
                    onClick = {
                        if (selectedCollection.isBlank() || fieldName.isBlank()) {
                            errorMessage = "Collection and field name are required"
                            return@TextButton
                        }
                        onAdd(selectedCollection, fieldName)
                    },
                ) {
                    Text("Create Index")
                }
            }
        }
    }
}
