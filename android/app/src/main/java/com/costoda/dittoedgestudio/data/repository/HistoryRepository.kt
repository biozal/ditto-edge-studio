package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import kotlinx.coroutines.flow.Flow

interface HistoryRepository {
    fun observeHistory(databaseId: String): Flow<List<DittoQueryHistory>>
    suspend fun loadHistory(databaseId: String): List<DittoQueryHistory>
    suspend fun addToHistory(databaseId: String, query: String): Long
    suspend fun removeHistoryItem(id: Long)
    suspend fun clearHistory(databaseId: String)
}
