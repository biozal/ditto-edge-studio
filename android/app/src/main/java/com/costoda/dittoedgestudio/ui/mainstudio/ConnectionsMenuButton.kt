package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SettingsInputAntenna
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.ui.mainstudio.presence.connectionColor

/**
 * Connections counter for the floating bottom bar, matching the SwiftUI
 * `DetailBottomBar` connections menu: an antenna icon with a monospaced total
 * (no chip chrome), opening a popup with a "Connections" header and one
 * colored-dot row per active transport — or a "No Active Connections" state.
 *
 * Dot colors reuse the presence graph's Ditto Rainbow palette
 * (`presence/ConnectionStyles.kt`).
 */
@Composable
fun ConnectionsMenuButton(
    connections: ConnectionsByTransport,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .clickable { expanded = true }
                .padding(horizontal = 8.dp, vertical = 8.dp)
                .testTag("ConnectionsMenuButton"),
        ) {
            Icon(
                imageVector = Icons.Outlined.SettingsInputAntenna,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "${connections.total}",
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.testTag("ConnectionsMenu"),
        ) {
            Text(
                text = "Connections",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            val rows = buildList {
                // SwiftUI ordering: WebSocket, Bluetooth, P2P WiFi, LAN, Ditto Server.
                if (connections.webSocket > 0) {
                    add(Triple("WebSocket", connections.webSocket, connectionColor(ConnectionType.WebSocket, isCloud = false)))
                }
                if (connections.bluetooth > 0) {
                    add(Triple("Bluetooth", connections.bluetooth, connectionColor(ConnectionType.Bluetooth, isCloud = false)))
                }
                if (connections.p2pWifi > 0) {
                    add(Triple("P2P WiFi", connections.p2pWifi, connectionColor(ConnectionType.P2PWiFi, isCloud = false)))
                }
                if (connections.lan > 0) {
                    add(Triple("LAN", connections.lan, connectionColor(ConnectionType.LAN, isCloud = false)))
                }
                if (connections.dittoServer > 0) {
                    add(Triple("Ditto Server", connections.dittoServer, connectionColor(ConnectionType.WebSocket, isCloud = true)))
                }
            }

            if (rows.isEmpty()) {
                DropdownMenuItem(
                    text = {
                        Text(
                            text = "No Active Connections",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    onClick = { expanded = false },
                    enabled = false,
                )
            } else {
                rows.forEach { (name, count, color) ->
                    DropdownMenuItem(
                        text = { Text("$name: $count") },
                        leadingIcon = {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(color, CircleShape),
                            )
                        },
                        onClick = { expanded = false },
                        modifier = Modifier.testTag("ConnectionsMenu_$name"),
                    )
                }
            }
        }
    }
}
