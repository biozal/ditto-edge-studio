package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.edgestudio.models.DittoDatabaseConfig

interface IDittoManager {
    var dittoLocal: Ditto?
    var dittoSelectedApp: Ditto?
    var selectedDatabaseConfig: DittoDatabaseConfig?

    fun closeSelectedDatabase()
    suspend fun initializeDittoAsync(databaseConfig: DittoDatabaseConfig)
    suspend fun initializeDittoSelectedApp(databaseConfig: DittoDatabaseConfig): Boolean
    fun selectedAppStartSync()
    fun selectedAppStopSync()
}
