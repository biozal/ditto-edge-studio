package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class LocalQueryExecutionService(private val dittoManager: DittoManager) {

    suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
        val ditto = dittoManager.currentInstance()
            ?: error("No active Ditto instance")
        val start = System.currentTimeMillis()
        val items = ditto.store.execute(query) { result ->
            result.items.map { item ->
                try {
                    runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                        .getOrDefault(emptyMap<String, Any?>())
                } finally {
                    // Release the native item handle — same contract as explainPlan below.
                    item.dematerialize()
                }
            }
        }
        val elapsed = System.currentTimeMillis() - start
        val (docs, profile) = QueryProfileParser.partition(items)
        QueryResult(
            documents = docs,
            totalCount = docs.size,
            executionTimeMs = elapsed,
            profile = profile,
        )
    }

    suspend fun explain(query: String): QueryResult = execute("EXPLAIN $query")

    /**
     * Runs EXPLAIN against [query] and returns the first result item as pretty-printed
     * JSON — the Android counterpart of SwiftUI's `QueryService.runExplain`, used to
     * populate `QueryMetrics.explainPlan` when metrics capture is on.
     *
     * Never throws: a failure is returned as an "EXPLAIN failed: …" string so the
     * metrics record is still saved. Returns "" for queries that are already EXPLAIN
     * statements (guards against recursive EXPLAIN), matching SwiftUI.
     */
    suspend fun explainPlan(query: String): String = withContext(Dispatchers.IO) {
        if (query.trimStart().uppercase().startsWith("EXPLAIN")) return@withContext ""
        val ditto = dittoManager.currentInstance()
            ?: return@withContext "EXPLAIN failed: no active Ditto instance"
        try {
            ditto.store.execute("EXPLAIN $query") { result ->
                var output = "No explain output"
                result.items.forEachIndexed { index, item ->
                    if (index == 0) {
                        val map = runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                            .getOrDefault(emptyMap())
                        if (map.isNotEmpty()) output = toSortedPrettyJson(map)
                    }
                    item.dematerialize()
                }
                output
            }
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            "EXPLAIN failed: ${t.message}"
        }
    }
}
