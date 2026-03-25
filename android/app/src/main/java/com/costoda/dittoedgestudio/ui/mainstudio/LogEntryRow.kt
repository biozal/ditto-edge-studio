package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.shortName
import com.ditto.kotlin.DittoLogLevel
import java.text.SimpleDateFormat
import java.util.Locale

private val timeFormat = SimpleDateFormat("h:mm:ss.SSS a", Locale.US)

@Composable
internal fun levelColor(level: DittoLogLevel): Color = when (level) {
    DittoLogLevel.Error -> Color(0xFFFF3B30)
    DittoLogLevel.Warning -> Color(0xFFFF9500)
    DittoLogLevel.Info -> MaterialTheme.colorScheme.primary
    DittoLogLevel.Debug -> MaterialTheme.colorScheme.secondary
    DittoLogLevel.Verbose -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LogEntryRow(
    entry: LogEntry,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    var showContextMenu by remember { mutableStateOf(false) }
    @Suppress("DEPRECATION") val clipboard = LocalClipboardManager.current
    val color = levelColor(entry.level)

    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = { expanded = !expanded },
                    onLongClick = { showContextMenu = true },
                )
                .padding(horizontal = 8.dp, vertical = 4.dp)
                .animateContentSize(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.Top,
        ) {
            // Timestamp
            Text(
                text = timeFormat.format(entry.timestamp),
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.defaultMinSize(minWidth = 90.dp),
                maxLines = 1,
            )

            // Level badge
            Surface(
                color = color.copy(alpha = 0.18f),
                shape = RoundedCornerShape(4.dp),
                modifier = Modifier.defaultMinSize(minWidth = 40.dp),
            ) {
                Text(
                    text = entry.level.shortName,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    color = color,
                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                    maxLines = 1,
                )
            }

            // Component pill — SDK source only, hidden for ALL/OTHER
            if (entry.source is LogEntrySource.DittoSDK &&
                entry.component != LogComponent.ALL &&
                entry.component != LogComponent.OTHER
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.12f),
                    shape = RoundedCornerShape(4.dp),
                ) {
                    Text(
                        text = entry.component.displayName,
                        fontSize = 10.sp,
                        color = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                        maxLines = 1,
                    )
                }
            }

            // Message
            Text(
                text = entry.message,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = if (expanded) Int.MAX_VALUE else 2,
                modifier = Modifier.weight(1f),
            )
        }

        DropdownMenu(
            expanded = showContextMenu,
            onDismissRequest = { showContextMenu = false },
        ) {
            DropdownMenuItem(
                text = { Text("Copy Message") },
                onClick = {
                    clipboard.setText(AnnotatedString(entry.message))
                    showContextMenu = false
                },
            )
            DropdownMenuItem(
                text = { Text("Copy Line") },
                onClick = {
                    clipboard.setText(AnnotatedString(entry.rawLine))
                    showContextMenu = false
                },
            )
        }
    }
}
