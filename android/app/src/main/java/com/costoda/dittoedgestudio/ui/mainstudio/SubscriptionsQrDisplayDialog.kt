package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.util.QrCodeEncoder
import com.costoda.dittoedgestudio.util.SubscriptionsQrCodec

/**
 * Dialog showing all subscriptions encoded as a single `EDS_SUBS1:` QR code
 * (parity with the SwiftUI `SubscriptionQRDisplayView`). Another Edge Studio
 * instance — macOS, iPadOS, or Android — can scan it to import them all at once.
 */
@Composable
fun SubscriptionsQrDisplayDialog(
    subscriptions: List<DittoSubscription>,
    onDismiss: () -> Unit,
) {
    val payload = SubscriptionsQrCodec.encode(subscriptions)
    val bitmap = payload?.let { QrCodeEncoder.renderQrBitmap(it) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Share Subscriptions") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = "QR code carrying ${subscriptions.size} subscriptions",
                        modifier = Modifier.size(280.dp),
                    )
                    Text(
                        text = "${subscriptions.size} subscription(s). Scan from another Edge Studio instance.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    Text(
                        text = "Could not generate the QR code.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done") }
        },
    )
}
