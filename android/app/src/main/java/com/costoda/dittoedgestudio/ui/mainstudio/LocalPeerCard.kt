package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.TrafficBlack

@Composable
fun LocalPeerCard(
    peer: LocalPeerInfo,
    modifier: Modifier = Modifier,
) {
    val isDark = isSystemInDarkTheme()
    val gradient = if (isDark) {
        Brush.linearGradient(colors = listOf(TrafficBlack, JetBlack))
    } else {
        Brush.linearGradient(
            colors = listOf(Color(0xFFF1F0EA), Color(0xFFD0CFC8)),
        )
    }
    val textColor = if (isDark) Color.White else Color(0xFF1A1A1A)
    val secondaryColor = if (isDark) Color(0xFFAAAAAA) else Color(0xFF555555)

    GradientCard(gradient = gradient, modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.PhoneAndroid,
                    contentDescription = null,
                    tint = textColor,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "This Device",
                    style = MaterialTheme.typography.labelMedium,
                    color = secondaryColor,
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = peer.deviceName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = textColor,
            )

            Spacer(modifier = Modifier.height(8.dp))

            PeerInfoRow(
                label = "SDK",
                value = "${peer.sdkLanguage} / ${peer.sdkPlatform}",
                textColor = textColor,
                secondaryColor = secondaryColor,
            )
            PeerInfoRow(
                label = "Version",
                value = peer.sdkVersion,
                textColor = textColor,
                secondaryColor = secondaryColor,
            )

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider(
                color = if (isSystemInDarkTheme()) Color.White.copy(alpha = 0.25f)
                        else Color.Black.copy(alpha = 0.15f),
                thickness = 1.dp,
            )
            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = peer.peerId,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = secondaryColor,
            )
        }
    }
}

@Composable
internal fun PeerInfoRow(
    label: String,
    value: String,
    textColor: Color,
    secondaryColor: Color,
    valueMonospace: Boolean = false,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = secondaryColor,
            modifier = Modifier.width(72.dp),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            color = textColor,
            fontFamily = if (valueMonospace) FontFamily.Monospace else null,
            modifier = Modifier.weight(1f),
        )
    }
}
