package com.costoda.dittoedgestudio.data.repository

import android.os.Build
import android.util.Log
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.MeshEdge
import com.costoda.dittoedgestudio.domain.model.MeshPeer
import com.costoda.dittoedgestudio.domain.model.MeshTopology
import com.costoda.dittoedgestudio.domain.model.PeerConnectionInfo
import com.costoda.dittoedgestudio.domain.model.PeerOS
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConnectionType
import com.ditto.kotlin.DittoPeer
import com.ditto.kotlin.DittoPeerOs
import com.ditto.kotlin.DittoPresenceGraph
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

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
    private val _meshTopology = MutableStateFlow(MeshTopology.Empty)

    override val peers: StateFlow<List<SyncStatusInfo>> = _peers.asStateFlow()
    override val localPeer: StateFlow<LocalPeerInfo?> = _localPeer.asStateFlow()
    override val connectionsByTransport: StateFlow<ConnectionsByTransport> =
        _connectionsByTransport.asStateFlow()
    override val meshTopology: StateFlow<MeshTopology> = _meshTopology.asStateFlow()

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
        _meshTopology.value = MeshTopology.Empty
    }

    private suspend fun updatePresence(graph: DittoPresenceGraph, ditto: Ditto) {
        // 1. Query sync metrics — graceful degradation on failure
        val syncMetrics = mutableMapOf<String, JSONObject>()
        runCatching {
            ditto.store.execute("SELECT * FROM system:data_sync_info") { result ->
                for (item in result.items) {
                    val json = runCatching { JSONObject(item.jsonString()) }.getOrNull() ?: continue
                    val peerId = json.optString("_id").takeIf { it.isNotBlank() } ?: continue
                    syncMetrics[peerId] = json
                }
            }
        }.onFailure { e ->
            Log.w(TAG, "system:data_sync_info query failed — commit IDs unavailable", e)
        }

        val localPeerKey = graph.localPeer.peerKey

        // 2. Deduplicate remote peers by peerKey, then filter to directly connected peers only.
        // presenceGraph.remotePeers returns the full mesh topology (all peers in the network,
        // including multihop peers). A peer is "directly connected" if the local device's peer
        // key is an endpoint of at least one of its connections.
        val deduped = graph.remotePeers
            .groupBy { it.peerKey }
            .mapValues { (_, peers) ->
                peers.maxByOrNull { it.dittoSdkVersion != null } ?: peers.first()
            }
            .values
            .filter { peer ->
                // Only directly connected peers — local peer must be an endpoint of at least one connection
                peer.connections.any { conn -> conn.peer1 == localPeerKey || conn.peer2 == localPeerKey }
            }

        val processedIds = mutableSetOf<String>()

        // 3. Map presence peers with merged sync metrics
        val remotePeers = deduped.map { peer ->
            processedIds.add(peer.peerKey)
            peer.toSyncStatusInfo(syncMetrics[peer.peerKey], localPeerKey)
        }.toMutableList()

        // 4. Add Cloud Server peers from DQL not in presence graph
        for ((peerId, metrics) in syncMetrics) {
            if (peerId in processedIds) continue
            if (!metrics.optBoolean(FIELD_IS_DITTO_SERVER, false)) continue
            val docs = metrics.optJSONObject(FIELD_DOCUMENTS)
            val status = docs?.optString(FIELD_SYNC_SESSION_STATUS)
            if (status == SYNC_STATUS_NOT_CONNECTED) continue
            remotePeers.add(
                SyncStatusInfo(
                    peerId = peerId,
                    isDittoServer = true,
                    deviceName = null,
                    osInfo = PeerOS.Unknown,
                    dittoSdkVersion = null,
                    syncedUpToLocalCommitId = docs?.optLongOrNull(FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID),
                    lastUpdateReceivedTime = docs?.optLongOrNull(FIELD_LAST_UPDATE_RECEIVED_TIME)?.toDouble(),
                )
            )
        }

        // 5a. Build the unfiltered mesh topology — every peer the SDK knows about plus
        //     every connection between them. The Presence Viewer needs this when the
        //     user toggles "Direct Connected" off; everything else keeps using the
        //     filtered [_peers] list above per the presence-graph pitfall rule.
        val allPeersDeduped = graph.remotePeers
            .groupBy { it.peerKey }
            .mapValues { (_, peers) ->
                peers.maxByOrNull { it.dittoSdkVersion != null } ?: peers.first()
            }
            .values
        val meshPeerList = allPeersDeduped.map { peer ->
            MeshPeer(
                peerKey = peer.peerKey,
                deviceName = peer.deviceName?.takeIf { it.isNotBlank() },
            )
        }
        val seenEdgeKeys = mutableSetOf<String>()
        val meshEdgeList = buildList {
            for (peer in allPeersDeduped) {
                for (conn in peer.connections) {
                    val p1 = conn.peer1
                    val p2 = conn.peer2
                    if (p1.isBlank() || p2.isBlank()) continue
                    val sortedPair = listOf(p1, p2).sorted()
                    val key = "${sortedPair[0]}_${sortedPair[1]}_${conn.connectionType}"
                    if (!seenEdgeKeys.add(key)) continue
                    add(MeshEdge(p1, p2, conn.connectionType.toConnectionType()))
                }
            }
        }

        // 5b. Publish all derived flows.
        _peers.value = remotePeers
        _connectionsByTransport.value = buildConnectionCounts(deduped, localPeerKey)
        _meshTopology.value = MeshTopology(
            localPeerKey = localPeerKey,
            peers = meshPeerList,
            edges = meshEdgeList,
        )
        _localPeer.value = LocalPeerInfo(
            peerId = graph.localPeer.peerKey,
            deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            sdkLanguage = "Kotlin",
            sdkPlatform = "Android",
            sdkVersion = graph.localPeer.dittoSdkVersion ?: "Unknown",
            isCloudConnected = graph.localPeer.isConnectedToDittoServer,
        )
    }

    private fun DittoPeer.toSyncStatusInfo(
        metrics: JSONObject? = null,
        localPeerKey: String,
    ): SyncStatusInfo {
        val docs = metrics?.optJSONObject(FIELD_DOCUMENTS)
        return SyncStatusInfo(
            peerId = peerKey,
            isDittoServer = metrics?.optBoolean(FIELD_IS_DITTO_SERVER, false) ?: false,
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
            syncedUpToLocalCommitId = docs?.optLongOrNull(FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID),
            lastUpdateReceivedTime = docs?.optLongOrNull(FIELD_LAST_UPDATE_RECEIVED_TIME)?.toDouble(),
        )
    }

    private fun JSONObject.optLongOrNull(key: String): Long? =
        if (has(key) && !isNull(key)) optLong(key) else null

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

    private fun buildConnectionCounts(peers: Collection<DittoPeer>, localPeerKey: String): ConnectionsByTransport {
        var bluetooth = 0
        var lan = 0
        var p2pWifi = 0
        var webSocket = 0

        peers.forEach { peer ->
            peer.connections
                .filter { conn -> conn.peer1 == localPeerKey || conn.peer2 == localPeerKey }
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
