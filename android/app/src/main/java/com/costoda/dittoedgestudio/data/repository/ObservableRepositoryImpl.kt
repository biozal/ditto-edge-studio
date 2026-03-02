package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.ObservableDao
import com.costoda.dittoedgestudio.data.db.entity.ObservableEntity
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class ObservableRepositoryImpl(private val dao: ObservableDao) : ObservableRepository {

    override fun observeObservables(databaseId: String): Flow<List<DittoObservable>> =
        dao.observeByDatabase(databaseId).map { list -> list.map { it.toDomain() } }

    override suspend fun loadObservables(databaseId: String): List<DittoObservable> =
        withContext(Dispatchers.IO) {
            dao.getByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun saveObservable(observable: DittoObservable): Long =
        withContext(Dispatchers.IO) {
            dao.insert(observable.toEntity())
        }

    override suspend fun updateObservable(observable: DittoObservable) =
        withContext(Dispatchers.IO) {
            dao.update(observable.toEntity())
        }

    override suspend fun removeObservable(id: Long) = withContext(Dispatchers.IO) {
        dao.deleteById(id)
    }

    override suspend fun removeAllObservables(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun ObservableEntity.toDomain() = DittoObservable(
    id = id,
    databaseId = databaseId,
    name = name,
    query = query,
    isActive = isActive,
    lastUpdated = lastUpdated
)

private fun DittoObservable.toEntity() = ObservableEntity(
    id = id,
    databaseId = databaseId,
    name = name,
    query = query,
    isActive = isActive,
    lastUpdated = lastUpdated
)
