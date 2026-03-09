@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryResult

@Composable
fun QueryResultsView(
    queryResult: QueryResult?,
    displayedDocuments: List<Map<String, Any?>>,
    isExecuting: Boolean,
    executionError: String?,
    onDocumentSelected: (Map<String, Any?>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by remember { mutableIntStateOf(0) }

    Column(modifier = modifier) {
        // ── Tab row ──────────────────────────────────────────────────────────
        SecondaryTabRow(selectedTabIndex = selectedTabIndex) {
            Tab(
                selected = selectedTabIndex == 0,
                onClick = { selectedTabIndex = 0 },
                text = { Text("JSON") },
            )
            Tab(
                selected = selectedTabIndex == 1,
                onClick = { selectedTabIndex = 1 },
                text = { Text("TABLE") },
            )
        }

        if (isExecuting) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        // ── Content ───────────────────────────────────────────────────────────
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            when {
                executionError != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = executionError,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
                queryResult == null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "Run a query to see results",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                queryResult.documents.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "No results",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                selectedTabIndex == 0 -> {
                    ResultJsonView(
                        documents = displayedDocuments,
                        onDocumentSelected = onDocumentSelected,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                else -> {
                    ResultTableView(
                        documents = displayedDocuments,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }
}
