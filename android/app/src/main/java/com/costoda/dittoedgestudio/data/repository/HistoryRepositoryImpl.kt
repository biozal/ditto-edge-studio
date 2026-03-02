package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.HistoryDao
import com.costoda.dittoedgestudio.data.db.entity.HistoryEntity
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

private const val MAX_HISTORY = 1000

class HistoryRepositoryImpl(private val dao: HistoryDao) : HistoryRepository {

    override fun observeHistory(databaseId: String): Flow<List<DittoQueryHistory>> =
        dao.observeByDatabase(databaseId).map { list -> list.map { it.toDomain() } }

    override suspend fun loadHistory(databaseId: String): List<DittoQueryHistory> =
        withContext(Dispatchers.IO) {
            dao.getByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun addToHistory(databaseId: String, query: String): Long =
        withContext(Dispatchers.IO) {
            // Deduplication: same query → update timestamp instead of inserting duplicate
            val existing = dao.findDuplicate(databaseId, query)
            if (existing != null) {
                val updated = existing.copy(createdDate = System.currentTimeMillis())
                dao.insert(updated)
                return@withContext updated.id
            }

            // Enforce max 1000 records per database
            val count = dao.countByDatabase(databaseId)
            if (count >= MAX_HISTORY) {
                dao.deleteOldest(databaseId, count - MAX_HISTORY + 1)
            }

            val entity = HistoryEntity(
                databaseId = databaseId,
                query = query,
                createdDate = System.currentTimeMillis()
            )
            dao.insert(entity)
        }

    override suspend fun removeHistoryItem(id: Long) = withContext(Dispatchers.IO) {
        dao.deleteById(id)
    }

    override suspend fun clearHistory(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun HistoryEntity.toDomain() = DittoQueryHistory(
    id = id,
    databaseId = databaseId,
    query = query,
    createdDate = createdDate
)
