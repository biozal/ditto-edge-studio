package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryResult

/**
 * Dispatcher facade: routes [execute] to [LocalQueryExecutionService] or
 * [HttpQueryExecutionService] based on the picker mode set on `QueryWorkbenchState`.
 *
 * [explain] is local-only (matches SwiftUI's "PROFILE is local-only for v1"; see the
 * design spec §5.7). Unknown modes fall back to Local — defensive in case the picker
 * state drifts from the supported set.
 */
class QueryExecutionService(
    private val local: LocalQueryExecutionService,
    private val http: HttpQueryExecutionService,
) {

    suspend fun execute(query: String, mode: String = "Local"): QueryResult =
        if (mode == "HTTP") http.execute(query) else local.execute(query)

    suspend fun explain(query: String): QueryResult = local.explain(query)

    /**
     * EXPLAIN output for [query] as pretty-printed JSON, for Query Metrics capture.
     * Local-only (like [explain]); never throws — failures come back as
     * "EXPLAIN failed: …" strings. See [LocalQueryExecutionService.explainPlan].
     */
    suspend fun explainPlan(query: String): String = local.explainPlan(query)
}
