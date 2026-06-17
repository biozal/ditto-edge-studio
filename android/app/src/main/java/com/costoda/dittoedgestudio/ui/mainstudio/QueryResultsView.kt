package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.costoda.dittoedgestudio.ui.mainstudio.profile.ProfileViewerView

@Composable
fun QueryResultsView(
    queryResult: QueryResult?,
    displayedDocuments: List<Map<String, Any?>>,
    isExecuting: Boolean,
    executionError: String?,
    captureProfilingData: Boolean,
    lastQueryText: String,
    onDocumentSelected: (Map<String, Any?>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by remember { mutableIntStateOf(0) }

    Column(modifier = modifier) {
        // ── View switcher ─────────────────────────────────────────────────────
        DittoConnectedButtonGroup(
            options = listOf("JSON", "TABLE", "PROFILE"),
            selectedIndex = selectedTabIndex,
            onSelect = { selectedTabIndex = it },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

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
                executionError != null && selectedTabIndex != 2 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = executionError,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
                queryResult == null && selectedTabIndex != 2 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "Run a query to see results",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                queryResult?.documents?.isEmpty() == true && selectedTabIndex != 2 -> {
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
                selectedTabIndex == 1 -> {
                    ResultTableView(
                        documents = displayedDocuments,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                else -> {
                    ProfileViewerView(
                        profile = queryResult?.profile,
                        metricsEnabled = captureProfilingData,
                        lastQueryText = lastQueryText,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }
}
