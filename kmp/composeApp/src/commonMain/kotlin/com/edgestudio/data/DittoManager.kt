package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import com.edgestudio.getAppDataDirectory
import com.edgestudio.models.DittoDatabaseConfig
import okio.FileSystem
import okio.Path.Companion.toPath

class DittoManager
    : IDittoManager {
    override var dittoLocalDatabase: Ditto? = null
    override var dittoSelectedDatabase: Ditto? = null
    override var selectedDatabaseConfig: DittoDatabaseConfig? = null

    var isDittoLocalDatabaseInitialized = false

    override fun closeSelectedDatabase() {
        dittoSelectedDatabase?.let {
           it.stopSync()
           it.close()
        }
        dittoSelectedDatabase = null
    }

    override suspend fun initializeDittoStoreAsync(databaseConfig: DittoDatabaseConfig) {
        if (isDittoLocalDatabaseInitialized) return

        //enable logging
        //TODO update this later based on user config
        DittoLogger.isEnabled = true
        DittoLogger.minimumLogLevel = DittoLogLevel.Debug

        selectedDatabaseConfig = databaseConfig

        //get the directory to store the local database cache
        val appDataPath = getAppDataDirectory() + "DittoEdgeStudio"
        val path = appDataPath.toPath()
        if (!FileSystem.SYSTEM.exists(path)) {
            FileSystem.SYSTEM.createDirectories(path)
        }

        //initialize the local database cache
    }

    override suspend fun initializeDittoSelectedDatabase(databaseConfig: DittoDatabaseConfig): Boolean {
        TODO("Not yet implemented")
    }

    override fun selectedAppStartSync() {
        dittoSelectedDatabase?.startSync()
    }

    override fun selectedAppStopSync() {
        dittoSelectedDatabase?.stopSync()
    }
}