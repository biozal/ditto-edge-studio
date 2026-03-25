package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.flow.Flow

interface DatabaseRepository {
    fun observeAll(): Flow<List<DittoDatabase>>
    suspend fun getAll(): List<DittoDatabase>
    suspend fun getById(id: Long): DittoDatabase?
    suspend fun getByDatabaseId(databaseId: String): DittoDatabase?
    suspend fun save(database: DittoDatabase): Long
    suspend fun delete(id: Long)
    suspend fun deleteByDatabaseId(databaseId: String)
}
