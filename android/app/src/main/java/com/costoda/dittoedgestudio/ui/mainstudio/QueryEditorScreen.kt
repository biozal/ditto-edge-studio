package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel

@Composable
fun QueryEditorScreen(
    viewModel: QueryEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val queryText by viewModel.queryText.collectAsState()
    val isExecuting by viewModel.isExecuting.collectAsState()
    val executionError by viewModel.executionError.collectAsState()
    val queryResult by viewModel.queryResult.collectAsState()
    val displayedDocuments by viewModel.displayedDocuments.collectAsState()

    Column(modifier = modifier.fillMaxSize()) {
        QueryEditorView(
            queryText = queryText,
            onQueryTextChange = { viewModel.onQueryTextChange(it) },
            modifier = Modifier.weight(0.4f),
        )
        HorizontalDivider()
        QueryResultsView(
            queryResult = queryResult,
            displayedDocuments = displayedDocuments,
            isExecuting = isExecuting,
            executionError = executionError,
            onDocumentSelected = { viewModel.selectDocument(it) },
            modifier = Modifier.weight(0.6f),
        )
    }
}
