package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.SubscriptionDao
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class SubscriptionsRepositoryImpl(private val dao: SubscriptionDao) : SubscriptionsRepository {

    override fun observeSubscriptions(databaseId: String): Flow<List<DittoSubscription>> =
        dao.observeByDatabase(databaseId).map { list -> list.map { it.toDomain() } }

    override suspend fun loadSubscriptions(databaseId: String): List<DittoSubscription> =
        withContext(Dispatchers.IO) {
            dao.getByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun saveSubscription(subscription: DittoSubscription): Long =
        withContext(Dispatchers.IO) {
            dao.insert(subscription.toEntity())
        }

    override suspend fun updateSubscription(subscription: DittoSubscription) =
        withContext(Dispatchers.IO) {
            dao.update(subscription.toEntity())
        }

    override suspend fun removeSubscription(id: Long) = withContext(Dispatchers.IO) {
        dao.deleteById(id)
    }

    override suspend fun removeAllSubscriptions(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun SubscriptionEntity.toDomain() = DittoSubscription(
    id = id,
    databaseId = databaseId,
    name = name,
    query = query
)

private fun DittoSubscription.toEntity() = SubscriptionEntity(
    id = id,
    databaseId = databaseId,
    name = name,
    query = query
)
