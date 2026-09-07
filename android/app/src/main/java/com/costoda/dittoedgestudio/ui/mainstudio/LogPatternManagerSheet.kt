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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuDefaults
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
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.data.logging.LogPatternEngine
import com.costoda.dittoedgestudio.data.logging.LogPatternStore
import com.costoda.dittoedgestudio.domain.model.LogPattern
import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.costoda.dittoedgestudio.domain.model.displayName
import com.costoda.dittoedgestudio.domain.model.severityLabel
import com.ditto.kotlin.DittoLogLevel
import kotlinx.coroutines.launch

/** Severity colors, matching the VS Code analyzer palette. */
internal fun severityColor(severity: Int): Color = when (severity) {
    5 -> Color(0xFFFF5252)
    4 -> Color(0xFFFF8A52)
    3 -> Color(0xFFD4A017)
    2 -> Color(0xFF4EA1FF)
    else -> Color(0xFF888888)
}

@Composable
internal fun SeverityChip(severity: Int, modifier: Modifier = Modifier) {
    Surface(
        color = severityColor(severity).copy(alpha = 0.18f),
        shape = RoundedCornerShape(4.dp),
        modifier = modifier,
    ) {
        Text(
            text = severityLabel(severity),
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            color = severityColor(severity),
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

/**
 * Log-pattern manager (parity with the VS Code extension's Pattern Editor panel):
 * bundled read-only catalog plus user CRUD. Editing launches [LogPatternEditorDialog].
 */
@Composable
fun LogPatternManagerSheet(
    store: LogPatternStore,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val patterns by store.patterns.collectAsState()
    val patternErrors by store.patternErrors.collectAsState()
    val scope = rememberCoroutineScope()

    var editing: LogPattern? by remember { mutableStateOf(null) }
    var creating by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = "Log Patterns",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Regex patterns that flag trouble in the log stream. " +
                    "Bundled patterns are read-only; add your own below.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp),
            )

            if (patternErrors.isNotEmpty()) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp),
                ) {
                    Text(
                        text = patternErrors.entries.joinToString("\n") { (k, r) -> "$k: $r" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
            actionError?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }

            val bundled = patterns.values.filter { it.source == PatternSource.BUNDLED }.sortedBy { it.key }
            val user = patterns.values.filter { it.source == PatternSource.USER }.sortedBy { it.key }

            LazyColumn(modifier = Modifier.weight(1f, fill = false)) {
                item { PatternSectionHeader("Bundled") }
                items(bundled, key = { it.key }) { pattern ->
                    PatternRow(
                        pattern = pattern,
                        onEdit = null,
                        onDelete = null,
                    )
                }
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PatternSectionHeader("Your Patterns", modifier = Modifier.weight(1f))
                        TextButton(onClick = { creating = true }) {
                            Icon(Icons.Outlined.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Add")
                        }
                    }
                }
                if (user.isEmpty()) {
                    item {
                        Text(
                            text = "No custom patterns yet.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                }
                items(user, key = { it.key }) { pattern ->
                    PatternRow(
                        pattern = pattern,
                        onEdit = { editing = pattern },
                        onDelete = {
                            scope.launch {
                                runCatching { store.delete(pattern.key) }
                                    .onFailure { actionError = it.message }
                            }
                        },
                    )
                }
            }
        }
    }

    if (creating) {
        LogPatternEditorDialog(
            title = "New Pattern",
            bundledKeys = store.bundledKeys,
            existingKeys = patterns.keys,
            initialKey = "",
            initial = LogPatternBody("", 3, ""),
            store = store,
            onSave = { key, body -> store.add(key, body) },
            onDismiss = { creating = false },
        )
    } else {
        editing?.let { existing ->
            LogPatternEditorDialog(
                title = "Edit Pattern",
                bundledKeys = store.bundledKeys,
                existingKeys = patterns.keys - existing.key,
                initialKey = existing.key,
                initial = existing.body,
                store = store,
                keyEditable = false,
                onSave = { key, body -> store.update(key, body) },
                onDismiss = { editing = null },
            )
        }
    }
}

@Composable
private fun PatternSectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun PatternRow(
    pattern: LogPattern,
    onEdit: (() -> Unit)?,
    onDelete: (() -> Unit)?,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SeverityChip(pattern.severity)
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (pattern.source == PatternSource.BUNDLED) {
                    Icon(
                        Icons.Outlined.Lock,
                        contentDescription = "Bundled (read-only)",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(12.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                }
                Text(
                    text = pattern.key,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                )
                pattern.body.userTag?.let {
                    Text(
                        text = "  #$it",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFFB08FFF),
                    )
                }
            }
            Text(
                text = pattern.body.pattern,
                fontFamily = FontFamily.Monospace,
                fontSize = 10.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(
                text = pattern.body.recommendation,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
        onEdit?.let {
            IconButton(onClick = it) {
                Icon(Icons.Outlined.Edit, contentDescription = "Edit ${pattern.key}", modifier = Modifier.size(18.dp))
            }
        }
        onDelete?.let {
            IconButton(onClick = it) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = "Delete ${pattern.key}",
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

/**
 * Pattern editor with live validation and a test-line field (parity with the
 * extension's `pattern-form`): shows ✓/✗ match against a pasted log line.
 */
@Composable
private fun LogPatternEditorDialog(
    title: String,
    bundledKeys: Set<String>,
    existingKeys: Set<String>,
    initialKey: String,
    initial: LogPatternBody,
    store: LogPatternStore,
    keyEditable: Boolean = true,
    onSave: suspend (String, LogPatternBody) -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var key by remember { mutableStateOf(initialKey) }
    var pattern by remember { mutableStateOf(initial.pattern) }
    var severity by remember { mutableStateOf(initial.severity) }
    var recommendation by remember { mutableStateOf(initial.recommendation) }
    var levelFilterName by remember { mutableStateOf(initial.levelFilter ?: "") }
    var tagFilter by remember { mutableStateOf(initial.tagFilter ?: "") }
    var userTag by remember { mutableStateOf(initial.userTag ?: "") }
    var testLine by remember { mutableStateOf("") }
    var severityExpanded by remember { mutableStateOf(false) }
    var levelExpanded by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    val body = LogPatternBody(
        pattern = pattern,
        severity = severity,
        recommendation = recommendation,
        levelFilter = levelFilterName.ifBlank { null },
        tagFilter = tagFilter.ifBlank { null },
        userTag = userTag.ifBlank { null },
    )

    val keyError = when {
        key.isBlank() -> "Key is required"
        keyEditable && bundledKeys.contains(key) -> "Key collides with a bundled pattern"
        keyEditable && existingKeys.contains(key) -> "A pattern with this key already exists"
        else -> null
    }
    val patternError = LogPatternEngine.rejectReason(
        key.ifBlank { "draft" },
        body,
        PatternSource.USER,
    )
    val regexValid = pattern.isNotEmpty() && runCatching { pattern.toRegex(RegexOption.IGNORE_CASE) }.isSuccess

    val testResult = if (testLine.isBlank()) null else {
        val probe = LogPatternEngine(emptyMap())
        if (!regexValid) false to "Pattern is not a valid regex"
        else {
            // Level filter is an exact equality, so test at the filter's level;
            // the component is derived from the pasted line via the same
            // heuristic the capture pipeline uses.
            val probeLevel = com.costoda.dittoedgestudio.domain.model.parseLevelFilter(body.levelFilter)
                ?: DittoLogLevel.Warning
            val matches = probe.matches(
                body,
                level = probeLevel,
                tag = com.costoda.dittoedgestudio.domain.model.LogComponent.heuristic(testLine).displayName,
                message = testLine,
            )
            matches to (if (matches) "Matches" else "No match")
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = key,
                    onValueChange = { key = it },
                    label = { Text("Key") },
                    enabled = keyEditable,
                    isError = key.isNotBlank() && keyError != null,
                    supportingText = { keyError?.takeIf { key.isNotBlank() }?.let { Text(it) } },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = pattern,
                    onValueChange = { pattern = it },
                    label = { Text("Pattern (regex, case-insensitive)") },
                    isError = pattern.isNotEmpty() && !regexValid,
                    supportingText = {
                        when {
                            pattern.isNotEmpty() && !regexValid -> Text("✗ Invalid regex")
                            regexValid -> Text("✓ Valid regex")
                            else -> {}
                        }
                    },
                    minLines = 2,
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ExposedDropdownMenuBox(
                        expanded = severityExpanded,
                        onExpandedChange = { severityExpanded = it },
                        modifier = Modifier.weight(1f),
                    ) {
                        OutlinedTextField(
                            value = "$severity — ${severityLabel(severity)}",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Severity") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = severityExpanded) },
                            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                            singleLine = true,
                        )
                        ExposedDropdownMenu(
                            expanded = severityExpanded,
                            onDismissRequest = { severityExpanded = false },
                        ) {
                            (5 downTo 1).forEach { sev ->
                                DropdownMenuItem(
                                    text = { Text("$sev — ${severityLabel(sev)}", color = severityColor(sev)) },
                                    onClick = { severity = sev; severityExpanded = false },
                                )
                            }
                        }
                    }
                    ExposedDropdownMenuBox(
                        expanded = levelExpanded,
                        onExpandedChange = { levelExpanded = it },
                        modifier = Modifier.weight(1f),
                    ) {
                        OutlinedTextField(
                            value = levelFilterName.ifBlank { "Any" },
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Level (exact)") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = levelExpanded) },
                            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                            singleLine = true,
                        )
                        ExposedDropdownMenu(
                            expanded = levelExpanded,
                            onDismissRequest = { levelExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Any") },
                                onClick = { levelFilterName = ""; levelExpanded = false },
                            )
                            listOf("error", "warning", "info", "debug", "verbose").forEach { lvl ->
                                DropdownMenuItem(
                                    text = { Text(lvl) },
                                    onClick = { levelFilterName = lvl; levelExpanded = false },
                                )
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = recommendation,
                    onValueChange = { recommendation = it },
                    label = { Text("Recommendation (required)") },
                    isError = recommendation.isBlank() && pattern.isNotEmpty(),
                    minLines = 2,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = tagFilter,
                    onValueChange = { tagFilter = it },
                    label = { Text("Component filter (regex, optional)") },
                    supportingText = { Text("e.g. ^Sync\$ — matches the entry's component name") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = userTag,
                    onValueChange = { userTag = it },
                    label = { Text("User tag (optional label applied to matching lines)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = testLine,
                    onValueChange = { testLine = it },
                    label = { Text("Test line (paste a log line to try the pattern)") },
                    supportingText = {
                        testResult?.let { (matched, label) ->
                            Text(
                                text = "${if (matched) "✓" else "✗"} $label",
                                color = if (matched) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                    minLines = 2,
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )

                saveError?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    saving = true
                    scope.launch {
                        runCatching { onSave(key.trim(), body) }
                            .onSuccess { onDismiss() }
                            .onFailure { saveError = it.message ?: "Save failed" }
                        saving = false
                    }
                },
                enabled = !saving && keyError == null && patternError == null,
            ) {
                Text(if (saving) "Saving…" else "Save")
            }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
        },
    )
}
