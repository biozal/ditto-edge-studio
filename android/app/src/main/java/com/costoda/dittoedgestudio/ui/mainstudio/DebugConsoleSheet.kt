@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

private val MUTATING_PREFIXES = listOf("INSERT", "UPDATE", "DELETE", "EVICT", "ALTER", "CREATE", "DROP")

internal fun isMutatingStatement(statement: String): Boolean {
    val first = statement.trimStart().takeWhile { it.isLetter() }.uppercase()
    return first in MUTATING_PREFIXES
}

private data class ConsoleEntry(
    val statement: String,
    val response: String,
    val isError: Boolean,
)

/** Pretty-print when the reply parses as JSON; keep raw text otherwise (e.g. `ERROR: …`). */
internal fun formatDebugResponse(raw: String): String = try {
    val json = kotlinx.serialization.json.Json { prettyPrint = true }
    json.encodeToString(kotlinx.serialization.json.JsonElement.serializer(), json.parseToJsonElement(raw))
} catch (_: Exception) {
    raw
}

/**
 * The debug console (SDK 5.1 `debug_socket`) — full-syntax DQL against the live
 * embedded Ditto over the unix socket, FIFO-serialized by the session's
 * [com.costoda.dittoedgestudio.data.ditto.DebugSocketClient].
 *
 * [onExecute] is the whole talk-to-Ditto seam: production wires it to
 * `StudioSession.executeDebugStatement`; tests substitute a fake.
 */
@Composable
fun DebugConsoleSheet(
    onExecute: suspend (String) -> String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    var statement by remember { mutableStateOf("") }
    val entries = remember { mutableStateListOf<ConsoleEntry>() }
    var running by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<String?>(null) }
    var bannerError by remember { mutableStateOf<String?>(null) }

    fun execute(q: String) {
        scope.launch {
            running = true
            bannerError = null
            try {
                val response = onExecute(q)
                entries.add(ConsoleEntry(q, formatDebugResponse(response), response.startsWith("ERROR")))
            } catch (e: Exception) {
                entries.add(ConsoleEntry(q, e.message ?: "failed", isError = true))
            }
            running = false
            if (entries.isNotEmpty()) listState.animateScrollToItem(entries.size - 1)
        }
    }

    fun run(raw: String) {
        val q = raw.trim()
        if (q.isEmpty() || running) return
        if (isMutatingStatement(q)) {
            confirming = q
            return
        }
        execute(q)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f, fill = false)
                .padding(horizontal = 16.dp)
                .padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "Debug Console",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "DQL against this app's own Ditto instance over the debug socket.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Live-mutation warning (extension parity): 5.1 defaults
            // dql_enable_remote_full_syntax to true, so EVICT/ALTER SYSTEM work.
            Surface(
                color = Color(0xFFFF9500).copy(alpha = 0.12f),
                shape = MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier.padding(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.Warning,
                        contentDescription = null,
                        tint = Color(0xFFFF9500),
                    )
                    Text(
                        "Full-syntax DQL — INSERT/UPDATE/DELETE/EVICT/ALTER SYSTEM apply immediately.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFFFF9500),
                    )
                }
            }

            bannerError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false)
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                itemsIndexed(entries) { _, entry ->
                    Column {
                        Text(
                            "❯ ${entry.statement}",
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        SelectionContainer {
                            Text(
                                entry.response,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                                color = if (entry.isError) {
                                    MaterialTheme.colorScheme.error
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                            )
                        }
                    }
                }
                if (entries.isEmpty()) {
                    item {
                        Text(
                            "e.g. SELECT * FROM system:dual",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = statement,
                    onValueChange = { statement = it },
                    placeholder = { Text("SELECT * FROM …") },
                    singleLine = true,
                    enabled = !running,
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.weight(1f),
                )
                if (running) {
                    Text("Running…", style = MaterialTheme.typography.bodySmall)
                } else {
                    IconButton(onClick = { run(statement) }) {
                        Icon(
                            Icons.Outlined.PlayArrow,
                            contentDescription = "Run statement",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                TextButton(
                    onClick = { entries.clear() },
                    enabled = entries.isNotEmpty() && !running,
                ) { Text("Clear") }
                Spacer(modifier = Modifier.weight(1f))
                OutlinedButton(onClick = onDismiss) { Text("Close") }
            }
        }
    }

    // Mutation confirmation (parity with the extension's confirm modal).
    confirming?.let { q ->
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text("Run mutating statement?") },
            text = { Text(q, fontFamily = FontFamily.Monospace, fontSize = 12.sp) },
            confirmButton = {
                Button(onClick = {
                    confirming = null
                    execute(q)
                }) {
                    Text("Run")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null }) { Text("Cancel") }
            },
        )
    }
}
