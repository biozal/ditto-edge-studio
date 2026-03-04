package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import kotlinx.coroutines.flow.Flow

interface FavoritesRepository {
    fun observeFavorites(databaseId: String): Flow<List<DittoQueryHistory>>
    suspend fun loadFavorites(databaseId: String): List<DittoQueryHistory>
    suspend fun saveFavorite(databaseId: String, query: String): Long?
    suspend fun removeFavorite(id: Long)
    suspend fun removeAllFavorites(databaseId: String)
}
