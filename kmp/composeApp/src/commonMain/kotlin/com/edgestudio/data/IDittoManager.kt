package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.edgestudio.models.ESDatabaseConfig

interface IDittoManager {
    var dittoLocalDatabase: Ditto?
    var dittoSelectedDatabase: Ditto?
    var selectedDatabaseConfig: ESDatabaseConfig?

    fun closeSelectedDatabase()
    suspend fun initializeDittoStoreAsync()
    suspend fun initializeDittoSelectedDatabase(databaseConfig: ESDatabaseConfig): Boolean
    fun selectedAppStartSync()
    fun selectedAppStopSync()
}
