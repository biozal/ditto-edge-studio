package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.ProfileTimeFormatter
import com.costoda.dittoedgestudio.domain.model.QueryProfileStats

@Composable
fun ProfileStatsBadges(
    stats: QueryProfileStats,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        stats.documentsIn?.let { n ->
            StatChip(label = "in: $n", containerColor = MaterialTheme.colorScheme.tertiaryContainer)
        }
        stats.documentsOut?.let { n ->
            StatChip(label = "out: $n", containerColor = MaterialTheme.colorScheme.tertiaryContainer)
        }
        stats.execNs?.let { ns ->
            StatChip(
                label = "exec: ${ProfileTimeFormatter.format(ns)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
        }
        stats.recvNs?.let { ns ->
            StatChip(
                label = "recv: ${ProfileTimeFormatter.format(ns)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
        }
        stats.sendNs?.let { ns ->
            StatChip(
                label = "send: ${ProfileTimeFormatter.format(ns)}",
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
        }
    }
}

@Composable
internal fun StatChip(
    label: String,
    containerColor: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}
