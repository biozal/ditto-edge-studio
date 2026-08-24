@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Top sub-toolbar for the Query Workbench. Sits between the scaffold's [TopAppBar] and
 * the DQL editor. Houses Run (with progress swap), the Local/HTTP target chip, and the
 * Options popover (Capture profiling data / Capture query metrics switches).
 *
 * Stateless by design — the caller (Query section) reads/writes the session-scoped flows
 * on `QueryWorkbenchState`; this composable is a pure render of the supplied state plus
 * callback handlers. Keeps the composable trivially testable without a VM scope.
 */
@Composable
fun QueryWorkbenchTopToolbar(
    queryText: String,
    isExecuting: Boolean,
    executeMode: String,
    executeModes: List<String>,
    captureProfilingData: Boolean,
    captureQueryMetrics: Boolean,
    onRun: () -> Unit,
    onExplain: () -> Unit,
    onModeSelect: (String) -> Unit,
    onCaptureProfilingDataChange: (Boolean) -> Unit,
    onCaptureQueryMetricsChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    // SwiftUI parity: JSON data import + DQL statement templates + results export.
    onImportJson: (() -> Unit)? = null,
    onGenerateStatement: ((com.costoda.dittoedgestudio.domain.model.DqlStatementKind) -> Unit)? = null,
) {
    var targetMenuExpanded by remember { mutableStateOf(false) }
    var optionsExpanded by remember { mutableStateOf(false) }
    val keyboardController = LocalSoftwareKeyboardController.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // Run / progress.
            IconButton(
                onClick = {
                    keyboardController?.hide()
                    onRun()
                },
                enabled = !isExecuting && queryText.isNotBlank(),
                modifier = Modifier.testTag("QueryToolbar.Run"),
            ) {
                if (isExecuting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.PlayArrow,
                        contentDescription = "Run query",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            // Local/HTTP target chip + dropdown.
            FilterChip(
                selected = false,
                onClick = { targetMenuExpanded = true },
                modifier = Modifier.testTag("QueryToolbar.TargetChip"),
                label = { Text(executeMode, style = MaterialTheme.typography.labelMedium) },
                leadingIcon = {
                    Icon(
                        imageVector = if (executeMode == "HTTP") Icons.Outlined.Cloud
                        else Icons.Outlined.Storage,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
                trailingIcon = {
                    Icon(
                        imageVector = Icons.Outlined.KeyboardArrowDown,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
            )
            DropdownMenu(
                expanded = targetMenuExpanded,
                onDismissRequest = { targetMenuExpanded = false },
            ) {
                executeModes.forEach { mode ->
                    DropdownMenuItem(
                        modifier = Modifier.testTag("QueryToolbar.TargetMenuItem.$mode"),
                        text = {
                            Text(
                                text = if (mode == executeMode) "$mode  ✓" else mode,
                                color = if (mode == executeMode) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurface,
                            )
                        },
                        onClick = {
                            targetMenuExpanded = false
                            onModeSelect(mode)
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Options popover.
            IconButton(
                onClick = { optionsExpanded = true },
                modifier = Modifier.testTag("QueryToolbar.Options"),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Tune,
                    contentDescription = "Query options",
                    tint = MaterialTheme.colorScheme.onSurface,
                )
            }
            DropdownMenu(
                expanded = optionsExpanded,
                onDismissRequest = { optionsExpanded = false },
                modifier = Modifier.width(280.dp),
            ) {
                // Runs EXPLAIN against the editor text (SwiftUI parity: the capture
                // auto-opens the Metrics inspector tab — handled by the ViewModel).
                DropdownMenuItem(
                    text = { Text("Run EXPLAIN") },
                    enabled = !isExecuting && queryText.isNotBlank(),
                    onClick = {
                        optionsExpanded = false
                        keyboardController?.hide()
                        onExplain()
                    },
                    modifier = Modifier.testTag("QueryOptions.RunExplain"),
                )
                // This switch writes the same DataStore pref as Settings →
                // "Collect Metrics" — keep the label identical so users can
                // recognize it as the same setting.
                DropdownMenuItem(
                    text = { Text("Collect Metrics") },
                    onClick = { onCaptureProfilingDataChange(!captureProfilingData) },
                    trailingIcon = {
                        Switch(
                            checked = captureProfilingData,
                            onCheckedChange = { onCaptureProfilingDataChange(it) },
                            modifier = Modifier.testTag("QueryOptions.CaptureProfiling"),
                        )
                    },
                )
                // DQL generator (SwiftUI "Generate SELECT/INSERT/…" parity).
                if (onGenerateStatement != null) {
                    HorizontalDivider()
                    com.costoda.dittoedgestudio.domain.model.DqlStatementKind.entries.forEach { kind ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    "Generate ${kind.name.lowercase().replaceFirstChar { it.uppercase() }}",
                                )
                            },
                            onClick = {
                                optionsExpanded = false
                                onGenerateStatement(kind)
                            },
                            modifier = Modifier.testTag("QueryOptions.Generate${kind.name}"),
                        )
                    }
                }
                if (onImportJson != null) {
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Import JSON data…") },
                        onClick = {
                            optionsExpanded = false
                            onImportJson()
                        },
                        modifier = Modifier.testTag("QueryOptions.ImportJson"),
                    )
                }
                // Per-query capture is gated on Collect Metrics in the VM — a live
                // switch here would silently no-op while Collect Metrics is off, so
                // disable it to make the dependency visible.
                DropdownMenuItem(
                    text = { Text("Capture query metrics") },
                    enabled = captureProfilingData,
                    onClick = { onCaptureQueryMetricsChange(!captureQueryMetrics) },
                    trailingIcon = {
                        Switch(
                            checked = captureQueryMetrics,
                            enabled = captureProfilingData,
                            onCheckedChange = { onCaptureQueryMetricsChange(it) },
                            modifier = Modifier.testTag("QueryOptions.CaptureMetrics"),
                        )
                    },
                )
            }
        }
    }
}
