package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

@Composable
fun ObserverDetailScreen(
    selectedObserver: DittoObservable?,
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    filterMode: EventFilterMode,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    onFilterChange: (EventFilterMode) -> Unit,
    modifier: Modifier = Modifier,
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
        // Top half: events table
        ObserverEventsTable(
            events = events,
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
