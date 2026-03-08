package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Android
import androidx.compose.material.icons.outlined.BluetoothConnected
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.DevicesOther
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.LaptopMac
import androidx.compose.material.icons.outlined.LaptopWindows
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Wifi
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.PeerOS
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo

@Composable
fun RemotePeerCard(
    peer: SyncStatusInfo,
    modifier: Modifier = Modifier,
) {
    val gradient = gradientForPeer(peer)
    val textColor = Color.White
    val secondaryColor = Color.White.copy(alpha = 0.75f)
    val dividerColor = Color.White.copy(alpha = 0.25f)
    var metadataExpanded by remember { mutableStateOf(false) }

    GradientCard(gradient = gradient, modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {

            // ── Header: OS icon + device name + "● Connected" ──────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = osIconForPeerOS(peer.osInfo),
                    contentDescription = peer.osInfo.displayName,
                    tint = textColor,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = peer.deviceName ?: "Unknown Device",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = textColor,
                    modifier = Modifier.weight(1f),
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Circle,
                        contentDescription = "Connected",
                        tint = Color(0xFF34C759),
                        modifier = Modifier.size(8.dp),
                    )
                    Text(
                        text = "Connected",
                        style = MaterialTheme.typography.labelSmall,
                        color = textColor,
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // OS subtitle (or "Cloud Server" for Ditto server peers)
            Text(
                text = if (peer.isDittoServer) "Cloud Server" else peer.osInfo.displayName,
                style = MaterialTheme.typography.bodySmall,
                color = secondaryColor,
                modifier = Modifier.padding(start = 28.dp),
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Full peer key in monospace
            Text(
                text = peer.peerId,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = secondaryColor,
            )

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(color = dividerColor, thickness = 1.dp)
            Spacer(modifier = Modifier.height(12.dp))

            // ── Body: SDK version + peer metadata ───────────────────────────
            peer.dittoSdkVersion?.let { version ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Code,
                        contentDescription = null,
                        tint = secondaryColor,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = "Ditto SDK: $version",
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor,
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
            }

            if (peer.peerMetadata != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { metadataExpanded = !metadataExpanded },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Info,
                        contentDescription = null,
                        tint = secondaryColor,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = "Peer Metadata",
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        imageVector = if (metadataExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = if (metadataExpanded) "Collapse" else "Expand",
                        tint = secondaryColor,
                        modifier = Modifier.size(16.dp),
                    )
                }
                AnimatedVisibility(visible = metadataExpanded) {
                    Text(
                        text = peer.peerMetadata,
                        style = MaterialTheme.typography.labelSmall,
                        fontFamily = FontFamily.Monospace,
                        color = secondaryColor,
                        modifier = Modifier
                            .padding(top = 6.dp)
                            .heightIn(max = 120.dp)
                            .verticalScroll(rememberScrollState()),
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
            }

            // ── Active Connections ──────────────────────────────────────────
            if (peer.connections.isNotEmpty()) {
                Text(
                    text = "Active Connections (${peer.connections.size})",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.75f),
                )
                Spacer(modifier = Modifier.height(6.dp))
                peer.connections.forEach { conn ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(vertical = 2.dp),
                    ) {
                        Icon(
                            imageVector = iconForConnectionType(conn.type),
                            contentDescription = null,
                            tint = textColor,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text = conn.type.displayName,
                            style = MaterialTheme.typography.bodySmall,
                            color = textColor,
                        )
                    }
                }
            }

            // ── Sync status ─────────────────────────────────────────────────
            peer.syncedUpToLocalCommitId?.let { commitId ->
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = secondaryColor,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = "Synced to commit: $commitId",
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor,
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = secondaryColor,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = "Last update: ${peer.formattedLastUpdate}",
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor,
                )
            }
        }
    }
}

private fun gradientForPeer(peer: SyncStatusInfo): Brush =
    if (peer.isDittoServer) {
        Brush.linearGradient(colors = listOf(Color(0xFF7326B8), Color(0xFF47127A)))
    } else {
        gradientForConnectionType(peer.connections.map { it.type }.dominantConnectionType())
    }

private fun List<ConnectionType>.dominantConnectionType(): ConnectionType {
    return when {
        contains(ConnectionType.WebSocket) -> ConnectionType.WebSocket
        contains(ConnectionType.LAN) -> ConnectionType.LAN
        contains(ConnectionType.P2PWiFi) -> ConnectionType.P2PWiFi
        contains(ConnectionType.Bluetooth) -> ConnectionType.Bluetooth
        else -> ConnectionType.Unknown
    }
}

private fun gradientForConnectionType(type: ConnectionType): Brush = when (type) {
    ConnectionType.Bluetooth -> Brush.linearGradient(
        colors = listOf(Color(0xFF0066D9), Color(0xFF003399)),
    )
    ConnectionType.LAN -> Brush.linearGradient(
        colors = listOf(Color(0xFF0D8540), Color(0xFF055224)),
    )
    ConnectionType.P2PWiFi -> Brush.linearGradient(
        colors = listOf(Color(0xFFC71A38), Color(0xFF800A1F)),
    )
    ConnectionType.WebSocket -> Brush.linearGradient(
        colors = listOf(Color(0xFFD97A00), Color(0xFF994D00)),
    )
    ConnectionType.Unknown -> Brush.linearGradient(
        colors = listOf(Color(0xFF595966), Color(0xFF333340)),
    )
}

private fun iconForConnectionType(type: ConnectionType): ImageVector = when (type) {
    ConnectionType.Bluetooth -> Icons.Outlined.BluetoothConnected
    ConnectionType.LAN -> Icons.Outlined.Lan
    ConnectionType.P2PWiFi -> Icons.Outlined.Wifi
    ConnectionType.WebSocket -> Icons.Outlined.Cloud
    ConnectionType.Unknown -> Icons.Outlined.Circle
}

private fun osIconForPeerOS(os: PeerOS): ImageVector = when (os) {
    PeerOS.iOS -> Icons.Outlined.PhoneIphone
    PeerOS.Android -> Icons.Outlined.Android
    PeerOS.MacOS -> Icons.Outlined.LaptopMac
    PeerOS.Linux -> Icons.Outlined.Computer
    PeerOS.Windows -> Icons.Outlined.LaptopWindows
    PeerOS.Unknown -> Icons.Outlined.DevicesOther
}
