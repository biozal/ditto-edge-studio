package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import kotlinx.coroutines.flow.Flow

interface SubscriptionsRepository {
    fun observeSubscriptions(databaseId: String): Flow<List<DittoSubscription>>
    suspend fun loadSubscriptions(databaseId: String): List<DittoSubscription>
    suspend fun saveSubscription(subscription: DittoSubscription): Long
    suspend fun updateSubscription(subscription: DittoSubscription)
    suspend fun removeSubscription(id: Long)
    suspend fun removeAllSubscriptions(databaseId: String)
}
