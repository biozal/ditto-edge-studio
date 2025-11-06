package com.edgestudio.data.repositories

import com.ditto.kotlin.DittoQueryResultItem
import com.ditto.kotlin.serialization.DittoCborSerializable
import com.edgestudio.data.IDittoManager
import com.edgestudio.models.ESDatabaseConfig
import com.edgestudio.models.toDittoDictionary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DatabaseRepository(private val dittoManager: IDittoManager)
    : IDatabaseRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val esDatabaseConfigMutableStateFlow = MutableStateFlow(emptyList<ESDatabaseConfig>())
    override val tasksStateFlow: StateFlow<List<ESDatabaseConfig>> = esDatabaseConfigMutableStateFlow.asStateFlow()
        .onStart{
            registerObserver()
        }
        .stateIn(
            scope = scope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )


    override suspend fun addDatabaseConfig(databaseConfig: ESDatabaseConfig){
        dittoManager.localDatabaseExecuteDql(query = "INSERT INTO dittoDatabaseConfig INITIAL DOCUMENTS(:newDatabaseConfig)",
            parameters = DittoCborSerializable.Dictionary(mapOf(
                DittoCborSerializable.Utf8String("newDatabaseConfig") to databaseConfig.toDittoDictionary()
            )))
    }

    override suspend fun closeObserver() {
        dittoManager.closeLocalObservers()
    }

    override suspend fun deleteDatabaseConfig(databaseConfig: ESDatabaseConfig){
        dittoManager.localDatabaseExecuteDql(query = "DELETE FROM dittoDatabaseConfig WHERE _id = :id",
            parameters = DittoCborSerializable.Dictionary(mapOf(
                DittoCborSerializable.Utf8String("id") to DittoCborSerializable.Utf8String(databaseConfig.id)
            )))
    }

    override suspend fun getDatabaseConfig(id: String):ESDatabaseConfig? {
        return dittoManager.localDatabaseExecuteDql(query="SELECT * FROM dittoDatabaseConfig WHERE _id = :id",
            parameters = DittoCborSerializable.Dictionary(
                mapOf(DittoCborSerializable.Utf8String("id") to DittoCborSerializable.Utf8String(id))
        ))?.items?.firstOrNull()?.toESDatabaseConfig()
    }

    override suspend fun registerObserver() {
        val observer = dittoManager.registerObserverLocalDatabase("SELECT * FROM dittoDatabaseConfig")
        scope.launch {
            observer
                .map { result -> result.items.map {
                   item -> item.toESDatabaseConfig() } }
                .collect { items ->
                    esDatabaseConfigMutableStateFlow.value = items
                }
        }
    }

    private fun DittoQueryResultItem.toESDatabaseConfig(): ESDatabaseConfig =
        ESDatabaseConfig(
            id = this.value["_id"].string,
            name = this.value["name"].string,
            databaseId = this.value["databaseId"].string,
            authToken = this.value["authToken"].string,
            authUrl = this.value["authURL"].string,
            httpApiUrl = this.value["httpApiUrl"].string,
            httpApiKey = this.value["httpApiKey"].string,
            mode = this.value["mode"].string,
            allowUntrustedCerts = this.value["allowUntrustedCerts"].boolean,
        )

    override suspend fun updateDatabaseConfig(databaseConfig: ESDatabaseConfig) {
       dittoManager.localDatabaseExecuteDql(
           query =
               """UPDATE dittoDatabaseConfig 
                   SET name = :name, 
                   databaseId = :databaseId, 
                   authToken = :authToken, 
                   authUrl = :authUrl, 
                   websocketUrl = :websocketUrl, 
                   httpApiUrl = :httpApiUrl, 
                   httpApiKey = :httpApiKey, 
                   mode = :mode, 
                   allowUntrustedCerts = :allowUntrustedCerts 
                   WHERE _id = :_id"""
           , parameters = databaseConfig.toDittoDictionary())
    }


}