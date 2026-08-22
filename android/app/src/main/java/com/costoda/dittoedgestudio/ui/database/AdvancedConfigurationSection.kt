package com.costoda.dittoedgestudio.ui.database

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsValidator
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel

/**
 * The Advanced Configuration section of the Register/Edit Database screen:
 * per-database collection sync scopes and startup system settings.
 *
 * Port of the SwiftUI editor's advanced section — see
 * docs/ADVANCED_DATABASE_CONFIG.md and plans/android/advanced-database-config-parity.md.
 */
@Composable
fun AdvancedConfigurationSection(viewModel: DatabaseEditorViewModel) {
    val isExpanded by viewModel.isAdvancedExpanded.collectAsStateWithLifecycle()
    val scopes by viewModel.collectionSyncScopes.collectAsStateWithLifecycle()
    val settings by viewModel.startupSettings.collectAsStateWithLifecycle()
    val hasErrors by viewModel.hasAdvancedValidationErrors.collectAsStateWithLifecycle()
    val hasCorruptScopes by viewModel.hasCorruptSyncScopes.collectAsStateWithLifecycle()
    val discardCorrupt by viewModel.discardCorruptSyncScopes.collectAsStateWithLifecycle()
    val resetRequested by viewModel.resetToDefaultsRequested.collectAsStateWithLifecycle()
    val applyFailures by viewModel.lastApplyFailures.collectAsStateWithLifecycle()
    val scopesUnverified by viewModel.lastApplyScopesUnverified.collectAsStateWithLifecycle()

    Spacer(modifier = Modifier.height(20.dp))

    // Disclosure row — owned expansion state, not a library disclosure control, so it
    // is reachable by UI tests and behaves identically for a user.
    Surface(
        onClick = { viewModel.isAdvancedExpanded.value = !isExpanded },
        modifier = Modifier
            .fillMaxWidth()
            .testTag("AdvancedConfigDisclosure"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = if (isExpanded) {
                    Icons.Filled.KeyboardArrowDown
                } else {
                    Icons.Filled.KeyboardArrowRight
                },
                contentDescription = if (isExpanded) "Collapse" else "Expand",
                tint = MaterialTheme.colorScheme.secondary,
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "Advanced Configuration",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = viewModel.advancedSummary(),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.secondary,
            )
            if (hasErrors) {
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "needs attention",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
    androidx.compose.material3.HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))

    if (!isExpanded) return

    // --- Collection Sync Scopes ---
    if (hasCorruptScopes) {
        CorruptScopesBanner(
            discard = discardCorrupt,
            onDiscardChange = { viewModel.discardCorruptSyncScopes.value = it },
        )
        Spacer(modifier = Modifier.height(8.dp))
    }

    Text(
        text = "COLLECTION SYNC SCOPES",
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        color = MaterialTheme.colorScheme.secondary,
    )
    Text(
        text = "Control where each user collection may synchronize. " +
            "Changes apply the next time this connection starts.",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
    )
    Spacer(modifier = Modifier.height(8.dp))

    scopes.forEach { row ->
        SyncScopeRow(
            row = row,
            error = viewModel.syncScopeError(row.id),
            onCollectionChange = { viewModel.updateScopeCollection(row.id, it) },
            onScopeChange = { viewModel.updateScope(row.id, it) },
            onRemove = { viewModel.removeSyncScope(row.id) },
        )
        Spacer(modifier = Modifier.height(8.dp))
    }

    TextButton(
        onClick = { viewModel.addSyncScope() },
        enabled = scopes.size < AdvancedSettingsValidator.MAX_ROW_COUNT,
        modifier = Modifier.testTag("AddSyncScopeButton"),
    ) {
        Text("+ Add collection")
    }

    Column(modifier = Modifier.padding(top = 2.dp)) {
        SyncScope.entries.forEach { scope ->
            Text(
                text = "• ${scope.displayName} — ${scope.explanation}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
    }
    Text(
        text = "Sync scopes and startup settings are not included when sharing a database by QR code.",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
        modifier = Modifier.padding(top = 4.dp),
    )

    Spacer(modifier = Modifier.height(16.dp))

    // --- Startup System Settings ---
    Text(
        text = "STARTUP SYSTEM SETTINGS",
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        color = MaterialTheme.colorScheme.secondary,
    )
    Text(
        text = "Applied after Ditto opens and before sync or subscriptions start.",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
    )
    Spacer(modifier = Modifier.height(8.dp))

    settings.forEach { row ->
        StartupSettingRow(
            row = row,
            error = viewModel.startupSettingError(row.id),
            isSensitive = viewModel.isSensitiveRow(row.id),
            onParameterChange = { viewModel.setParameter(row.id, it) },
            onTypeChange = { viewModel.setType(row.id, it) },
            onValueChange = { viewModel.setValue(row.id, it) },
            onAcknowledgedChange = { viewModel.setAcknowledged(row.id, it) },
            onRemove = { viewModel.removeStartupSetting(row.id) },
        )
        Spacer(modifier = Modifier.height(8.dp))
    }

    TextButton(
        onClick = { viewModel.addStartupSetting() },
        enabled = settings.size < AdvancedSettingsValidator.MAX_ROW_COUNT,
        modifier = Modifier.testTag("AddStartupSettingButton"),
    ) {
        Text("+ Add startup setting")
    }

    Text(
        text = "Enter a parameter name for every startup setting. Values are applied exactly " +
            "as typed — Edge Studio does not validate that a parameter exists.",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
        modifier = Modifier.padding(top = 4.dp),
    )

    // Outcome of the most recent open. Without this, a rejected parameter — or scopes
    // that were applied but could not be verified — existed only as a line in the log.
    if (applyFailures.isNotEmpty() || scopesUnverified) {
        Column(modifier = Modifier
            .padding(top = 8.dp)
            .testTag("AdvancedApplyFailures")) {
            if (scopesUnverified) {
                Text(
                    text = "Sync scopes were applied but could not be verified when this " +
                        "database was last opened.",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
            if (applyFailures.isNotEmpty()) {
                Text(
                    text = "Not applied when this database was last opened:",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.tertiary,
                )
                applyFailures.forEach { failure ->
                    Text(
                        text = "• $failure",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
    }

    Spacer(modifier = Modifier.height(8.dp))

    if (viewModel.canUndoResetToDefaults) {
        TextButton(
            onClick = { viewModel.undoResetToDefaults() },
            modifier = Modifier.testTag("UndoResetButton"),
        ) {
            Text("Undo Reset")
        }
    } else {
        TextButton(
            onClick = { viewModel.resetAdvancedToDefaults() },
            modifier = Modifier.testTag("ResetToDefaultsButton"),
        ) {
            Text("Reset to SDK Defaults")
        }
    }

    if (resetRequested) {
        Text(
            text = "System settings will be restored to Ditto's defaults. If this database " +
                "is currently open, that happens when you save; otherwise it takes effect " +
                "the next time you open it.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.secondary,
        )
    }
}

@Composable
private fun CorruptScopesBanner(discard: Boolean, onDiscardChange: (Boolean) -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.4f),
        shape = MaterialTheme.shapes.small,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("CorruptSyncScopesBanner"),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(
                    imageVector = Icons.Outlined.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.tertiary,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "The saved sync scopes for this database could not be read.",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
            Text(
                text = "This database will not open until you re-enter the scopes below, " +
                    "or confirm that losing them is acceptable.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Switch(
                    checked = discard,
                    onCheckedChange = onDiscardChange,
                    modifier = Modifier.testTag("DiscardCorruptScopesToggle"),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Discard the unreadable sync scopes",
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@Composable
private fun SyncScopeRow(
    row: CollectionSyncScope,
    error: AdvancedSettingsValidator.CollectionError?,
    onCollectionChange: (String) -> Unit,
    onScopeChange: (SyncScope) -> Unit,
    onRemove: () -> Unit,
) {
    Column(modifier = Modifier.testTag("SyncScopeRow_${row.id}")) {
        OutlinedTextField(
            value = row.collection,
            onValueChange = onCollectionChange,
            label = { Text("Collection") },
            singleLine = true,
            isError = error != null,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("SyncScopeCollection_${row.id}"),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(top = 4.dp),
        ) {
            SyncScopeDropdown(
                selected = row.scope,
                onSelected = onScopeChange,
                rowTag = "SyncScopeDropdown_${row.id}",
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onRemove) {
                Text("Remove", color = MaterialTheme.colorScheme.error)
            }
        }
        if (error != null) {
            Text(
                text = error.message,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SyncScopeDropdown(
    selected: SyncScope,
    onSelected: (SyncScope) -> Unit,
    rowTag: String,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = selected.displayName,
            onValueChange = {},
            readOnly = true,
            label = { Text("Scope") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .testTag(rowTag)
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SyncScope.entries.forEach { scope ->
                DropdownMenuItem(
                    text = { Text(scope.displayName) },
                    onClick = {
                        onSelected(scope)
                        expanded = false
                    },
                    modifier = Modifier.testTag("SyncScope_${scope.name}"),
                )
            }
        }
    }
}

@Composable
private fun StartupSettingRow(
    row: StartupSetting,
    error: AdvancedSettingsValidator.ParameterError?,
    isSensitive: Boolean,
    onParameterChange: (String) -> Unit,
    onTypeChange: (StartupSettingType) -> Unit,
    onValueChange: (String) -> Unit,
    onAcknowledgedChange: (Boolean) -> Unit,
    onRemove: () -> Unit,
) {
    Column(modifier = Modifier.testTag("StartupSettingRow_${row.id}")) {
        OutlinedTextField(
            value = row.parameter,
            onValueChange = onParameterChange,
            label = { Text("Parameter") },
            singleLine = true,
            isError = error != null,
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("StartupSettingParameter_${row.id}"),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(top = 4.dp),
        ) {
            SettingTypeDropdown(
                selected = row.type,
                onSelected = onTypeChange,
                rowTag = "StartupSettingType_${row.id}",
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onRemove) {
                Text("Remove", color = MaterialTheme.colorScheme.error)
            }
        }
        Spacer(modifier = Modifier.height(4.dp))
        SettingValueControl(
            type = row.type,
            value = row.value,
            onValueChange = onValueChange,
            isError = error != null,
            rowTag = "StartupSettingValue_${row.id}",
        )
        if (error != null) {
            Text(
                text = error.message,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        if (isSensitive) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Switch(
                    checked = row.isAcknowledged,
                    onCheckedChange = onAcknowledgedChange,
                    modifier = Modifier.testTag("StartupSettingAcknowledge_${row.id}"),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "I understand this parameter can expose data on the network " +
                        "or reduce durability.",
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingTypeDropdown(
    selected: StartupSettingType,
    onSelected: (StartupSettingType) -> Unit,
    rowTag: String,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = selected.displayName,
            onValueChange = {},
            readOnly = true,
            label = { Text("Type") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .testTag(rowTag)
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            StartupSettingType.entries.forEach { type ->
                DropdownMenuItem(
                    text = { Text(type.displayName) },
                    onClick = {
                        onSelected(type)
                        expanded = false
                    },
                    modifier = Modifier.testTag("SettingType_${type.name}"),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingValueControl(
    type: StartupSettingType,
    value: String,
    onValueChange: (String) -> Unit,
    isError: Boolean,
    rowTag: String,
) {
    if (type == StartupSettingType.Boolean) {
        var expanded by remember { mutableStateOf(false) }
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = it },
        ) {
            OutlinedTextField(
                value = value,
                onValueChange = {},
                readOnly = true,
                label = { Text("Value") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(rowTag)
                    .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                StartupSetting.booleanValues.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option) },
                        onClick = {
                            onValueChange(option)
                            expanded = false
                        },
                        modifier = Modifier.testTag("SettingValue_$option"),
                    )
                }
            }
        }
    } else {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text("Value") },
            singleLine = true,
            isError = isError,
            textStyle = if (type == StartupSettingType.Json) {
                MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
            } else {
                MaterialTheme.typography.bodyMedium
            },
            modifier = Modifier
                .fillMaxWidth()
                .testTag(rowTag),
        )
    }
}
