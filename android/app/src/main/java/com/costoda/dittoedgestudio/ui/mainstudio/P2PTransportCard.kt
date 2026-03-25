package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CellTower
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.WifiFind
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
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo

@Composable
fun P2PTransportCard(
    transport: P2PTransportInfo,
    modifier: Modifier = Modifier,
) {
    val (gradient, title, icon) = when (transport.kind) {
        P2PTransportInfo.Kind.WifiAware -> Triple(
            Brush.linearGradient(colors = listOf(Color(0xFF4F46E5), Color(0xFF312E81))),
            "WiFi Aware (NAN)",
            Icons.Outlined.CellTower,
        )
        P2PTransportInfo.Kind.WifiDirect -> Triple(
            Brush.linearGradient(colors = listOf(Color(0xFF475569), Color(0xFF1E293B))),
            "WiFi Direct",
            Icons.Outlined.WifiFind,
        )
    }
    val textColor = Color.White
    val secondaryColor = Color.White.copy(alpha = 0.75f)

    GradientCard(gradient = gradient, modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = textColor,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = textColor,
                )
                Icon(
                    imageVector = Icons.Outlined.Circle,
                    contentDescription = if (transport.isEnabled) "Available" else "Unavailable",
                    tint = if (transport.isEnabled) Color(0xFF34C759) else Color(0xFFFF3B30),
                    modifier = Modifier.size(10.dp),
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            transport.statusDetail?.let { detail ->
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = secondaryColor,
                )
            }
        }
    }
}
