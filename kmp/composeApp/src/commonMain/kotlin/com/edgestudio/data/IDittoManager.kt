package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoQueryResult
import com.ditto.kotlin.serialization.DittoCborSerializable
import com.edgestudio.models.ESDatabaseConfig
import kotlinx.coroutines.flow.Flow

interface IDittoManager {
    var dittoLocalDatabase: Ditto?
    var dittoSelectedDatabase: Ditto?
    var selectedDatabaseConfig: ESDatabaseConfig?

    fun closeSelectedDatabase()
    fun closeLocalDatabase()

    suspend fun closeLocalObservers()

    suspend fun initializeDittoStore()
    suspend fun initializeDittoSelectedDatabase(databaseConfig: ESDatabaseConfig)
    suspend fun isDittoLocalDatabaseInitialized():Boolean
    suspend fun isDittoSelectedDatabaseInitialized():Boolean
    suspend fun isDittoSelectedDatabaseSyncing():Boolean
    suspend fun localDatabaseExecuteDql(query: String, parameters: DittoCborSerializable.Dictionary?): DittoQueryResult?

    suspend fun registerObserverLocalDatabase(
        query: String,
        arguments: DittoCborSerializable.Dictionary? = null
    ): Flow<DittoQueryResult>

    suspend fun selectedDatabaseExecuteDql(query: String, parameters: DittoCborSerializable.Dictionary?): DittoQueryResult?
    suspend fun selectedDatabaseStartSync()
    suspend fun selectedDatabaseStopSync()
}
