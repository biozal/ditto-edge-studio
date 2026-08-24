package com.costoda.dittoedgestudio.domain.model

/**
 * Generates DQL statement templates (port of SwiftUI's `DQLGenerator`).
 * Field-type-aware placeholders derive types from a sample document —
 * typically the first row of the current query result.
 */
enum class DqlStatementKind { SELECT, INSERT, UPDATE, DELETE, EVICT }

object DqlGenerator {

    private val FROM_COLLECTION = Regex("(?i)\\bFROM\\s+([A-Za-z_][A-Za-z0-9_]*)")

    /** Extracts the collection name from a query (SwiftUI `QueryInfo.collectionName` parity). */
    fun collectionName(query: String): String? = FROM_COLLECTION.find(query)?.groupValues?.get(1)

    /**
     * Field names from the first result document: sorted with `_id` first
     * (SwiftUI `queryExtractFieldNames` parity).
     */
    fun fieldNames(sampleDocument: Map<String, Any?>?): List<String> {
        val keys = sampleDocument?.keys?.sorted()?.toMutableList() ?: return emptyList()
        // SwiftUI parity: _id floats to the front when present (not injected).
        if (keys.remove("_id")) keys.add(0, "_id")
        return keys
    }

    fun generateSelect(collection: String, fields: List<String>): String =
        "SELECT ${fields.joinToString(", ")} FROM $collection"

    fun generateSelectAll(collection: String): String = "SELECT * FROM $collection"

    fun generateInsert(
        collection: String,
        fields: List<String>,
        sampleDocument: Map<String, Any?>? = null,
    ): String {
        val placeholders = fields.joinToString(", ") { field ->
            "\"$field\": ${placeholderValue(field, sampleDocument?.containsKey(field) == true, sampleDocument?.get(field))}"
        }
        return "INSERT INTO $collection DOCUMENTS ({ $placeholders })"
    }

    /** _id is excluded from the SET clause (SwiftUI parity). */
    fun generateUpdate(
        collection: String,
        fields: List<String>,
        sampleDocument: Map<String, Any?>? = null,
    ): String {
        val toUpdate = fields.filter { it != "_id" }
        val setClause = toUpdate.joinToString(", ") { field ->
            "$field = ${placeholderValue(field, sampleDocument?.containsKey(field) == true, sampleDocument?.get(field))}"
        }
        return "UPDATE $collection SET $setClause WHERE _id = '<document-id>'"
    }

    fun generateDelete(collection: String): String =
        "DELETE FROM $collection WHERE _id = '<document-id>'"

    fun generateEvict(collection: String): String =
        "EVICT FROM $collection WHERE _id = '<document-id>'"

    /** Placeholder by name and observed value type (matches the Swift cell-type switch). */
    private fun placeholderValue(field: String, present: Boolean, sampleValue: Any?): String {
        if (field == "_id") return "\"<document-id>\""
        if (!present) return "\"<value>\""
        return when (sampleValue) {
            null -> "null" // the field exists with an explicit null value
            is String -> "\"<value>\""
            is Number -> "0"
            is Boolean -> "true"
            is Map<*, *>, is List<*> -> "{}"
            else -> "\"<value>\""
        }
    }
}
