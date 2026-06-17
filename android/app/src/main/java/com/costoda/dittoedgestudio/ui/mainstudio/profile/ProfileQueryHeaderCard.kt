package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfile

@Composable
fun ProfileQueryHeaderCard(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    val displayText = profile.text
        .let { raw ->
            if (raw.trimStart().uppercase().startsWith("PROFILE ")) {
                raw.trimStart().drop("PROFILE ".length)
            } else {
                raw
            }
        }
        .trim()

    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Outlined.Code,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Captured Query",
                    style = MaterialTheme.typography.titleSmall,
                )
            }
            Spacer(modifier = Modifier.padding(top = 8.dp))
            Text(
                text = displayText,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
