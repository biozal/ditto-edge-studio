package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

@Composable
fun ObserverEventDetailView(
    event: DittoObserveEvent,
    filterMode: EventFilterMode,
    onFilterChange: (EventFilterMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    val filteredDocs = when (filterMode) {
        EventFilterMode.ALL -> event.data
        EventFilterMode.INSERTED -> event.getInsertedData()
        EventFilterMode.UPDATED -> event.getUpdatedData()
    }

    Column(modifier = modifier.fillMaxSize().padding(8.dp)) {
        // Header with counts
        Text(
            text = "Event: ${event.eventTime.substringAfter("T").substringBefore(".")}",
            style = MaterialTheme.typography.titleSmall,
        )
        Text(
            text = "Docs: ${event.data.size}  Ins: ${event.insertIndexes.size}  " +
                "Upd: ${event.updatedIndexes.size}  Del: ${event.deletedIndexes.size}  " +
                "Mov: ${event.movedIndexes.size}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Filter chips
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
        ) {
            EventFilterMode.entries.forEach { mode ->
                FilterChip(
                    selected = filterMode == mode,
                    onClick = { onFilterChange(mode) },
                    label = {
                        Text(
                            when (mode) {
                                EventFilterMode.ALL -> "All Items (${event.data.size})"
                                EventFilterMode.INSERTED -> "Inserted (${event.insertIndexes.size})"
                                EventFilterMode.UPDATED -> "Updated (${event.updatedIndexes.size})"
                            },
                        )
                    },
                    modifier = Modifier.padding(end = 8.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Document cards
        if (filteredDocs.isEmpty()) {
            Text(
                text = "No documents for this filter",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
        } else {
            LazyColumn {
                itemsIndexed(filteredDocs) { _, doc ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                    ) {
                        Text(
                            text = doc,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.padding(12.dp),
                        )
                    }
                }
            }
        }
    }
}
