package com.costoda.dittoedgestudio.data.ditto

import android.util.Log
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAuthenticationProvider
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DittoManager(private val coroutineScope: CoroutineScope) {

    private var ditto: Ditto? = null

    companion object {
        private const val TAG = "DittoManager"
    }

    suspend fun hydrate(database: DittoDatabase): Ditto {
        require(database.databaseId.isNotBlank()) { "databaseId must not be blank" }
        if (database.mode == AuthMode.SERVER) {
            require(database.token.isNotBlank()) { "token must not be blank for SERVER mode" }
            require(database.authUrl.isNotBlank()) { "authUrl must not be blank for SERVER mode" }
        }

        closeCurrentInstance()

        val config = buildConfig(database)
        val newDitto = withContext(Dispatchers.IO) {
            DittoFactory.create(config, coroutineScope)
        }

        // Set device name for peer identification
        newDitto.deviceName = "Edge Studio"

        // Register auth handler BEFORE starting sync
        setupAuth(newDitto, database)

        // Apply transport config BEFORE starting sync
        applyTransportConfig(newDitto, database)

        withContext(Dispatchers.IO) { newDitto.sync.start() }

        ditto = newDitto
        return newDitto
    }

    private fun setupAuth(ditto: Ditto, database: DittoDatabase) {
        when (database.mode) {
            AuthMode.SERVER -> {
                ditto.auth?.expirationHandler = { d, secondsRemaining ->
                    Log.i(TAG, "[Auth] Handler called, secondsRemaining=$secondsRemaining")
                    d.auth?.login(
                        token = database.token,
                        provider = DittoAuthenticationProvider.development(),
                    )
                }
            }
            AuthMode.SMALL_PEERS_ONLY -> {
                if (database.token.isNotEmpty()) {
                    runCatching { ditto.setOfflineOnlyLicenseToken(database.token) }
                        .onFailure { e ->
                            Log.e(TAG, "[Auth] Failed to set offline license token: ${e.message}")
                        }
                }
            }
        }
    }

    suspend fun close() = closeCurrentInstance()

    fun currentInstance(): Ditto? = ditto

    fun applyTransportConfig(ditto: Ditto, database: DittoDatabase) {
        ditto.updateTransportConfig { builder ->
            builder.peerToPeer {
                bluetoothLe { enabled = database.isBluetoothLeEnabled }
                lan { enabled = database.isLanEnabled }
                wifiAware { enabled = database.isAwdlEnabled }
            }
            if (database.isCloudSyncEnabled && database.websocketUrl.isNotBlank()) {
                builder.connect {
                    websocketUrls = mutableSetOf(database.websocketUrl)
                }
            }
        }
    }

    private suspend fun closeCurrentInstance() {
        val current = ditto ?: return
        withContext(Dispatchers.IO) {
            runCatching { if (current.sync.isActive) current.sync.stop() }
        }
        ditto = null
    }

    private fun buildConfig(database: DittoDatabase): DittoConfig = when (database.mode) {
        AuthMode.SERVER -> DittoConfig(
            databaseId = database.databaseId,
            connect = DittoConfig.Connect.Server(url = database.authUrl),
        )
        AuthMode.SMALL_PEERS_ONLY -> DittoConfig(
            databaseId = database.databaseId,
            connect = DittoConfig.Connect.SmallPeersOnly(),
        )
    }
}
