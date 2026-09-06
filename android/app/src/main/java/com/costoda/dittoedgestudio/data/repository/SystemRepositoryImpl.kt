package com.costoda.dittoedgestudio.data.repository

import android.os.Build
import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
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
import com.ditto.kotlin.serialization.DittoJsonSerializable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

class SystemRepositoryImpl(
    private val coroutineScope: CoroutineScope,
    /**
     * Current database config, used to filter stale presence-graph connections on
     * disabled transports (SDK bug workaround, mirroring SwiftUI SystemRepository).
     * Null means "no config known" — nothing is filtered.
     */
    private val databaseProvider: () -> com.costoda.dittoedgestudio.domain.model.DittoDatabase? = { null },
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
            if (BuildConfig.DEBUG) {
                Log.w(TAG, "system:data_sync_info query failed — commit IDs unavailable", e)
            }
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
        val config = databaseProvider()

        // 3. Map presence peers with merged sync metrics
        val remotePeers = deduped.map { peer ->
            processedIds.add(peer.peerKey)
            peer.toSyncStatusInfo(syncMetrics[peer.peerKey], localPeerKey, config)
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

        // 5a. Build the full mesh topology — every connection the SDK knows about,
        //     plus every discovered peer that participates in at least one of those
        //     edges. The Presence Viewer needs this when the user toggles "Direct
        //     Connected" off; everything else keeps using the filtered [_peers] list
        //     above per the presence-graph pitfall rule.
        val allPeersDeduped = graph.remotePeers
            .groupBy { it.peerKey }
            .mapValues { (_, peers) ->
                peers.maxByOrNull { it.dittoSdkVersion != null } ?: peers.first()
            }
            .values
        val seenEdgeKeys = mutableSetOf<String>()
        val meshEdgeList = buildList {
            // Ditto usually reports the same undirected edge from both endpoints, but
            // the local peer is the authoritative source for edges attached to this
            // process. Aggregate it too so a transport (notably multicast) is not
            // lost when only the local side advertises the edge. (Same fix as the
            // VS Code extension's buildPresenceGraphView.)
            for (peer in listOf(graph.localPeer) + allPeersDeduped) {
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
        // Orphan filter (extension pass 2): remote peers appearing in no aggregated
        // edge are dropped — otherwise they float as pills on the outermost ring in
        // the sync stop→start window. The local peer is always shown regardless —
        // it's added by the graph model builder, not from this list.
        val meshPeerList = filterOrphanMeshPeers(
            peers = allPeersDeduped.map { peer -> peer.toMeshPeer() },
            edges = meshEdgeList,
        )

        // 5b. Publish all derived flows.
        _peers.value = remotePeers
        _connectionsByTransport.value = buildConnectionCounts(
            deduped,
            localPeerKey,
            dittoServerCount = remotePeers.count { it.isDittoServer },
            config = config,
        )
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
            // The Kotlin SDK exposes this as `isConnectedToDittoServer`; the iOS SDK
            // calls the same flag `isConnectedToDittoCloud`. Both mean the same thing
            // — "is this local device currently linked to the hosted Big Peer / Ditto
            // Cloud service?" (NOT an on-prem Ditto Server instance — that's a
            // different product). Keep our domain field name iOS-aligned.
            isCloudConnected = graph.localPeer.isConnectedToDittoServer,
        )
    }

    private fun DittoPeer.toSyncStatusInfo(
        metrics: JSONObject? = null,
        localPeerKey: String,
        config: com.costoda.dittoedgestudio.domain.model.DittoDatabase? = null,
    ): SyncStatusInfo {
        val docs = metrics?.optJSONObject(FIELD_DOCUMENTS)
        return SyncStatusInfo(
            peerId = peerKey,
            isDittoServer = metrics?.optBoolean(FIELD_IS_DITTO_SERVER, false) ?: false,
            deviceName = deviceName.takeIf { it.isNotBlank() },
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
                }
                // Drop stale connections on user-disabled transports (the SDK
                // presence graph keeps reporting them after a transport config
                // change) so one can't drive dominantConnectionType()/the card
                // gradient. Mirrors SwiftUI SystemRepository's
                // `mapped.filter { isConnectionTypeEnabled($0.type, config:) }`.
                .filter { info -> config == null || info.type.isEnabledIn(config) },
            // ObjectValue.toString() is Kotlin map syntax ("{role=my kiosk}"), NOT JSON —
            // verified: org.json.JSONObject rejects it. The raw string is kept only for
            // RemotePeerCard's verbatim display; never derive a key count from it, use
            // the counts below.
            peerMetadata = peerMetadata.takeIf { it.isNotEmpty() }?.toString(),
            peerMetadataKeyCount = peerMetadata.keyCountOrZero(),
            identityServiceMetadata = identityServiceMetadata.takeIf { it.isNotEmpty() }?.toString(),
            identityServiceMetadataKeyCount = identityServiceMetadata.keyCountOrZero(),
            syncedUpToLocalCommitId = docs?.optLongOrNull(FIELD_SYNCED_UP_TO_LOCAL_COMMIT_ID),
            lastUpdateReceivedTime = docs?.optLongOrNull(FIELD_LAST_UPDATE_RECEIVED_TIME)?.toDouble(),
        )
    }

    /**
     * Full `DittoPeer` projection for the mesh view. Everything here is available for
     * INDIRECT peers as well — the presence graph reports the same fields regardless of
     * whether we can reach the peer. Sync progress is deliberately absent: it comes from
     * `system:data_sync_info`, which only has rows for peers we actually receive data
     * from.
     *
     * Metadata is reduced to (raw JSON, top-level key count) here rather than in the UI
     * so the SDK's serialization types stay out of the Compose layer, and so the key
     * count is computed once per presence update instead of once per recomposition.
     */
    private fun DittoPeer.toMeshPeer(): MeshPeer {
        // NOT `takeIf { !it.isNull }`: isNull asks "is this the JSON literal null?", so
        // it is false for an ObjectValue even when the object is empty — verified
        // against the SDK (empty ObjectValue: isNull=false, isEmpty=true, toString="{}").
        // Using it would give every peer that never set metadata a non-blank "{}" and
        // the card would report metadata "present" for all of them.
        val peerMeta = peerMetadata.takeIf { it.isNotEmpty() }
        val identityMeta = identityServiceMetadata.takeIf { it.isNotEmpty() }
        return MeshPeer(
            peerKey = peerKey,
            deviceName = deviceName.takeIf { it.isNotBlank() },
            os = os?.toPeerOS() ?: PeerOS.Unknown,
            dittoSdkVersion = dittoSdkVersion?.takeIf { it.isNotBlank() },
            isConnectedToDittoServer = isConnectedToDittoServer,
            isCompatible = isCompatible,
            peerMetadata = peerMeta?.toString(),
            peerMetadataKeyCount = peerMeta?.keyCountOrZero() ?: 0,
            identityServiceMetadata = identityMeta?.toString(),
            identityServiceMetadataKeyCount = identityMeta?.keyCountOrZero() ?: 0,
        )
    }

    /** Top-level key count, 0 if the SDK object can't be converted (never throws). */
    private fun DittoJsonSerializable.ObjectValue.keyCountOrZero(): Int =
        runCatching { toMap().size }.getOrDefault(0)

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
        DittoConnectionType.Multicast -> ConnectionType.Multicast
        DittoConnectionType.P2PWiFi -> ConnectionType.P2PWiFi
        DittoConnectionType.WebSocket -> ConnectionType.WebSocket
    }

    private fun buildConnectionCounts(
        peers: Collection<DittoPeer>,
        localPeerKey: String,
        dittoServerCount: Int,
        config: com.costoda.dittoedgestudio.domain.model.DittoDatabase?,
    ): ConnectionsByTransport {
        var bluetooth = 0
        var lan = 0
        var p2pWifi = 0
        var webSocket = 0
        var multicast = 0

        peers.forEach { peer ->
            peer.connections
                .filter { conn -> conn.peer1 == localPeerKey || conn.peer2 == localPeerKey }
                .distinctBy { it.connectionType }
                .forEach { conn ->
                    val type = conn.connectionType.toConnectionType()
                    // Skip connections for disabled transports (SDK bug workaround:
                    // the presence graph retains stale connections after transport
                    // config changes). Mirrors SwiftUI's isConnectionTypeEnabled.
                    if (config != null && !type.isEnabledIn(config)) return@forEach
                    when (type) {
                        ConnectionType.Bluetooth -> bluetooth++
                        ConnectionType.LAN -> lan++
                        ConnectionType.P2PWiFi -> p2pWifi++
                        ConnectionType.WebSocket -> webSocket++
                        ConnectionType.Multicast -> multicast++
                        ConnectionType.Unknown -> { /* skip */ }
                    }
                }
        }

        return ConnectionsByTransport(
            bluetooth = bluetooth,
            lan = lan,
            p2pWifi = p2pWifi,
            webSocket = webSocket,
            dittoServer = dittoServerCount,
            multicast = multicast,
        )
    }
}

