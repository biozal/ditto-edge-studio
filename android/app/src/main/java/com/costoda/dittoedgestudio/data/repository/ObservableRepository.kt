package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoObservable
import kotlinx.coroutines.flow.Flow

interface ObservableRepository {
    fun observeObservables(databaseId: String): Flow<List<DittoObservable>>
    suspend fun loadObservables(databaseId: String): List<DittoObservable>
    suspend fun saveObservable(observable: DittoObservable): Long
    suspend fun updateObservable(observable: DittoObservable)
    suspend fun removeObservable(id: Long)
    suspend fun removeAllObservables(databaseId: String)
}
