package com.costoda.dittoedgestudio.domain.model

data class QueryMetrics(
    val historyId: Long,
    val executionTimeMs: Long,
    val docsExamined: Int,
    val docsReturned: Int,
    val indexesUsed: List<String>,
    val bytesRead: Long,
    val explainPlan: String?,
    val capturedAt: Long,
)
