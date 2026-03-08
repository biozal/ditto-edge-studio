package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo

@Composable
fun NetworkInterfaceCard(
    iface: NetworkInterfaceInfo,
    modifier: Modifier = Modifier,
) {
    val (gradient, textColor, secondaryColor) = when (iface.kind) {
        NetworkInterfaceInfo.InterfaceKind.Wifi -> Triple(
            Brush.linearGradient(colors = listOf(Color(0xFF0D8540), Color(0xFF053324))),
            Color.White,
            Color.White.copy(alpha = 0.75f),
        )
        NetworkInterfaceInfo.InterfaceKind.Ethernet -> Triple(
            Brush.linearGradient(colors = listOf(Color(0xFF0D7380), Color(0xFF034751))),
            Color.White,
            Color.White.copy(alpha = 0.75f),
        )
        NetworkInterfaceInfo.InterfaceKind.Other -> Triple(
            Brush.linearGradient(colors = listOf(Color(0xFF475569), Color(0xFF1E293B))),
            Color.White,
            Color.White.copy(alpha = 0.75f),
        )
    }

    GradientCard(gradient = gradient, modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = when (iface.kind) {
                        NetworkInterfaceInfo.InterfaceKind.Wifi -> if (iface.isActive) Icons.Outlined.Wifi else Icons.Outlined.WifiOff
                        else -> Icons.Outlined.Lan
                    },
                    contentDescription = null,
                    tint = textColor,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = iface.interfaceName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = textColor,
                )
                Icon(
                    imageVector = Icons.Outlined.Circle,
                    contentDescription = if (iface.isActive) "Active" else "Inactive",
                    tint = if (iface.isActive) Color(0xFF34C759) else Color(0xFFFF3B30),
                    modifier = Modifier.size(10.dp),
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // WiFi-specific fields
            if (iface.kind == NetworkInterfaceInfo.InterfaceKind.Wifi) {
                if (iface.locationPermissionGranted) {
                    iface.ssid?.let { PeerInfoRow("SSID", it, textColor, secondaryColor) }
                    iface.bssid?.let { PeerInfoRow("BSSID", it, textColor, secondaryColor, valueMonospace = true) }
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(vertical = 2.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Warning,
                            contentDescription = null,
                            tint = Color(0xFFF0D830),
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text = "Location permission needed for SSID/BSSID",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFFF0D830),
                        )
                    }
                }

                iface.rssi?.let { rssi ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(vertical = 2.dp),
                    ) {
                        Text(
                            text = "Signal",
                            style = MaterialTheme.typography.bodySmall,
                            color = secondaryColor,
                        )
                        Text(
                            text = "$rssi dBm",
                            style = MaterialTheme.typography.bodySmall,
                            color = textColor,
                        )
                        iface.signalLevel?.let { level ->
                            SignalBar(level = level, maxLevel = 4, tint = textColor)
                        }
                    }
                }

                iface.linkSpeedMbps?.let {
                    PeerInfoRow("Link Speed", "$it Mbps", textColor, secondaryColor)
                }
                iface.txLinkSpeedMbps?.let {
                    PeerInfoRow("TX Speed", "$it Mbps", textColor, secondaryColor)
                }
                iface.rxLinkSpeedMbps?.let {
                    PeerInfoRow("RX Speed", "$it Mbps", textColor, secondaryColor)
                }
                iface.frequencyBandLabel?.let {
                    val freqText = iface.frequencyMhz?.let { mhz -> "$it ($mhz MHz)" } ?: it
                    PeerInfoRow("Band", freqText, textColor, secondaryColor)
                }
                iface.wifiStandardLabel?.let {
                    PeerInfoRow("Standard", it, textColor, secondaryColor)
                }
            }

            // Ethernet-specific
            if (iface.kind == NetworkInterfaceInfo.InterfaceKind.Ethernet) {
                iface.ethernetBandwidthKbps?.let {
                    val mbps = it / 1000
                    PeerInfoRow("Bandwidth", "$mbps Mbps", textColor, secondaryColor)
                }
            }

            // Common fields
            iface.hardwareAddress?.let {
                PeerInfoRow("MAC", it, textColor, secondaryColor, valueMonospace = true)
            }
            iface.mtu?.let { PeerInfoRow("MTU", it.toString(), textColor, secondaryColor) }
            iface.ipv4Address?.let { PeerInfoRow("IPv4", it, textColor, secondaryColor, valueMonospace = true) }
            iface.ipv6Address?.let { PeerInfoRow("IPv6", it, textColor, secondaryColor, valueMonospace = true) }
            iface.gatewayAddress?.let { PeerInfoRow("Gateway", it, textColor, secondaryColor, valueMonospace = true) }
        }
    }
}

@Composable
private fun SignalBar(level: Int, maxLevel: Int, tint: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (i in 0..maxLevel) {
            Icon(
                imageVector = Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (i <= level) tint else tint.copy(alpha = 0.3f),
                modifier = Modifier.size(6.dp),
            )
        }
    }
}
