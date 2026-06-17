@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
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
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import kotlinx.coroutines.launch

/**
 * Editor for a new or existing subscription. Save is treated as a foreground
 * operation: tap Save → the sheet shows "Saving…", the buttons disable, and
 * swipe / back / tap-outside dismissal are blocked until the underlying Room
 * write commits. Only then does the sheet dismiss.
 *
 * This eliminates the previous fire-and-forget race where a fast back-tap could
 * cancel the in-flight save and silently lose the user's subscription.
 *
 * @param onSave Suspending block invoked when the user taps Save. Should perform
 *   the actual persistence and return only when the write is durable. Errors are
 *   returned via the `Result` so the sheet can stay open and let the user retry.
 * @param onDismiss Synchronous callback fired when the user explicitly cancels
 *   (Cancel button or system back while idle). Not invoked after a successful
 *   save — the save itself drives dismissal by clearing the upstream
 *   `editingSubscription` state, which removes this composable from composition.
 */
@Composable
fun SubscriptionEditorSheet(
    initial: DittoSubscription,
    onSave: suspend (name: String, query: String) -> Result<Unit>,
    onDismiss: () -> Unit,
) {
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // Block sheet dismissal (swipe, tap-outside, back-button) while a save is in
    // flight. Returning `false` from confirmValueChange rejects the requested
    // value change, leaving the sheet up until the save completes.
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { newValue ->
            !(isSaving && newValue == SheetValue.Hidden)
        },
    )

    var name by remember { mutableStateOf(initial.name) }
    var query by remember { mutableStateOf(initial.query) }

    ModalBottomSheet(
        onDismissRequest = { if (!isSaving) onDismiss() },
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = if (initial.id == 0L) "New Subscription" else "Edit Subscription",
                modifier = Modifier.padding(bottom = 16.dp),
            )

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name (optional)") },
                placeholder = { Text("My Subscription") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Query") },
                placeholder = { Text("SELECT * FROM collection") },
                minLines = 4,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )

            // Surface a save error inline so the user can correct the query and
            // retry without losing what they typed.
            errorMessage?.let { msg ->
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = msg,
                    color = androidx.compose.material3.MaterialTheme.colorScheme.error,
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onDismiss,
                    enabled = !isSaving,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Cancel")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = {
                        errorMessage = null
                        isSaving = true
                        scope.launch {
                            val result = onSave(name.trim(), query.trim())
                            if (result.isFailure) {
                                // Show the error and re-enable the form so the user
                                // can retry. The sheet stays in composition because
                                // editingSubscription is still non-null upstream.
                                errorMessage = result.exceptionOrNull()?.message ?: "Save failed"
                                isSaving = false
                            }
                            // On success: caller cleared editingSubscription, this
                            // composable leaves composition — no further work needed.
                        }
                    },
                    enabled = !isSaving && query.isNotBlank(),
                    modifier = Modifier.weight(1f),
                ) {
                    if (isSaving) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = androidx.compose.material3.MaterialTheme.colorScheme.onPrimary,
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Saving…")
                        }
                    } else {
                        Text("Save")
                    }
                }
            }
        }
    }
}
