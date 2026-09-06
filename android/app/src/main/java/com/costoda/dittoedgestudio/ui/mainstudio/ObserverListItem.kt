package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObservable

/** Green used for the "Active" pip and label; matches the SwiftUI sidebar's `.green`. */
private val ActiveGreen = Color(0xFF4CAF50)

/**
 * One row in the Observers list.
 *
 * Actions parity with the SwiftUI sidebar (`SidebarViews.observerTreeRows`), which offers
 * Activate/Stop and Delete through a macOS context menu and iOS swipe actions. Those are
 * discoverable gestures on their platforms; a Compose long-press is not, so the same actions
 * are exposed here as visible controls — an inline Activate/Stop toggle (matching how a
 * trailing swipe puts that one action a single gesture away) plus an overflow menu. The
 * long-press still opens the menu for anyone who reaches for it.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ObserverListItem(
    observer: DittoObservable,
    isSelected: Boolean,
    isActive: Boolean,
    onSelect: () -> Unit,
    onActivate: () -> Unit,
    onDeactivate: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showMenu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    val backgroundColor = if (isSelected) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    } else {
        Color.Transparent
    }

    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = onSelect,
                    onLongClick = { showMenu = true },
                )
                .background(backgroundColor)
                .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = observer.name.ifBlank { observer.query.take(30) },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )

                // Compact controls: the list pane is only 200–320dp wide, so oversized
                // touch targets here cost the observer name its readable width.
                IconButton(
                    onClick = { if (isActive) onDeactivate() else onActivate() },
                    modifier = Modifier.size(32.dp),
                ) {
                    Icon(
                        imageVector = if (isActive) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                        contentDescription = if (isActive) {
                            "Stop observer ${observer.name}"
                        } else {
                            "Activate observer ${observer.name}"
                        },
                        tint = if (isActive) ActiveGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }

                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = "More actions for observer ${observer.name}",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    ObserverActionsMenu(
                        expanded = showMenu,
                        isActive = isActive,
                        onDismiss = { showMenu = false },
                        onActivate = onActivate,
                        onDeactivate = onDeactivate,
                        onEdit = onEdit,
                        onRequestDelete = { confirmDelete = true },
                    )
                }
            }

            // Active badge rides the query line, not the title line — on a 200dp pane it
            // would otherwise compete with the name for the same few characters.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = observer.query,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (isActive) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(ActiveGreen),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Active",
                        style = MaterialTheme.typography.labelSmall,
                        color = ActiveGreen,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
            }
        }
    }

    if (confirmDelete) {
        // SwiftUI deletes straight from the context menu / swipe. Those take a deliberate
        // right-click or drag; an always-visible menu item is far easier to hit by accident,
        // and deleting drops the observer's captured events with it — so confirm here.
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete observer?") },
            text = {
                Text(
                    "\"${observer.name.ifBlank { observer.query }}\" will be removed along with " +
                        "any events it captured. This cannot be undone.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onDelete()
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun ObserverActionsMenu(
    expanded: Boolean,
    isActive: Boolean,
    onDismiss: () -> Unit,
    onActivate: () -> Unit,
    onDeactivate: () -> Unit,
    onEdit: () -> Unit,
    onRequestDelete: () -> Unit,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        if (isActive) {
            DropdownMenuItem(
                text = { Text("Stop") },
                leadingIcon = { Icon(Icons.Filled.Stop, contentDescription = null) },
                onClick = { onDismiss(); onDeactivate() },
            )
        } else {
            DropdownMenuItem(
                text = { Text("Activate") },
                leadingIcon = { Icon(Icons.Filled.PlayArrow, contentDescription = null) },
                onClick = { onDismiss(); onActivate() },
            )
        }
        DropdownMenuItem(
            text = { Text("Edit") },
            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
            onClick = { onDismiss(); onEdit() },
        )
        DropdownMenuItem(
            text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
            leadingIcon = {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                )
            },
            onClick = { onDismiss(); onRequestDelete() },
        )
    }
}
