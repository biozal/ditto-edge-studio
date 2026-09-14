@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.Podcasts
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.MulticastConfig
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

/**
 * Transport configuration sheet content (BLE / LAN / WiFi Aware toggles + apply).
 *
 * Hosted by [PresenceSection] inside a `ModalBottomSheet`. Moved out of the deleted
 * legacy `MainStudioScreen.kt` so the scene-driven shell can reuse it without retaining
 * the monolith.
 */
@Composable
internal fun TransportConfigContent(viewModel: MainStudioViewModel) {
    var bluetoothEnabled by remember { mutableStateOf(viewModel.transportBluetoothEnabled) }
    var lanEnabled by remember { mutableStateOf(viewModel.transportLanEnabled) }
    var wifiAwareEnabled by remember { mutableStateOf(viewModel.transportWifiAwareEnabled) }
    var multicastEnabled by remember { mutableStateOf(viewModel.transportMulticastConfig.enabled) }
    var multicastGroup by remember { mutableStateOf(viewModel.transportMulticastConfig.groupAddress) }
    var multicastPortText by remember {
        mutableStateOf(viewModel.transportMulticastConfig.port.toString())
    }
    var multicastInterface by remember {
        mutableStateOf(viewModel.transportMulticastConfig.interfaceName.orEmpty())
    }
    val isApplyingTransport by viewModel.isApplyingTransportFlow.collectAsStateWithLifecycle()
    val connectionsByTransport by viewModel.connectionsByTransport.collectAsStateWithLifecycle()

    // Multicast fields validate continuously; Apply stays disabled while invalid
    // (Zava Retail pattern: port 0 rejected — the SDK reads it as "any port" and
    // group rendezvous silently breaks).
    val multicastGroupValid = MulticastConfig.isValidGroupAddress(multicastGroup)
    val multicastPort = MulticastConfig.parsePort(multicastPortText)
    val multicastValid = !multicastEnabled || (multicastGroupValid && multicastPort != null)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            // The multicast advanced fields made the content taller than the
            // sheet on smaller windows (foldable cover screen, split screen);
            // without this the bottom of the sheet is clipped with no way to
            // reach it.
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Surface(
            color = SulfurYellow.copy(alpha = 0.12f),
            shape = MaterialTheme.shapes.small,
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Warning,
                    contentDescription = null,
                    tint = SulfurYellow,
                )
                Text(
                    text = "Changing transport settings will temporarily stop sync and disconnect all peers.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Peer-to-Peer Transports",
            style = MaterialTheme.typography.titleMedium,
        )

        Spacer(modifier = Modifier.height(8.dp))

        TransportToggleRow(
            icon = Icons.Outlined.Bluetooth,
            name = "Bluetooth LE",
            description = "Direct peer-to-peer sync via Bluetooth Low Energy",
            enabled = bluetoothEnabled,
            onToggle = { bluetoothEnabled = it },
        )
        TransportToggleRow(
            icon = Icons.Outlined.Wifi,
            name = "Local Area Network",
            description = "Sync with peers on the same Wi-Fi or wired network",
            enabled = lanEnabled,
            onToggle = { lanEnabled = it },
        )
        TransportToggleRow(
            icon = Icons.Outlined.WifiFind,
            name = "WiFi Aware",
            description = "WiFi Aware — devices that support WiFi Aware connections",
            enabled = wifiAwareEnabled,
            onToggle = { wifiAwareEnabled = it },
        )
        TransportToggleRow(
            icon = Icons.Outlined.Podcasts,
            name = "Multicast (beta)",
            description = "Reliable UDP multicast with peers on the same Wi-Fi segment",
            enabled = multicastEnabled,
            onToggle = { multicastEnabled = it },
        )

        if (multicastEnabled) {
            Spacer(modifier = Modifier.height(8.dp))

            // Live multicast connection count (from the presence-graph transport
            // counter) — the on-device confirmation that multicast is working.
            Text(
                text = if (connectionsByTransport.multicast > 0) {
                    "● ${connectionsByTransport.multicast} multicast connection(s) active"
                } else {
                    "● Multicast enabled — no multicast connections yet"
                },
                style = MaterialTheme.typography.bodySmall,
                color = if (connectionsByTransport.multicast > 0) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
            )

            OutlinedTextField(
                value = multicastGroup,
                onValueChange = { multicastGroup = it },
                label = { Text("Group Address") },
                supportingText = {
                    if (!multicastGroupValid) {
                        Text("Must be a class-D IPv4 address (224.0.0.0–239.255.255.255)")
                    }
                },
                isError = !multicastGroupValid,
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = multicastPortText,
                onValueChange = { multicastPortText = it },
                label = { Text("Port") },
                supportingText = {
                    if (multicastPort == null) {
                        Text("UDP port 1–65535 (all peers must match)")
                    }
                },
                isError = multicastPort == null,
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = multicastInterface,
                onValueChange = { multicastInterface = it },
                label = { Text("Interface Name (optional)") },
                supportingText = { Text("Blank lets the OS pick the interface") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = {
                viewModel.applyTransportSettings(
                    bluetoothEnabled,
                    lanEnabled,
                    wifiAwareEnabled,
                    MulticastConfig(
                        enabled = multicastEnabled,
                        groupAddress = multicastGroup.trim(),
                        port = multicastPort ?: MulticastConfig.DEFAULT_PORT,
                        interfaceName = multicastInterface.trim().ifBlank { null },
                    ),
                )
            },
            enabled = !isApplyingTransport && multicastValid,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isApplyingTransport) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp,
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(if (isApplyingTransport) "Applying…" else "Apply Transport Settings")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun TransportToggleRow(
    icon: ImageVector,
    name: String,
    description: String,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = enabled,
            onCheckedChange = onToggle,
        )
    }
}
