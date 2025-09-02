package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.edgestudio.getAppDataDirectory
import com.edgestudio.models.DittoDatabaseConfig

class DittoManager
    : IDittoManager {
    override var dittoLocal: Ditto? = null
    override var dittoSelectedApp: Ditto? = null
    override var selectedDatabaseConfig: DittoDatabaseConfig? = null

    var isDittoLocalInitialized = false

    override fun closeSelectedDatabase() {
        dittoSelectedApp?.let {
           it.stopSync()
           it.close()
        }
        dittoSelectedApp = null
        var appDataPath = getAppDataDirectory() + "DittoEdgeStudio"
    }

    override suspend fun initializeDittoAsync(databaseConfig: DittoDatabaseConfig) {
        if (isDittoLocalInitialized) return
        selectedDatabaseConfig = databaseConfig

    }

    override suspend fun initializeDittoSelectedApp(databaseConfig: DittoDatabaseConfig): Boolean {
        TODO("Not yet implemented")
    }

    override fun selectedAppStartSync() {
        dittoSelectedApp?.startSync()
    }

    override fun selectedAppStopSync() {
        dittoSelectedApp?.stopSync()
    }
}