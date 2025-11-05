package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import com.edgestudio.config.DittoSecretsConfiguration
import com.edgestudio.getAppDataDirectory
import com.edgestudio.models.ESDatabaseConfig

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

import okio.FileSystem
import okio.Path.Companion.toPath
import okio.SYSTEM

private const val TAG = "DittoManager"

class DittoManager
    : IDittoManager {
    private val scope = CoroutineScope(SupervisorJob())
    override var dittoLocalDatabase: Ditto? = null
    override var dittoSelectedDatabase: Ditto? = null
    override var selectedDatabaseConfig: ESDatabaseConfig? = null
    private var createJob: Job? = null
    private var closeJob: Job? = null
    var isDittoLocalDatabaseInitialized = false

    override fun closeSelectedDatabase() {
        dittoSelectedDatabase?.let {
           it.stopSync()
           it.close()
        }
        dittoSelectedDatabase = null
    }

    override suspend fun initializeDittoStoreAsync() {
        if (isDittoLocalDatabaseInitialized) return

        // SDKS-1294: Don't create Ditto in a scope using Dispatchers.IO
        createJob = scope.launch(Dispatchers.Default) {
            //enable logging
            //TODO update this later based on user config
            DittoLogger.isEnabled = true
            DittoLogger.minimumLogLevel = DittoLogLevel.Debug

            //get the directory to store the local database cache
            val appDataPath = getAppDataDirectory() + "DittoEdgeStudio"
            val path = appDataPath.toPath()
            if (!FileSystem.SYSTEM.exists(path)) {
                FileSystem.SYSTEM.createDirectories(path)
            }
            /*
            val dittoConfig = DittoConfig(
                databaseId = DittoSecretsConfiguration.DITTO_APP_ID,
                connect = DittoConfig.Connect.Server(url = DittoSecretsConfiguration.DITTO_AUTH_URL),
                persistenceDirectory = path)
             */

            //initialize the local database cache
            // Configuration values available from DittoSecretsConfiguration:
            // - DittoSecretsConfiguration.DITTO_APP_ID
            // - DittoSecretsConfiguration.DITTO_PLAYGROUND_TOKEN
            // - DittoSecretsConfiguration.DITTO_AUTH_URL
            // - DittoSecretsConfiguration.DITTO_WEBSOCKET_URL

            // Example initialization (uncomment when ready):
            // val identity = DittoIdentity.OnlinePlayground(
            //     appID = DittoSecretsConfiguration.DITTO_APP_ID,
            //     token = DittoSecretsConfiguration.DITTO_PLAYGROUND_TOKEN
            // )
            // dittoLocalDatabase = Ditto(identity, appDataPath)
            // isDittoLocalDatabaseInitialized = true
        }
    }

    override suspend fun initializeDittoSelectedDatabase(databaseConfig: ESDatabaseConfig): Boolean {
        // Close any existing database connection
        closeSelectedDatabase()

        // Use .env configuration or the provided databaseConfig
        // You can choose to use DittoSecretsConfiguration.DITTO_APP_ID or databaseConfig.databaseId
        // depending on your use case

        // Example implementation:
        // val identity = DittoIdentity.OnlinePlayground(
        //     appID = databaseConfig.databaseId,
        //     token = databaseConfig.authToken
        // )
        // val appDataPath = getAppDataDirectory() + "DittoEdgeStudio/${databaseConfig.name}"
        // dittoSelectedDatabase = Ditto(identity, appDataPath)
        // dittoSelectedDatabase?.startSync()

        TODO("Not yet implemented")
    }

    override fun selectedAppStartSync() {
        dittoSelectedDatabase?.startSync()
    }

    override fun selectedAppStopSync() {
        dittoSelectedDatabase?.stopSync()
    }
}