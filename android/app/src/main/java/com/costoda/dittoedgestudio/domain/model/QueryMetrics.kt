package com.costoda.dittoedgestudio.domain.model

data class QueryMetrics(
    /** The metrics row's own primary key (0 before persistence). Detail navigation and
     *  list highlighting key on this — NOT on [historyId], which is non-unique because
     *  history dedups re-runs of the same query onto one history row. */
    val id: Long = 0,
    /** Reference to the history row this capture was recorded against. Non-unique and
     *  NOT a foreign key — history housekeeping (clear/trim) must not wipe metrics. */
    val historyId: Long,
    /** The Ditto databaseId string (same value as `history.databaseId`) this capture
     *  belongs to; metrics are scoped per database. */
    val databaseId: String = "",
    val executionTimeMs: Long,
    val docsExamined: Int,
    val docsReturned: Int,
    val indexesUsed: List<String>,
    val bytesRead: Long,
    val explainPlan: String?,
    val capturedAt: Long,
    val queryText: String = "",
) {
    companion object {
        /**
         * Derives index usage from EXPLAIN output using the same heuristic as SwiftUI's
         * `QueryExplainRecord.usedIndex`: any case-insensitive mention of "index" in the
         * plan means the query planner likely used an index (see docs/METRICS.md).
         *
         * The returned list is a presence marker only — every UI reads `isNotEmpty()`.
         * Ditto's EXPLAIN does not reliably name the index, so no name extraction is
         * attempted (same as SwiftUI).
         */
        fun indexesUsedFromExplain(explainPlan: String?): List<String> =
            if (explainPlan?.lowercase()?.contains("index") == true) listOf("index")
            else emptyList()
    }
}
