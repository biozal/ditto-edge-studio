package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.flow.Flow

/**
 * Per-query metrics captures, scoped per database (the Ditto databaseId string, same
 * value as `history.databaseId`).
 *
 * The store is independent of query history: `QueryMetrics.historyId` is a plain
 * reference, not a foreign key, so history housekeeping never wipes metrics captures
 * (SwiftUI parity). Detail lookups key on [QueryMetrics.id] — the row's own primary
 * key — because `historyId` is non-unique (history dedups re-runs of the same query).
 */
interface QueryMetricsRepository {
    suspend fun save(metrics: QueryMetrics): Long
    suspend fun getById(id: Long): QueryMetrics?
    fun observeByDatabase(databaseId: String): Flow<List<QueryMetrics>>
    suspend fun getAllByDatabase(databaseId: String): List<QueryMetrics>
    suspend fun deleteAllByDatabase(databaseId: String)
}
