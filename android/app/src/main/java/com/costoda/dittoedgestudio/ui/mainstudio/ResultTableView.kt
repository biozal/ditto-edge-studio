package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private const val CELL_MIN_WIDTH_DP = 120
private const val CELL_PADDING_DP = 8

@Composable
fun ResultTableView(
    documents: List<Map<String, Any?>>,
    modifier: Modifier = Modifier,
) {
    if (documents.isEmpty()) {
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            Text(
                text = "No results",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    // Build column headers: _id first, then sorted remaining keys
    val columns = remember(documents) {
        val allKeys = documents.flatMap { it.keys }.toSet()
        buildList {
            if ("_id" in allKeys) add("_id")
            addAll(allKeys.filter { it != "_id" }.sorted())
        }
    }

    val scrollState: ScrollState = rememberScrollState()

    Column(modifier = modifier) {
        // Sticky header row
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(scrollState),
            ) {
                columns.forEach { col ->
                    Text(
                        text = col,
                        color = MaterialTheme.colorScheme.onSurface,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .widthIn(min = CELL_MIN_WIDTH_DP.dp)
                            .padding(CELL_PADDING_DP.dp),
                    )
                }
            }
        }
        HorizontalDivider()

        // Data rows
        LazyColumn {
            itemsIndexed(documents) { index, doc ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            if (index % 2 == 0) MaterialTheme.colorScheme.surface
                            else MaterialTheme.colorScheme.surfaceContainerLowest,
                        )
                        .horizontalScroll(scrollState),
                ) {
                    columns.forEach { col ->
                        val value = doc[col]?.toString() ?: ""
                        Text(
                            text = value,
                            color = MaterialTheme.colorScheme.onSurface,
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .widthIn(min = CELL_MIN_WIDTH_DP.dp)
                                .padding(CELL_PADDING_DP.dp),
                        )
                    }
                }
                HorizontalDivider(thickness = 0.5.dp)
            }
        }
    }
}

