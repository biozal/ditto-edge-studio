package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent

private data class TableColumn(val label: String, val width: Dp)

private val columns = listOf(
    TableColumn("Time", 180.dp),
    TableColumn("Count", 70.dp),
    TableColumn("Inserted", 80.dp),
    TableColumn("Updated", 80.dp),
    TableColumn("Deleted", 70.dp),
    TableColumn("Moves", 70.dp),
)

@Composable
fun ObserverEventsTable(
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()

    Column(modifier = modifier) {
        // Sticky header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(scrollState)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(vertical = 8.dp),
        ) {
            columns.forEach { col ->
                Text(
                    text = col.label,
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .width(col.width)
                        .padding(horizontal = 8.dp),
                )
            }
        }

        // Event rows
        LazyColumn(modifier = Modifier.fillMaxWidth()) {
            itemsIndexed(events, key = { _, event -> event.id }) { index, event ->
                val isSelected = event.id == selectedEvent?.id
                val rowBackground = when {
                    isSelected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                    index % 2 == 1 -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
                    else -> MaterialTheme.colorScheme.surface
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(scrollState)
                        .clickable { onSelectEvent(event) }
                        .background(rowBackground)
                        .padding(vertical = 6.dp),
                ) {
                    val values = listOf(
                        event.eventTime.substringAfter("T").substringBefore("."),
                        event.data.size.toString(),
                        event.insertIndexes.size.toString(),
                        event.updatedIndexes.size.toString(),
                        event.deletedIndexes.size.toString(),
                        event.movedIndexes.size.toString(),
                    )
                    values.forEachIndexed { i, value ->
                        Text(
                            text = value,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .width(columns[i].width)
                                .padding(horizontal = 8.dp),
                        )
                    }
                }
            }
        }
    }
}
