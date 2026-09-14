package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.data.logging.LogPatternEngine
import com.costoda.dittoedgestudio.domain.model.LogEntry
import java.text.SimpleDateFormat
import java.util.Locale

private val problemTimeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)
private const val MAX_SHOWN_HITS_PER_PATTERN = 10

/**
 * Collapsible strip summarizing pattern matches in the current log view (parity
 * with the VS Code analyzer's Problems list): groups by pattern key sorted by
 * severity, shows hit counts and recommendations, and lets the user jump a hit
 * into the table via the search box. Renders nothing when there are no matches.
 */
@Composable
fun LogProblemsSection(
    problems: List<LogPatternEngine.Match>,
    onJumpToEntry: (LogEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val expandedKeys = remember { mutableStateMapOf<String, Boolean>() }

    AnimatedVisibility(visible = problems.isNotEmpty(), modifier = modifier) {
        Column(modifier = Modifier.fillMaxWidth()) {
            val groups = remember(problems) {
                problems
                    .groupBy { it.pattern.key }
                    .map { (key, matches) -> key to matches }
                    .sortedByDescending { (_, matches) -> matches.first().pattern.severity }
            }
            val worstSeverity = groups.firstOrNull()?.second?.first()?.pattern?.severity ?: 1
            val distinctLines = problems.map { it.entry.id }.distinct().size

            Surface(
                color = severityColor(worstSeverity).copy(alpha = 0.12f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                shape = MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier
                        .clickable { expanded = !expanded }
                        .padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Outlined.Warning,
                        contentDescription = null,
                        tint = severityColor(worstSeverity),
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        text = "${problems.size} problems matched on $distinctLines log lines",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium,
                        color = severityColor(worstSeverity),
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        if (expanded) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown,
                        contentDescription = if (expanded) "Hide problems" else "Show problems",
                        tint = severityColor(worstSeverity),
                        modifier = Modifier.size(16.dp),
                    )
                }
            }

            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    groups.forEach { (key, matches) ->
                        val pattern = matches.first().pattern
                        val groupExpanded = expandedKeys[key] == true

                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { expandedKeys[key] = !groupExpanded }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            SeverityChip(pattern.severity)
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "$key ×${matches.size}",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    text = pattern.recommendation,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 2,
                                )
                            }
                            Icon(
                                if (groupExpanded) {
                                    Icons.Outlined.KeyboardArrowUp
                                } else {
                                    Icons.Outlined.KeyboardArrowDown
                                },
                                contentDescription = if (groupExpanded) "Collapse $key" else "Expand $key",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(16.dp),
                            )
                        }

                        if (groupExpanded) {
                            matches.take(MAX_SHOWN_HITS_PER_PATTERN).forEach { match ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onJumpToEntry(match.entry) }
                                        .padding(start = 16.dp, top = 2.dp, bottom = 2.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Text(
                                        text = problemTimeFormat.format(match.entry.timestamp),
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    Text(
                                        text = match.entry.message,
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.onSurface,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            if (matches.size > MAX_SHOWN_HITS_PER_PATTERN) {
                                Text(
                                    text = "+${matches.size - MAX_SHOWN_HITS_PER_PATTERN} more",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 16.dp),
                                )
                            }
                        }
                    }
                    Spacer(modifier = Modifier.width(4.dp))
                }
            }
            HorizontalDivider()
        }
    }
}
