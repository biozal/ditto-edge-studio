package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryMetrics

interface QueryMetricsRepository {
    suspend fun save(metrics: QueryMetrics): Long
    suspend fun getByHistoryId(historyId: Long): QueryMetrics?
    suspend fun getAllMetrics(): List<QueryMetrics>
    suspend fun deleteAll()
}
