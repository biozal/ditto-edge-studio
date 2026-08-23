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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
    val isApplyingTransport by viewModel.isApplyingTransportFlow.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxWidth()
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

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = { viewModel.applyTransportSettings(bluetoothEnabled, lanEnabled, wifiAwareEnabled) },
            enabled = !isApplyingTransport,
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
