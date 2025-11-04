package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.edgestudio.models.ESDatabaseConfig

interface IDittoManager {
    var dittoLocal: Ditto?
    var dittoSelectedApp: Ditto?
    var selectedDatabaseConfig: ESDatabaseConfig?

    fun closeSelectedDatabase()
    suspend fun initializeDittoAsync(databaseConfig: ESDatabaseConfig)
    suspend fun initializeDittoSelectedApp(databaseConfig: ESDatabaseConfig): Boolean
    fun selectedAppStartSync()
    fun selectedAppStopSync()
}
