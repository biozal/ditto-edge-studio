package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel

@Composable
fun QueryEditorScreen(
    viewModel: QueryEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val queryText by viewModel.queryText.collectAsStateWithLifecycle()
    val isExecuting by viewModel.isExecuting.collectAsStateWithLifecycle()
    val executionError by viewModel.executionError.collectAsStateWithLifecycle()
    val queryResult by viewModel.queryResult.collectAsStateWithLifecycle()
    val displayedDocuments by viewModel.displayedDocuments.collectAsStateWithLifecycle()
    val captureProfilingData by viewModel.captureProfilingData.collectAsStateWithLifecycle()

    Column(modifier = modifier.fillMaxSize()) {
        QueryEditorView(
            queryText = queryText,
            onQueryTextChange = { viewModel.onQueryTextChange(it) },
            // Ctrl+Enter / Cmd+Enter runs the query; disabled while a query is executing.
            onRunQuery = if (!isExecuting) viewModel::executeQuery else null,
            modifier = Modifier.weight(0.4f),
        )
        HorizontalDivider()
        QueryResultsView(
            queryResult = queryResult,
            displayedDocuments = displayedDocuments,
            isExecuting = isExecuting,
            executionError = executionError,
            captureProfilingData = captureProfilingData,
            lastQueryText = queryText,
            onDocumentSelected = { viewModel.selectDocument(it) },
            onAddConfirm = { uri, docId, coll, fieldName, metadata, ctx ->
                viewModel.addAttachment(uri, docId, coll, fieldName, metadata, ctx)
            },
            onDeleteConfirm = { docId, coll, attachments ->
                viewModel.deleteAttachments(docId, coll, attachments)
            },
            modifier = Modifier.weight(0.6f),
        )
    }
}
