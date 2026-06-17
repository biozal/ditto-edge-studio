package com.costoda.dittoedgestudio.domain.model

data class QueryResult(
    val documents: List<Map<String, Any?>>,
    val totalCount: Int,
    val executionTimeMs: Long,
    val explainPlan: String? = null,
    /** Set only when the query was a SELECT prefixed with PROFILE and the envelope was parsed. */
    val profile: QueryProfile? = null,
)