/** Whether a transport is enabled in the database config (SwiftUI parity). */
internal fun ConnectionType.isEnabledIn(config: com.costoda.dittoedgestudio.domain.model.DittoDatabase): Boolean =
    when (this) {
        ConnectionType.Bluetooth -> config.isBluetoothLeEnabled
        ConnectionType.LAN -> config.isLanEnabled
        ConnectionType.P2PWiFi -> config.isAwdlEnabled
        ConnectionType.WebSocket -> config.isCloudSyncEnabled
        // Multicast (beta, SDK 5.1.0) is configured via `peerToPeer.multicastBeta`
        // from the per-database `isMulticastEnabled` flag (Transport Settings) —
        // mirrors SwiftUI's isConnectionTypeEnabled.
        ConnectionType.Multicast -> config.isMulticastEnabled
        ConnectionType.Unknown -> true
    }

/**
 * Keep only peers that participate in at least one mesh edge (VS Code extension
 * `buildPresenceGraphView` pass 2). Drops orphan peers the SDK has discovered
 * (mDNS/BLE) but holds no current connection to — most visible in the window
 * right after `sync.stop()` → `sync.start()`, when transports stay alive across
 * the toggle but sync sessions don't. Edge participation (not an empty
 * own-connections list) is the criterion so a peer that only appears as peer2
 * in another peer's connection list is still drawn.
 */
internal fun filterOrphanMeshPeers(peers: List<MeshPeer>, edges: List<MeshEdge>): List<MeshPeer> {
    val peersInAnyEdge = HashSet<String>(edges.size * 2)
    for (edge in edges) {
        peersInAnyEdge.add(edge.peer1)
        peersInAnyEdge.add(edge.peer2)
    }
    return peers.filter { it.peerKey in peersInAnyEdge }
}
