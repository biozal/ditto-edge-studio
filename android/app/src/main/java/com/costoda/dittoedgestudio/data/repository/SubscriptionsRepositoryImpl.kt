package com.costoda.dittoedgestudio.data.repository

import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.db.dao.SubscriptionDao
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

private const val TAG = "SubscriptionsRepository"

class SubscriptionsRepositoryImpl(private val dao: SubscriptionDao) : SubscriptionsRepository {

    override fun observeSubscriptions(databaseId: String): Flow<List<DittoSubscription>> =
        dao.observeByDatabase(databaseId).map { list -> list.map { it.toDomain() } }

    override suspend fun loadSubscriptions(databaseId: String): List<DittoSubscription> =
        withContext(Dispatchers.IO) {
            dao.getByDatabase(databaseId).map { it.toDomain() }
        }

    override suspend fun saveSubscription(subscription: DittoSubscription): Long =
        withContext(Dispatchers.IO) {
            val newId = dao.insert(subscription.toEntity())
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "INSERT sub: in=${subscription.id} → out=$newId dbId='${subscription.databaseId}'")
            }
            newId
        }

    override suspend fun updateSubscription(subscription: DittoSubscription) =
        withContext(Dispatchers.IO) {
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "UPDATE sub id=${subscription.id}")
            }
            dao.update(subscription.toEntity())
        }

    override suspend fun removeSubscription(id: Long) = withContext(Dispatchers.IO) {
        if (BuildConfig.DEBUG) {
            Log.w(TAG, "DELETE sub id=$id")
        }
        dao.deleteById(id)
    }

    override suspend fun removeAllSubscriptions(databaseId: String) = withContext(Dispatchers.IO) {
        if (BuildConfig.DEBUG) {
            Log.w(TAG, "DELETE ALL subs for dbId='$databaseId'")
        }
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
