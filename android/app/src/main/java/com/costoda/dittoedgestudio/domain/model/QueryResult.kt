package com.costoda.dittoedgestudio.domain.model

data class QueryResult(
    val documents: List<Map<String, Any?>>,
    val totalCount: Int,
    val executionTimeMs: Long,
    val explainPlan: String? = null,
)
