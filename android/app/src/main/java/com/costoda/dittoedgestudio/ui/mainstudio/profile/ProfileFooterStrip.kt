package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfile

@Composable
fun ProfileFooterStrip(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Feature flags: ${profile.featureFlags}",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        StatePill(state = profile.state)
        Text(
            text = "Results: ${profile.resultCount}",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StatePill(
    state: String,
    modifier: Modifier = Modifier,
) {
    val isCompleted = state.equals("completed", ignoreCase = true)
    val containerColor = if (isCompleted) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.errorContainer
    }

    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            text = state,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}
