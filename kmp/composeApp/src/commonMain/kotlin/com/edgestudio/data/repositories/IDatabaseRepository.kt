package com.edgestudio.data.repositories

import com.edgestudio.models.ESDatabaseConfig
import kotlinx.coroutines.flow.StateFlow

interface IDatabaseRepository {
    val tasksStateFlow: StateFlow<List<ESDatabaseConfig>>

    //CRUD
    suspend fun addDatabaseConfig(databaseConfig: ESDatabaseConfig)
    suspend fun deleteDatabaseConfig(databaseConfig: ESDatabaseConfig)
    suspend fun getDatabaseConfig(id: String): ESDatabaseConfig?
    suspend fun updateDatabaseConfig(databaseConfig: ESDatabaseConfig)

    suspend fun closeObserver()
    suspend fun registerObserver()
}