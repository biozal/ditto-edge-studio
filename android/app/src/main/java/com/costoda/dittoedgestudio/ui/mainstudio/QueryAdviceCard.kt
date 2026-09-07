package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.QueryAdvice
import com.costoda.dittoedgestudio.domain.model.QueryIndexSuggestion

/**
 * Card surfacing the result of an `ADVISE` run (SDK 5.1): the advised statement,
 * then either the outcome text ("no keys to advise on") or one row per index
 * suggestion with an Apply button. Applying executes the CREATE INDEX statement
 * verbatim — only after the confirmation dialog (parity with the VS Code
 * extension's confirm modal).
 */
@Composable
fun QueryAdviceCard(
    advice: QueryAdvice,
    onApply: suspend (QueryIndexSuggestion) -> Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Per-suggestion state keyed by statement (extension parity: pending/created/failed).
    val states = remember { mutableStateMapOf<String, String>() }
    var confirming by remember { mutableStateOf<QueryIndexSuggestion?>(null) }
    val scope = rememberCoroutineScope()

    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        ),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.Lightbulb,
                    contentDescription = null,
                    tint = com.costoda.dittoedgestudio.ui.theme.SulfurYellowDeep,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "Index advice",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        Icons.Outlined.Close,
                        contentDescription = "Dismiss index advice",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Text(
                advice.statement,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            if (advice.suggestions.isEmpty()) {
                Text(
                    advice.outcome ?: "No index suggestions.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                advice.suggestions.forEach { suggestion ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                suggestion.statement,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (suggestion.reason.isNotEmpty()) {
                                Text(
                                    suggestion.reason,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        when (states[suggestion.statement]) {
                            "created" -> Text(
                                "✓ Created",
                                style = MaterialTheme.typography.bodySmall,
                                color = androidx.compose.ui.graphics.Color(0xFF34C759),
                            )
                            "failed" -> Text(
                                "✗ Failed",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                            else -> Button(
                                onClick = { confirming = suggestion },
                                contentPadding = ButtonDefaults.TextButtonContentPadding,
                            ) {
                                Text("Apply", style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }
        }
    }

    confirming?.let { suggestion ->
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text("Create index on ${suggestion.collection}?") },
            text = {
                Text(suggestion.statement, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            },
            confirmButton = {
                Button(onClick = {
                    confirming = null
                    scope.launch {
                        val ok = onApply(suggestion)
                        states[suggestion.statement] = if (ok) "created" else "failed"
                    }
                }) {
                    Text("Create Index")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null }) { Text("Cancel") }
            },
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun QueryAdviceCardPreview() {
    EdgeStudioTheme {
        QueryAdviceCard(
            advice = QueryAdvice(
                statement = "SELECT * FROM cars WHERE make = 'Honda'",
                outcome = null,
                suggestions = listOf(
                    QueryIndexSuggestion(
                        collection = "cars",
                        reason = "equality predicates on `make`",
                        statement = "CREATE INDEX IF NOT EXISTS adv_cars_make ON default:`cars` (`make` ASC)",
                    ),
                ),
            ),
            onApply = { true },
            onDismiss = {},
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun QueryAdviceCardEmptyPreview() {
    EdgeStudioTheme {
        QueryAdviceCard(
            advice = QueryAdvice(
                statement = "SELECT * FROM cars",
                outcome = "no keys to advise on",
                suggestions = emptyList(),
            ),
            onApply = { true },
            onDismiss = {},
        )
    }
}
