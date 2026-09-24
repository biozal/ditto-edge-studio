package com.costoda.dittoedgestudio.domain.model

/** One index suggestion from an `ADVISE` run (SDK 5.1). */
data class QueryIndexSuggestion(
    val collection: String,
    val reason: String,
    /** Full `CREATE INDEX …` statement, executed verbatim after user confirmation. */
    val statement: String,
)

/** Result of an `ADVISE <SELECT …>` execution. */
data class QueryAdvice(
    val statement: String,
    val outcome: String?,
    val suggestions: List<QueryIndexSuggestion>,
)

/**
 * Extracts advice from an ADVISE result set (parity with the extension's
 * `advise.ts`): forward-compatible — scans every row, merges, drops
 * suggestions missing the fields the UI needs.
 */
object QueryAdviceExtractor {

    fun extract(rows: List<Map<String, Any?>>): QueryAdvice? {
        var statement: String? = null
        var outcome: String? = null
        val suggestions = mutableListOf<QueryIndexSuggestion>()
        var found = false

        for (row in rows) {
            val advice = row["advice"] as? Map<*, *> ?: continue
            found = true
            if (statement == null) statement = advice["statement"] as? String
            if (outcome == null) outcome = advice["outcome"] as? String
            (advice["suggestedIndexes"] as? List<*>)?.forEach { raw ->
                parseSuggestion(raw)?.let { suggestions.add(it) }
            }
        }

        return if (found) QueryAdvice(statement ?: "", outcome, suggestions) else null
    }

    internal fun parseSuggestion(raw: Any?): QueryIndexSuggestion? {
        val map = raw as? Map<*, *> ?: return null
        val collection = map["collection"] as? String ?: return null
        val statement = map["statement"] as? String ?: return null
        if (statement.isEmpty()) return null
        return QueryIndexSuggestion(
            collection = collection,
            reason = (map["reason"] as? String) ?: "",
            statement = statement,
        )
    }
}

/** Statement-shape guards shared by the toolbar gating. */
object DqlStatements {
    fun isSelectStatement(query: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return false
        val upper = trimmed.uppercase()
        if (!upper.startsWith("SELECT")) return false
        return trimmed.length == 6 || trimmed[6].isWhitespace()
    }

    /** `EXPLAIN ADVISE …` is not valid syntax. */
    fun isAdviseStatement(query: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return false
        val upper = trimmed.uppercase()
        if (!upper.startsWith("ADVISE")) return false
        return trimmed.length == 6 || trimmed[6].isWhitespace()
    }
}
