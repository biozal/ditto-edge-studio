package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAuthenticationProvider
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoLog
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import com.ditto.kotlin.DittoQueryResult
import com.ditto.kotlin.error.DittoError
import com.ditto.kotlin.serialization.DittoCborSerializable
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
    //local database
    override var dittoLocalDatabase: Ditto? = null
    private var createLocalDatabaseJob: Job? = null
    private var closeLocalDatabaseJob: Job? = null

    //selected database via end user
    override var dittoSelectedDatabase: Ditto? = null
    private var createSelectedDatabaseJob: Job? = null
    private var closeSelectedDatabaseJob: Job? = null
    override var selectedDatabaseConfig: ESDatabaseConfig? = null
    private var appDataPath = getAppDataDirectory() + "DittoEdgeStudio"

    override fun closeLocalDatabase() {
        closeLocalDatabaseJob = scope.launch(Dispatchers.IO) {
            getDittoLocalDatabase()?.stopSync()
            getDittoLocalDatabase()?.close()
            dittoLocalDatabase = null
        }
    }

    override suspend fun closeLocalObservers() {
        getDittoLocalDatabase()?.store?.observers?.forEach { observer ->
            observer.close()
        }
    }

    override fun closeSelectedDatabase() {
        closeSelectedDatabaseJob = scope.launch(Dispatchers.IO) {
            getDittoSelectedDatabase()?.stopSync()
            getDittoSelectedDatabase()?.close()
            dittoSelectedDatabase = null
        }
    }

    override suspend fun localDatabaseExecuteDql(
        query: String,
        parameters: DittoCborSerializable.Dictionary?
    ): DittoQueryResult? {
        if (getDittoLocalDatabase() == null) {
            throw IllegalStateException("Local database not initialized")
        }
        try {
            return if (parameters != null) {
                getDittoLocalDatabase()?.store?.execute(query, parameters)
            } else {
                getDittoLocalDatabase()?.store?.execute(query)
            }
        } catch (e: DittoError) {
            DittoLog.e("localDatabaseExecuteDql", "Error executing DQL query: ${e.message}")
            return null
        }
    }

    suspend fun getDittoLocalDatabase(): Ditto? {
        waitForLocalDatabaseWorkInProgress()
        return dittoLocalDatabase
    }

    suspend fun getDittoSelectedDatabase(): Ditto? {
        waitForSelectedDatabaseWorkInProgress()
        return dittoSelectedDatabase
    }

    override suspend fun initializeDittoStore() {
        if (getDittoLocalDatabase() != null) {
            DittoLog.e(TAG, "Local database already initialized")
            return
        }

        // SDKS-1294: Don't create Ditto in a scope using Dispatchers.IO
        createLocalDatabaseJob = scope.launch(Dispatchers.Default) {
            dittoLocalDatabase = try {
                //enable logging
                //TODO update this later based on user config
                DittoLogger.isEnabled = true
                DittoLogger.minimumLogLevel = DittoLogLevel.Debug

                //get the directory to store the local database cache
                val path = appDataPath.toPath()
                if (!FileSystem.SYSTEM.exists(path)) {
                    FileSystem.SYSTEM.createDirectories(path)
                }

                val dittoConfig = DittoConfig(
                    databaseId = DittoSecretsConfiguration.DITTO_APP_ID,
                    connect = DittoConfig.Connect.Server(url = DittoSecretsConfiguration.DITTO_AUTH_URL),
                    persistenceDirectory = appDataPath,
                )
                createDitto(config = dittoConfig)
                    .apply{
                        auth?.setExpirationHandler { ditto, secondsRemaining ->
                            // Authenticate when a token is expiring
                            val clientInfo = ditto.auth?.login(
                                token = DittoSecretsConfiguration.DITTO_PLAYGROUND_TOKEN,
                                provider = DittoAuthenticationProvider.development(),
                            )
                        }
                    }.apply {
                        updateTransportConfig { config ->
                            config.peerToPeer.lan.enabled = true
                            config.peerToPeer.bluetoothLe.enabled = true
                            config.peerToPeer.wifiAware.enabled = true
                        }
                    }
            } catch(e: Throwable){
                DittoLog.e(TAG, "Failed to create Ditto instance: $e")
                e.printStackTrace()
                null
            }
        }
    }

    override suspend fun initializeDittoSelectedDatabase(databaseConfig: ESDatabaseConfig) {
        // Close any existing database connection
        closeSelectedDatabase()
        closeLocalDatabaseJob?.join()

        // SDKS-1294: Don't create Ditto in a scope using Dispatchers.IO
        createSelectedDatabaseJob = scope.launch(Dispatchers.Default) {
            dittoSelectedDatabase = try {
                val dittoConfig = DittoConfig(
                    databaseId = databaseConfig.databaseId,
                    connect = DittoConfig.Connect.Server(url = databaseConfig.authUrl),
                    persistenceDirectory = appDataPath,
                )
                createDitto(config = dittoConfig)
                    .apply{
                        auth?.setExpirationHandler { ditto, secondsRemaining ->
                            // Authenticate when a token is expiring
                            val clientInfo = ditto.auth?.login(
                                token = databaseConfig.authToken,
                                provider = DittoAuthenticationProvider.development(),
                            )
                        }
                    }.apply {
                        updateTransportConfig { config ->
                            config.peerToPeer.lan.enabled = true
                            config.peerToPeer.bluetoothLe.enabled = true
                            config.peerToPeer.wifiAware.enabled = true
                        }
                    }
            } catch(e: Throwable){
                DittoLog.e(TAG, "Failed to create selected Ditto Database instance: $e")
                e.printStackTrace()
                null
            }
        }
    }

    override suspend fun isDittoLocalDatabaseInitialized() = getDittoLocalDatabase() != null

    override suspend fun isDittoSelectedDatabaseInitialized() = getDittoLocalDatabase() != null

    override suspend fun isDittoSelectedDatabaseSyncing() = getDittoSelectedDatabase()?.isSyncActive == true

    override suspend fun registerObserverLocalDatabase(
        query: String,
        arguments: DittoCborSerializable.Dictionary?
    ): Flow<DittoQueryResult> = requireNotNull(getDittoLocalDatabase()).store.observe(
        query = query,
        arguments = arguments
    )

    override suspend fun selectedDatabaseExecuteDql(
        query: String,
        parameters: DittoCborSerializable.Dictionary?
    ): DittoQueryResult? {
        if (getDittoLocalDatabase() == null) {
            throw IllegalStateException("Local database not initialized")
        }
         try {
            return if (parameters != null) {
                getDittoSelectedDatabase()?.store?.execute(query, parameters)
            } else {
                getDittoSelectedDatabase()?.store?.execute(query)
            }
        } catch (e: DittoError) {
            DittoLog.e("selectedDatabaseExecuteDql", "Error executing DQL query: ${e.message}")
            return null
        }
    }

    override suspend fun selectedDatabaseStartSync() {
        getDittoSelectedDatabase()?.startSync()
    }

    override suspend fun selectedDatabaseStopSync() {
        getDittoSelectedDatabase()?.stopSync()
    }

    private suspend fun waitForLocalDatabaseWorkInProgress() {
        createLocalDatabaseJob?.join()
        closeLocalDatabaseJob?.join()
    }

    private suspend fun waitForSelectedDatabaseWorkInProgress() {
        createSelectedDatabaseJob?.join()
        closeSelectedDatabaseJob?.join()
    }
}

/**
 * Defines how to create a Ditto Config in Multiplatform, and on each platform pass the required dependencies -
 * on Android we require Context.
 */
internal expect fun createDitto(config: DittoConfig): Ditto