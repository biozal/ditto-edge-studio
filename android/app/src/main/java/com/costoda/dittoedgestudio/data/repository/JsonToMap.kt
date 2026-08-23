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

/**
 * Serialize a parsed result row back to pretty-printed JSON with sorted keys and
 * 2-space indentation — mirrors SwiftUI's
 * `JSONSerialization(options: [.prettyPrinted, .sortedKeys])`.
 *
 * Used to render EXPLAIN output for Query Metrics records
 * (`LocalQueryExecutionService.explainPlan`).
 */
fun toSortedPrettyJson(value: Any?, indent: Int = 0): String {
    val pad = "  ".repeat(indent)
    val childPad = "  ".repeat(indent + 1)
    return when (value) {
        null -> "null"
        is Map<*, *> -> if (value.isEmpty()) {
            "{}"
        } else {
            value.entries
                .sortedBy { it.key.toString() }
                .joinToString(",\n") { (k, v) ->
                    "$childPad${JSONObject.quote(k.toString())}: ${toSortedPrettyJson(v, indent + 1)}"
                }
                .let { "{\n$it\n$pad}" }
        }
        is List<*> -> if (value.isEmpty()) {
            "[]"
        } else {
            value.joinToString(",\n") { "$childPad${toSortedPrettyJson(it, indent + 1)}" }
                .let { "[\n$it\n$pad]" }
        }
        is String -> JSONObject.quote(value)
        is Boolean, is Number -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
}
