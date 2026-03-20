package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.QueryMetricsDao
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray

class QueryMetricsRepositoryImpl(private val dao: QueryMetricsDao) : QueryMetricsRepository {

    override suspend fun save(metrics: QueryMetrics): Long = withContext(Dispatchers.IO) {
        val entity = QueryMetricsEntity(
            historyId = metrics.historyId,
            executionTimeMs = metrics.executionTimeMs,
            docsExamined = metrics.docsExamined,
            docsReturned = metrics.docsReturned,
            indexesUsed = JSONArray(metrics.indexesUsed).toString(),
            bytesRead = metrics.bytesRead,
            explainPlan = metrics.explainPlan,
            capturedAt = metrics.capturedAt,
        )
        dao.insert(entity)
    }

    override suspend fun getByHistoryId(historyId: Long): QueryMetrics? = withContext(Dispatchers.IO) {
        dao.getByHistoryId(historyId)?.toDomain()
    }

    override suspend fun getAllMetrics(): List<QueryMetrics> = withContext(Dispatchers.IO) {
        dao.getAll().map { it.toDomain() }
    }

    override suspend fun deleteAll() = withContext(Dispatchers.IO) {
        dao.deleteAll()
    }
}

private fun QueryMetricsEntity.toDomain(): QueryMetrics {
    val arr = runCatching { JSONArray(indexesUsed) }.getOrDefault(JSONArray())
    val indexes = buildList {
        for (i in 0 until arr.length()) arr.optString(i).takeIf { it.isNotBlank() }?.let { add(it) }
    }
    return QueryMetrics(
        historyId = historyId,
        executionTimeMs = executionTimeMs,
        docsExamined = docsExamined,
        docsReturned = docsReturned,
        indexesUsed = indexes,
        bytesRead = bytesRead,
        explainPlan = explainPlan,
        capturedAt = capturedAt,
    )
}
