package com.costoda.dittoedgestudio.data.repository

import android.os.Build
import android.util.Log
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.PeerConnectionInfo
import com.costoda.dittoedgestudio.domain.model.PeerOS
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConnectionType
import com.ditto.kotlin.DittoPeer
import com.ditto.kotlin.DittoPeerOs
import com.ditto.kotlin.DittoPresenceGraph
import com.ditto.kotlin.serialization.DittoCborSerializable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class SystemRepositoryImpl(
    private val coroutineScope: CoroutineScope,
) : SystemRepository {

    companion object {
        private const val TAG = "SystemRepositoryImpl"
        private const val FIELD_IS_DITTO_SERVER = "is_ditto_server"
        private const val FIELD_DOCUMENTS = "documents"
        private const val FIELD_SYNC_SESSION_STATUS = "sync_session_status"
        private const val FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID = "synced_up_to_local_commit_id"
        private const val FIELD_LAST_UPDATE_RECEIVED_TIME = "last_update_received_time"
        private const val SYNC_STATUS_NOT_CONNECTED = "Not Connected"
    }

    private val _peers = MutableStateFlow<List<SyncStatusInfo>>(emptyList())
    private val _localPeer = MutableStateFlow<LocalPeerInfo?>(null)
    private val _connectionsByTransport = MutableStateFlow(ConnectionsByTransport.Empty)

    override val peers: StateFlow<List<SyncStatusInfo>> = _peers.asStateFlow()
    override val localPeer: StateFlow<LocalPeerInfo?> = _localPeer.asStateFlow()
    override val connectionsByTransport: StateFlow<ConnectionsByTransport> =
        _connectionsByTransport.asStateFlow()

    // Job collecting the presence Flow — cancelled on stopObserving()
    private var observeJob: Job? = null

    override fun startObserving(ditto: Ditto) {
        observeJob?.cancel()
        observeJob = coroutineScope.launch {
            ditto.presence.observe().collect { graph ->
                updatePresence(graph, ditto)
            }
        }
    }

    override fun stopObserving() {
        observeJob?.cancel()
        observeJob = null
        _peers.value = emptyList()
        _localPeer.value = null
        _connectionsByTransport.value = ConnectionsByTransport.Empty
    }

    private suspend fun updatePresence(graph: DittoPresenceGraph, ditto: Ditto) {
        // 1. Query sync metrics — graceful degradation on failure
        val syncMetrics = mutableMapOf<String, DittoCborSerializable.Dictionary>()
        runCatching {
            val result = ditto.store.execute("SELECT * FROM system:data_sync_info")
            for (item in result.items) {
                val dict = item.value
                val peerId = dict["_id"].stringOrNull ?: continue
                syncMetrics[peerId] = dict
            }
        }.onFailure { e ->
            Log.w(TAG, "system:data_sync_info query failed — commit IDs unavailable", e)
        }

        // 2. Deduplicate remote peers by peerKey
        val deduped = graph.remotePeers
            .groupBy { it.peerKey }
            .mapValues { (_, peers) ->
                peers.maxByOrNull { it.dittoSdkVersion != null } ?: peers.first()
            }
            .values

        val processedIds = mutableSetOf<String>()

        val localPeerKey = graph.localPeer.peerKey

        // 3. Map presence peers with merged sync metrics
        val remotePeers = deduped.map { peer ->
            processedIds.add(peer.peerKey)
            peer.toSyncStatusInfo(syncMetrics[peer.peerKey], localPeerKey)
        }.toMutableList()

        // 4. Add Cloud Server peers from DQL not in presence graph
        for ((peerId, metrics) in syncMetrics) {
            if (peerId in processedIds) continue
            val isDittoServer = metrics[FIELD_IS_DITTO_SERVER].booleanOrNull ?: false
            if (!isDittoServer) continue
            val docs = metrics[FIELD_DOCUMENTS].dictionaryOrNull
            val status = docs?.get(FIELD_SYNC_SESSION_STATUS)?.stringOrNull
            if (status == SYNC_STATUS_NOT_CONNECTED) continue
            remotePeers.add(
                SyncStatusInfo(
                    peerId = peerId,
                    isDittoServer = true,
                    deviceName = null,
                    osInfo = PeerOS.Unknown,
                    dittoSdkVersion = null,
                    syncedUpToLocalCommitId = docs?.get(FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID)?.longOrNull,
                    lastUpdateReceivedTime = docs?.get(FIELD_LAST_UPDATE_RECEIVED_TIME)?.longOrNull?.toDouble(),
                )
            )
        }

        // 5. Update state
        _peers.value = remotePeers
        _connectionsByTransport.value = buildConnectionCounts(deduped)
        _localPeer.value = LocalPeerInfo(
            peerId = graph.localPeer.peerKey,
            deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            sdkLanguage = "Kotlin",
            sdkPlatform = "Android",
            sdkVersion = graph.localPeer.dittoSdkVersion ?: "Unknown",
        )
    }

    private fun DittoPeer.toSyncStatusInfo(
        metrics: DittoCborSerializable.Dictionary? = null,
        localPeerKey: String,
    ): SyncStatusInfo {
        val docs = metrics?.get(FIELD_DOCUMENTS)?.dictionaryOrNull
        return SyncStatusInfo(
            peerId = peerKey,
            isDittoServer = metrics?.get(FIELD_IS_DITTO_SERVER)?.booleanOrNull ?: false,
            deviceName = deviceName?.takeIf { it.isNotBlank() },
            osInfo = os?.toPeerOS() ?: PeerOS.Unknown,
            dittoSdkVersion = dittoSdkVersion?.takeIf { it.isNotBlank() },
            connections = connections
                .filter { conn -> conn.peer1 == localPeerKey || conn.peer2 == localPeerKey }
                .distinctBy { conn -> conn.connectionType }
                .map { conn ->
                    PeerConnectionInfo(
                        id = conn.id,
                        type = conn.connectionType.toConnectionType(),
                    )
                },
            peerMetadata = peerMetadata
                ?.takeIf { !it.isNull }
                ?.toString(),
            identityServiceMetadata = identityServiceMetadata
                ?.takeIf { !it.isNull }
                ?.toString(),
            syncedUpToLocalCommitId = docs?.get(FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID)?.longOrNull,
            lastUpdateReceivedTime = docs?.get(FIELD_LAST_UPDATE_RECEIVED_TIME)?.longOrNull?.toDouble(),
        )
    }

    private fun DittoPeerOs.toPeerOS(): PeerOS = when (this) {
        DittoPeerOs.Ios, DittoPeerOs.Tvos -> PeerOS.iOS
        DittoPeerOs.Android -> PeerOS.Android
        DittoPeerOs.MacOS -> PeerOS.MacOS
        DittoPeerOs.Linux -> PeerOS.Linux
        DittoPeerOs.Windows -> PeerOS.Windows
        DittoPeerOs.Generic -> PeerOS.Unknown
    }

    private fun DittoConnectionType.toConnectionType(): ConnectionType = when (this) {
        DittoConnectionType.Bluetooth -> ConnectionType.Bluetooth
        DittoConnectionType.AccessPoint -> ConnectionType.LAN
        DittoConnectionType.P2PWiFi -> ConnectionType.P2PWiFi
        DittoConnectionType.WebSocket -> ConnectionType.WebSocket
    }

    private fun buildConnectionCounts(peers: Collection<DittoPeer>): ConnectionsByTransport {
        var bluetooth = 0
        var lan = 0
        var p2pWifi = 0
        var webSocket = 0

        peers.forEach { peer ->
            peer.connections
                .distinctBy { it.connectionType }
                .forEach { conn ->
                    when (conn.connectionType.toConnectionType()) {
                        ConnectionType.Bluetooth -> bluetooth++
                        ConnectionType.LAN -> lan++
                        ConnectionType.P2PWiFi -> p2pWifi++
                        ConnectionType.WebSocket -> webSocket++
                        ConnectionType.Unknown -> { /* skip */ }
                    }
                }
        }

        return ConnectionsByTransport(
            bluetooth = bluetooth,
            lan = lan,
            p2pWifi = p2pWifi,
            webSocket = webSocket,
        )
    }
}
