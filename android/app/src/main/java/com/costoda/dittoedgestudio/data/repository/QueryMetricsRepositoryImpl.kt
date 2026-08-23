package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.QueryMetricsDao
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import org.json.JSONArray

class QueryMetricsRepositoryImpl(private val dao: QueryMetricsDao) : QueryMetricsRepository {

    override suspend fun save(metrics: QueryMetrics): Long = withContext(Dispatchers.IO) {
        val entity = QueryMetricsEntity(
            historyId = metrics.historyId,
            databaseId = metrics.databaseId,
            executionTimeMs = metrics.executionTimeMs,
            docsExamined = metrics.docsExamined,
            docsReturned = metrics.docsReturned,
            indexesUsed = JSONArray(metrics.indexesUsed).toString(),
            bytesRead = metrics.bytesRead,
            explainPlan = metrics.explainPlan,
            capturedAt = metrics.capturedAt,
            queryText = metrics.queryText,
        )
        // Match SwiftUI's QueryMetricsRepository: retain at most MAX_RECORDS per
        // database, evicting oldest — atomically, so a mid-pair failure can't leave
        // the table over cap.
        return@withContext dao.insertAndTrim(entity, MAX_RECORDS)
    }

    override suspend fun getById(id: Long): QueryMetrics? = withContext(Dispatchers.IO) {
        dao.getById(id)?.toDomain()
    }

    // Flows from Room run on Dispatchers.IO automatically — no explicit dispatch needed.
    override fun observeByDatabase(databaseId: String): Flow<List<QueryMetrics>> =
        dao.observeByDatabase(databaseId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun getAllByDatabase(databaseId: String): List<QueryMetrics> =
        withContext(Dispatchers.IO) {
            dao.getAllByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun deleteAllByDatabase(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteAllByDatabase(databaseId)
    }

    companion object {
        /** Record retention cap — same value as SwiftUI's `QueryMetricsRepository.maxRecords`. */
        const val MAX_RECORDS = 200
    }
}

private fun QueryMetricsEntity.toDomain(): QueryMetrics {
    val arr = runCatching { JSONArray(indexesUsed) }.getOrDefault(JSONArray())
    val indexes = buildList {
        for (i in 0 until arr.length()) arr.optString(i).takeIf { it.isNotBlank() }?.let { add(it) }
    }
    return QueryMetrics(
        id = id,
        historyId = historyId,
        databaseId = databaseId,
        executionTimeMs = executionTimeMs,
        docsExamined = docsExamined,
        docsReturned = docsReturned,
        indexesUsed = indexes,
        bytesRead = bytesRead,
        explainPlan = explainPlan,
        capturedAt = capturedAt,
        queryText = queryText,
    )
}
