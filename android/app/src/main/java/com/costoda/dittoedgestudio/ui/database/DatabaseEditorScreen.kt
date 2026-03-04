package com.costoda.dittoedgestudio.ui.database

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import kotlinx.coroutines.launch
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

private val logLevelOptions = listOf(
    "error" to "Error",
    "warning" to "Warning",
    "info" to "Info (Default)",
    "debug" to "Debug",
    "verbose" to "Verbose",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DatabaseEditorScreen(
    databaseId: Long,
    onDismiss: () -> Unit,
    instanceKey: String? = null,
    viewModel: DatabaseEditorViewModel = koinViewModel(
        key = instanceKey,
        parameters = { parametersOf(databaseId) },
    ),
) {
    val name by viewModel.name.collectAsState()
    val dbId by viewModel.databaseId.collectAsState()
    val token by viewModel.token.collectAsState()
    val authUrl by viewModel.authUrl.collectAsState()
    val httpApiUrl by viewModel.httpApiUrl.collectAsState()
    val httpApiKey by viewModel.httpApiKey.collectAsState()
    val mode by viewModel.mode.collectAsState()
    val allowUntrustedCerts by viewModel.allowUntrustedCerts.collectAsState()
    val secretKey by viewModel.secretKey.collectAsState()
    val logLevel by viewModel.logLevel.collectAsState()
    val canSave by viewModel.canSave.collectAsState()

    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.Close, contentDescription = "Dismiss")
                    }
                },
                title = {
                    Text(
                        text = if (viewModel.isNewItem) "Register Database" else "Edit Database",
                    )
                },
                actions = {
                    TextButton(
                        enabled = canSave,
                        onClick = {
                            scope.launch {
                                viewModel.save()
                                onDismiss()
                            }
                        },
                        modifier = Modifier.testTag("SaveButton"),
                    ) {
                        Text("Save")
                    }
                },
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState()),
        ) {
            // --- Mode selector ---
            SecondaryTabRow(selectedTabIndex = mode.ordinal) {
                AuthMode.entries.forEachIndexed { index, authMode ->
                    Tab(
                        selected = mode.ordinal == index,
                        onClick = { viewModel.switchMode(authMode) },
                        text = { Text(authMode.displayName) },
                        modifier = Modifier.testTag("Tab_${authMode.name}"),
                    )
                }
            }

            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                // --- Basic Information ---
                FormSectionHeader("Basic Information")
                OutlinedTextField(
                    value = name,
                    onValueChange = { viewModel.name.value = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("NameField"),
                )

                // --- Authorization Information ---
                FormSectionHeader("Authorization Information")
                OutlinedTextField(
                    value = dbId,
                    onValueChange = { viewModel.databaseId.value = it },
                    label = { Text("Database ID") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("DatabaseIdField"),
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = token,
                    onValueChange = { viewModel.token.value = it },
                    label = {
                        Text(if (mode == AuthMode.SERVER) "Token" else "Offline Token")
                    },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("TokenField"),
                )
                if (mode == AuthMode.SMALL_PEERS_ONLY) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Required for sync activation. Obtain from https://portal.ditto.live",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }

                // --- Server-only sections ---
                if (mode == AuthMode.SERVER) {
                    FormSectionHeader("Ditto Server (BigPeer) Information")
                    OutlinedTextField(
                        value = authUrl,
                        onValueChange = { viewModel.authUrl.value = it },
                        label = { Text("Auth URL") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("AuthUrlField"),
                    )

                    FormSectionHeader("Ditto Server — HTTP API (Optional)")
                    OutlinedTextField(
                        value = httpApiUrl,
                        onValueChange = { viewModel.httpApiUrl.value = it },
                        label = { Text("HTTP API URL") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("HttpApiUrlField"),
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = httpApiKey,
                        onValueChange = { viewModel.httpApiKey.value = it },
                        label = { Text("HTTP API Key") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("HttpApiKeyField"),
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Switch(
                            checked = allowUntrustedCerts,
                            onCheckedChange = { viewModel.allowUntrustedCerts.value = it },
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Allow untrusted certificates",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    Text(
                        text = "By allowing untrusted certificates, you accept the security risks of connecting to a server with a self-signed or expired certificate.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }

                // --- Small Peers Only section ---
                if (mode == AuthMode.SMALL_PEERS_ONLY) {
                    FormSectionHeader("Optional Secret Key")
                    OutlinedTextField(
                        value = secretKey,
                        onValueChange = { viewModel.secretKey.value = it },
                        label = { Text("Shared Key") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("SharedKeyField"),
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Optional secret key for shared key identity. Leave blank to use certificate-based authentication.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }

                // --- Developer Options ---
                FormSectionHeader("Developer Options")
                LogLevelDropdown(
                    selectedLogLevel = logLevel,
                    onLogLevelSelected = { viewModel.logLevel.value = it },
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Controls DittoLogger.minimumLogLevel. Higher verbosity may impact performance.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                )

                // --- Info banner (new items only) ---
                if (viewModel.isNewItem) {
                    Spacer(modifier = Modifier.height(16.dp))
                    InfoBanner(
                        message = "This information comes from the Ditto Portal and is required to register a Ditto Database.",
                        linkText = "Ditto Portal",
                    )
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

@Composable
private fun FormSectionHeader(title: String) {
    Spacer(modifier = Modifier.height(20.dp))
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
    )
    HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LogLevelDropdown(
    selectedLogLevel: String,
    onLogLevelSelected: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedDisplay = logLevelOptions.firstOrNull { it.first == selectedLogLevel }?.second ?: selectedLogLevel

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier.testTag("LogLevelDropdown"),
    ) {
        OutlinedTextField(
            value = selectedDisplay,
            onValueChange = {},
            readOnly = true,
            label = { Text("SDK Log Level") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            logLevelOptions.forEach { (value, display) ->
                DropdownMenuItem(
                    text = { Text(display) },
                    onClick = {
                        onLogLevelSelected(value)
                        expanded = false
                    },
                    modifier = Modifier.testTag("LogLevel_$value"),
                )
            }
        }
    }
}

@Composable
private fun InfoBanner(message: String, linkText: String) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f),
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                imageVector = Icons.Outlined.Info,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 2.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun DatabaseEditorScreenPreview() {
    EdgeStudioTheme {
        // Preview uses a static layout since ViewModels can't be previewed directly
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
        ) {
            Text(
                "Register Database",
                style = MaterialTheme.typography.headlineSmall,
            )
        }
    }
}
