package com.costoda.dittoedgestudio.data.repository

/**
 * Thrown by [HttpQueryExecutionService] when the remote endpoint returns a non-2xx response.
 *
 * The existing `runCatching { ... }.onFailure { workbench.executionError.value = e.message }`
 * block in `QueryEditorViewModel.executeQuery()` surfaces the message string in the results
 * pane, so the response body is embedded in the message for visibility.
 */
class QueryExecutionException(
    val httpStatus: Int,
    val body: String,
) : RuntimeException("HTTP $httpStatus: $body")
