package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.edgestudio.models.DittoDatabaseConfig

interface IDittoManager {
    var dittoLocalDatabase: Ditto?
    var dittoSelectedDatabase: Ditto?
    var selectedDatabaseConfig: DittoDatabaseConfig?

    fun closeSelectedDatabase()
    suspend fun initializeDittoStoreAsync(databaseConfig: DittoDatabaseConfig)
    suspend fun initializeDittoSelectedDatabase(databaseConfig: DittoDatabaseConfig): Boolean
    fun selectedAppStartSync()
    fun selectedAppStopSync()
}
