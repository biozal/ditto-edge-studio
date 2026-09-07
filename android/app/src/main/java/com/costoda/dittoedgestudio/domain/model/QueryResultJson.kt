package com.costoda.dittoedgestudio.domain.model

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Serializes a query result document list as pretty-printed JSON for export
 * (parity with the SwiftUI "Export JSON" action which writes the full result,
 * not just the visible page).
 */
fun queryDocumentsToJson(documents: List<Map<String, Any?>>): String {
    val array = JsonArray(documents.map { doc ->
        JsonObject(doc.mapValues { (_, v) -> v.toJsonElement() })
    })
    return kotlinx.serialization.json.Json { prettyPrint = true }.encodeToString(array)
}

private fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is String -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Int, is Long, is Double, is Float -> JsonPrimitive(this as Number)
    is Number -> JsonPrimitive(toString())
    is Map<*, *> -> JsonObject(
        entries.associate { (k, v) -> k.toString() to v.toJsonElement() },
    )
    is List<*> -> JsonArray(map { it.toJsonElement() })
    is Array<*> -> JsonArray(map { it.toJsonElement() })
    else -> JsonPrimitive(toString())
}
