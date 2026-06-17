package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class QueryExecutionService(private val dittoManager: DittoManager) {

    suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
        val ditto = dittoManager.currentInstance()
            ?: error("No active Ditto instance")
        val start = System.currentTimeMillis()
        val documents = ditto.store.execute(query) { result ->
            result.items.map { item ->
                runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                    .getOrDefault(emptyMap<String, Any?>())
            }
        }
        val elapsed = System.currentTimeMillis() - start
        QueryResult(
            documents = documents,
            totalCount = documents.size,
            executionTimeMs = elapsed,
        )
    }

    suspend fun explain(query: String): QueryResult = execute("EXPLAIN $query")
}
