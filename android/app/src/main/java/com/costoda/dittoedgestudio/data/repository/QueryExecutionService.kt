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
        val result = ditto.store.execute(query)
        val elapsed = System.currentTimeMillis() - start
        val documents = result.items.map { item ->
            runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                .getOrDefault(emptyMap())
        }
        result.close()
        QueryResult(
            documents = documents,
            totalCount = documents.size,
            executionTimeMs = elapsed,
        )
    }

    suspend fun explain(query: String): QueryResult = execute("EXPLAIN $query")

    private fun parseJsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            map[key] = when (val value = json.opt(key)) {
                JSONObject.NULL -> null
                is JSONObject -> parseJsonToMap(value)
                else -> value
            }
        }
        return map
    }
}
