package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.costoda.dittoedgestudio.data.logging.LogEntryContext
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.shortName
import com.ditto.kotlin.DittoLogLevel
import java.text.SimpleDateFormat
import java.util.Locale

private val timeFormat = SimpleDateFormat("h:mm:ss.SSS a", Locale.US)

/** User-tag chip color — matches the VS Code analyzer's purple (#b08fff). */
private val UserTagColor = Color(0xFFB08FFF)

/**
 * The clipboard payload for `Copy With Context`: the raw source lines of
 * [context]`.before`, [entry], and [context]`.after`, in that order, joined by
 * newlines.
 *
 * Mirrors `LogEntryRowView.swift`'s `context.before + [entry] + context.after`
 * mapped over `\.rawLine`. Raw lines rather than parsed messages, because the
 * JSON-Lines file encoding keeps the interesting fields (`remote`, `role`,
 * `transport_type`, `connection_id`) beside the message rather than inside it —
 * pasting parsed messages would drop exactly what the reader needs.
 *
 * An empty [context] degrades to the focused line alone rather than to an empty
 * clipboard.
 */
internal fun copyWithContextText(entry: LogEntry, context: LogEntryContext): String =
    (context.before + entry + context.after).joinToString("\n") { it.rawLine }

@Composable
internal fun levelColor(level: DittoLogLevel): Color = when (level) {
    DittoLogLevel.Error -> Color(0xFFFF3B30)
    DittoLogLevel.Warning -> Color(0xFFFF9500)
    DittoLogLevel.Info -> MaterialTheme.colorScheme.primary
    DittoLogLevel.Debug -> MaterialTheme.colorScheme.secondary
    DittoLogLevel.Verbose -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f)
}

/**
 * One log line, optionally expanded to show its surrounding context.
 *
 * ## Why expansion state is a parameter rather than local `remember`
 *
 * The context slice has to come from the **unfiltered** source buffer — the
 * whole point of context is to show what the SDK was doing around a line, which
 * is almost always something the current filter hides. A row cannot reach that
 * buffer, so the owner ([LoggingScreen]) resolves the slice and hands it down.
 * Keeping the flag here as well would also lose the expansion on every re-parse,
 * which mints new entry ids. One row is open at a time, by construction: the
 * owner stores a single expanded id.
 *
 * @param expanded         Whether this row is the one currently expanded.
 * @param onToggleExpanded Invoked when the row is tapped.
 * @param context          The ±5 unfiltered neighbours, or null when collapsed.
 * @param resolveContext   Resolves the ±5 unfiltered neighbours of any entry, on
 *                         demand, for `Copy With Context`. Supplied by the owner
 *                         because only it can reach the unfiltered buffer;
 *                         invoked on click so a collapsed row costs nothing.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LogEntryRow(
    entry: LogEntry,
    modifier: Modifier = Modifier,
    userTags: List<String> = emptyList(),
    expanded: Boolean = false,
    onToggleExpanded: () -> Unit = {},
    context: LogEntryContext? = null,
    resolveContext: ((LogEntry) -> LogEntryContext)? = null,
) {
    var showContextMenu by remember { mutableStateOf(false) }
    @Suppress("DEPRECATION") val clipboard = LocalClipboardManager.current
    val color = levelColor(entry.level)

    Column(modifier = modifier) {
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = onToggleExpanded,
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

            // User-tag chips — labels applied by matching log patterns.
            userTags.forEach { tag ->
                Surface(
                    color = UserTagColor.copy(alpha = 0.18f),
                    shape = RoundedCornerShape(4.dp),
                ) {
                    Text(
                        text = tag,
                        fontSize = 10.sp,
                        color = UserTagColor,
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
            // Parity with SwiftUI's `Copy With Context`: the before + focused +
            // after raw lines, newline-joined — the shape you paste into an
            // issue.
            //
            // The slice is resolved lazily, on click, rather than passed in for
            // every row: it must come from the unfiltered buffer, which only the
            // owner can reach, and resolving it eagerly per row would be a
            // linear scan of that buffer per visible row. Falling back to the
            // already-resolved [context] keeps the expanded row working even if
            // no resolver was supplied.
            if (resolveContext != null || context?.isEmpty == false) {
                DropdownMenuItem(
                    text = { Text("Copy With Context") },
                    onClick = {
                        val slice = context?.takeIf { !it.isEmpty }
                            ?: resolveContext?.invoke(entry)
                            ?: LogEntryContext.EMPTY
                        clipboard.setText(AnnotatedString(copyWithContextText(entry, slice)))
                        showContextMenu = false
                    },
                )
            }
        }
    }

        AnimatedVisibility(visible = expanded) {
            LogEntryContextDrawer(entry = entry, context = context)
        }
    }
}

/**
 * The detail panel under an expanded row: the raw source line when it carries
 * more than the parsed message, then the ±5 surrounding entries from the
 * unfiltered buffer with the focused line marked.
 */
@Composable
private fun LogEntryContextDrawer(
    entry: LogEntry,
    context: LogEntryContext?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 8.dp, top = 2.dp, bottom = 6.dp)
            .testTag("LogEntryContextDrawer"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // The JSON-Lines file encoding puts the interesting fields (remote,
        // role, transport_type, connection_id) alongside the message rather
        // than inside it, so the raw line is often the only place they appear.
        val raw = entry.rawLine.trim()
        if (raw.isNotEmpty() && raw != entry.message.trim()) {
            DrawerLabel("Raw line")
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                shape = RoundedCornerShape(4.dp),
            ) {
                Text(
                    text = raw,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(6.dp),
                )
            }
        }

        when {
            context == null -> Unit
            context.isEmpty -> DrawerLabel("No surrounding lines available.")
            else -> {
                DrawerLabel("Context (±${LogEntryContext.DEFAULT_RADIUS} lines, unfiltered)")
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
                    shape = RoundedCornerShape(4.dp),
                ) {
                    Column(modifier = Modifier.padding(vertical = 4.dp)) {
                        context.before.forEach { ContextLine(it, focused = false) }
                        ContextLine(entry, focused = true)
                        context.after.forEach { ContextLine(it, focused = false) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DrawerLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun ContextLine(entry: LogEntry, focused: Boolean) {
    val tint = levelColor(entry.level)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (focused) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                } else {
                    Color.Transparent
                },
            )
            .padding(horizontal = 6.dp, vertical = 1.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = if (focused) "▶" else " ",
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = timeFormat.format(entry.timestamp),
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
        Text(
            text = entry.level.shortName,
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            color = tint,
            modifier = Modifier.defaultMinSize(minWidth = 34.dp),
            maxLines = 1,
        )
        Text(
            text = entry.message,
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (focused) 1f else 0.75f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}
