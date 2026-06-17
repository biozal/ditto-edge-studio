package com.costoda.dittoedgestudio.data.repository

import org.json.JSONArray
import org.json.JSONObject

/**
 * Convert a [JSONObject] to a plain [Map] so result rows render uniformly across the
 * local-Ditto and HTTP execution paths.
 *
 * Nested objects recurse; nested arrays are normalized to `List<Any?>`; `JSONObject.NULL`
 * collapses to Kotlin `null`. Pulled out of the previous `QueryExecutionService` so both
 * `LocalQueryExecutionService` and `HttpQueryExecutionService` can share one implementation.
 */
fun parseJsonToMap(json: JSONObject): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    for (key in json.keys()) {
        map[key] = unwrap(json.opt(key))
    }
    return map
}

private fun unwrap(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> parseJsonToMap(value)
    is JSONArray -> List(value.length()) { i -> unwrap(value.opt(i)) }
    else -> value
}
