package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

private val pageSizeOptions = listOf(10, 25, 50, 100)

@Composable
fun ObserverDetailScreen(
    selectedObserver: DittoObservable?,
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    filterMode: EventFilterMode,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    onFilterChange: (EventFilterMode) -> Unit,
    modifier: Modifier = Modifier,
    pageSize: Int = 25,
    currentPage: Int = 0,
    onPageSizeChange: (Int) -> Unit = {},
    onPageChange: (Int) -> Unit = {},
) {
    if (selectedObserver == null) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Outlined.Visibility,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
                Text(
                    text = "Select an observer and activate it to see events",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        return
    }

    if (events.isEmpty()) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = selectedObserver.name.ifBlank { "Observer" },
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "No events captured yet. Activate the observer to start.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        return
    }

    Column(modifier = modifier.fillMaxSize()) {
        ObserverEventsPaginationBar(
            totalEvents = events.size,
            pageSize = pageSize,
            currentPage = currentPage,
            onPageChange = onPageChange,
            onPageSizeChange = onPageSizeChange,
            modifier = Modifier.fillMaxWidth(),
        )

        // Clamp only for slicing — never write state back during composition.
        val totalPages = maxOf(1, (events.size + pageSize - 1) / pageSize)
        val pagedEvents = events
            .drop(currentPage.coerceIn(0, totalPages - 1) * pageSize)
            .take(pageSize)

        // Top half: events table
        ObserverEventsTable(
            events = pagedEvents,
            selectedEvent = selectedEvent,
            onSelectEvent = onSelectEvent,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )

        HorizontalDivider()

        // Bottom half: event detail
        if (selectedEvent != null) {
            ObserverEventDetailView(
                event = selectedEvent,
                filterMode = filterMode,
                onFilterChange = onFilterChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Tap an event row above to see details",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Page-size selector + prev/next controls for the events table (SwiftUI
 * `PaginationControls` parity). Keeps to a single compact row so it fits the
 * narrow detail pane on phones; follows the same IconButton/labelSmall pattern
 * as the Query Workbench pagination chrome.
 */
@Composable
private fun ObserverEventsPaginationBar(
    totalEvents: Int,
    pageSize: Int,
    currentPage: Int,
    onPageChange: (Int) -> Unit,
    onPageSizeChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    var pageSizeExpanded by remember { mutableStateOf(false) }
    val totalPages = maxOf(1, (totalEvents + pageSize - 1) / pageSize)
    val clampedPage = currentPage.coerceIn(0, totalPages - 1)

    Row(
        modifier = modifier.padding(horizontal = 8.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "$totalEvents events",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.weight(1f))

        IconButton(
            onClick = { onPageChange(clampedPage - 1) },
            enabled = clampedPage > 0,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                contentDescription = "Previous page",
                modifier = Modifier.size(18.dp),
            )
        }
        Text(
            text = "Pg ${clampedPage + 1} / $totalPages",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        IconButton(
            onClick = { onPageChange(clampedPage + 1) },
            enabled = clampedPage < totalPages - 1,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Next page",
                modifier = Modifier.size(18.dp),
            )
        }

        Spacer(modifier = Modifier.width(4.dp))

        Box {
            TextButton(onClick = { pageSizeExpanded = true }) {
                Text(
                    text = "$pageSize",
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            DropdownMenu(
                expanded = pageSizeExpanded,
                onDismissRequest = { pageSizeExpanded = false },
            ) {
                pageSizeOptions.forEach { option ->
                    DropdownMenuItem(
                        text = { Text("$option per page") },
                        onClick = {
                            pageSizeExpanded = false
                            onPageSizeChange(option)
                        },
                    )
                }
            }
        }
    }
}
