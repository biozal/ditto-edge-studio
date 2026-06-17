package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.ProfileTimeFormatter
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes

@Composable
fun ProfileSummaryStrip(
    times: QueryProfileTimes,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            StatChip(
                label = "Elapsed: ${ProfileTimeFormatter.format(times.elapsedNs)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
            StatChip(
                label = "Parse: ${ProfileTimeFormatter.format(times.parseNs)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
            StatChip(
                label = "Plan: ${ProfileTimeFormatter.format(times.planNs)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
        }
        if (times.startISO.isNotBlank()) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Started: ${times.startISO}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
