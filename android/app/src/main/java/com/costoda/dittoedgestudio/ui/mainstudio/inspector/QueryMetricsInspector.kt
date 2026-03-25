@file:OptIn(ExperimentalLayoutApi::class)

package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun QueryMetricsInspector(
    metrics: QueryMetrics?,
    modifier: Modifier = Modifier,
) {
    if (metrics == null) {
        Column(
            modifier = modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.Analytics,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.secondary,
            )
            Text(
                text = "No Query Executed",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(top = 12.dp),
            )
            Text(
                text = "Run a query to see its performance metrics here.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
            )
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // DQL Statement block
        if (metrics.queryText.isNotEmpty()) {
            Text(
                text = "DQL Statement",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.1f),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SelectionContainer {
                    Text(
                        text = metrics.queryText,
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                        ),
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
        }

        // Stat badges
        val timeColor = when {
            metrics.executionTimeMs < 10 -> Color(0xFF4CAF50)
            metrics.executionTimeMs < 100 -> Color(0xFFFFC107)
            else -> Color(0xFFF44336)
        }
        val indexUsed = metrics.indexesUsed.isNotEmpty()
        val atFormatted = SimpleDateFormat("MMM d, HH:mm", Locale.getDefault())
            .format(Date(metrics.capturedAt))

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            StatBadge(
                label = "Time",
                value = "${metrics.executionTimeMs} ms",
                valueColor = timeColor,
            )
            StatBadge(
                label = "Results",
                value = "${metrics.docsReturned}",
            )
            StatBadge(
                label = "Index",
                value = if (indexUsed) "✓ Yes" else "✗ No",
                valueColor = if (indexUsed) Color(0xFF4CAF50) else Color(0xFFFF9800),
            )
            StatBadge(
                label = "At",
                value = atFormatted,
            )
        }

        // EXPLAIN Output section
        Text(
            text = "EXPLAIN Output",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
        )
        Surface(
            shape = MaterialTheme.shapes.small,
            color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.1f),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (metrics.explainPlan != null) {
                SelectionContainer {
                    Text(
                        text = metrics.explainPlan,
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                        ),
                        modifier = Modifier.padding(8.dp),
                    )
                }
            } else {
                Text(
                    text = "(no output)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(8.dp),
                )
            }
        }
    }
}

@Composable
private fun StatBadge(
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
) {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.secondaryContainer,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                color = valueColor,
            )
        }
    }
}
