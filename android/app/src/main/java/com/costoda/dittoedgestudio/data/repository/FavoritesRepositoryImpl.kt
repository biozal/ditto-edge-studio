package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.FavoriteDao
import com.costoda.dittoedgestudio.data.db.entity.FavoriteEntity
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class FavoritesRepositoryImpl(private val dao: FavoriteDao) : FavoritesRepository {

    override fun observeFavorites(databaseId: String): Flow<List<DittoQueryHistory>> =
        dao.observeByDatabase(databaseId).map { list -> list.map { it.toDomain() } }

    override suspend fun loadFavorites(databaseId: String): List<DittoQueryHistory> =
        withContext(Dispatchers.IO) {
            dao.getByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun saveFavorite(databaseId: String, query: String): Long? =
        withContext(Dispatchers.IO) {
            // Deduplication: same databaseId + query → no-op
            if (dao.findDuplicate(databaseId, query) != null) return@withContext null
            val entity = FavoriteEntity(
                databaseId = databaseId,
                query = query,
                createdDate = System.currentTimeMillis()
            )
            dao.insert(entity)
        }

    override suspend fun removeFavorite(id: Long) = withContext(Dispatchers.IO) {
        dao.deleteById(id)
    }

    override suspend fun removeAllFavorites(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun FavoriteEntity.toDomain() = DittoQueryHistory(
    id = id,
    databaseId = databaseId,
    query = query,
    createdDate = createdDate
)
