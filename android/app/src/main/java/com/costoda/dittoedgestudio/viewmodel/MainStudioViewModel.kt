package com.costoda.dittoedgestudio.viewmodel

import android.content.Context
import android.util.Log
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.DittoSyncSubscription
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class StudioNavItem(val label: String, val icon: ImageVector) {
    SUBSCRIPTIONS("Subscriptions", Icons.Outlined.Sync),
    QUERY("Query", Icons.Outlined.Storage),
    OBSERVERS("Observers", Icons.Outlined.Visibility),
    LOGGING("Logging", Icons.Outlined.Description),
    APP_METRICS("App Metrics", Icons.Outlined.Memory),
    QUERY_METRICS("Query Metrics", Icons.AutoMirrored.Outlined.ManageSearch);

    val helpFileName: String get() = when (this) {
        SUBSCRIPTIONS -> "subscription.md"
        QUERY -> "query.md"
        OBSERVERS -> "observe.md"
        LOGGING -> "logging.md"
        APP_METRICS -> "appmetrics.md"
        QUERY_METRICS -> "querymetrics.md"
    }
}

sealed class PeersUiState {
    object Initializing : PeersUiState()
    data class Active(
        val localPeer: LocalPeerInfo?,
        val remotePeers: List<SyncStatusInfo>,
    ) : PeersUiState()
}

private const val TAG = "MainStudioViewModel"

class MainStudioViewModel(
    private val databaseId: Long,
    private val databaseRepository: DatabaseRepository,
    private val dittoManager: DittoManager,
    private val systemRepository: SystemRepository,
    private val networkRepo: NetworkDiagnosticsRepository,
    private val subscriptionsRepository: SubscriptionsRepository,
    val collectionsRepository: CollectionsRepository,
    val loggingCaptureService: DittoLogCaptureService,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {

    var selectedNavItem by mutableStateOf(StudioNavItem.SUBSCRIPTIONS)
    var dataPanelVisible by mutableStateOf(true)
    var inspectorVisible by mutableStateOf(false)
    var syncEnabled by mutableStateOf(false)
    var bottomBarExpanded by mutableStateOf(true)
    var transportConfigVisible by mutableStateOf(false)
    var fabMenuExpanded by mutableStateOf(false)
    var connectionPopupVisible by mutableStateOf(false)
    var hydrateError by mutableStateOf<String?>(null)
    var showAddIndex by mutableStateOf(false)

    var currentDittoId by mutableStateOf<String?>(null)
        private set

    val collections: StateFlow<List<DittoCollection>> = collectionsRepository.collections
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Persisted subscription metadata — drives the sidebar list
    private val _subscriptions = MutableStateFlow<List<DittoSubscription>>(emptyList())
    val subscriptions: StateFlow<List<DittoSubscription>> = _subscriptions.asStateFlow()

    // Sheet control — null = closed, non-null = editing (new entry has id=0L)
    var editingSubscription by mutableStateOf<DittoSubscription?>(null)

    // In-memory live SDK handles keyed by Room subscription id
    private val activeHandles = mutableMapOf<Long, DittoSyncSubscription>()

    var transportBluetoothEnabled by mutableStateOf(true)
    var transportLanEnabled by mutableStateOf(true)
    var transportWifiAwareEnabled by mutableStateOf(false)
    var transportCloudSyncEnabled by mutableStateOf(true)
    var isApplyingTransport by mutableStateOf(false)

    private var currentDatabase: DittoDatabase? = null

    val peersUiState: StateFlow<PeersUiState> = combine(
        systemRepository.localPeer,
        systemRepository.peers,
    ) { local, remote ->
        PeersUiState.Active(localPeer = local, remotePeers = remote)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PeersUiState.Initializing)

    val connectionsByTransport: StateFlow<ConnectionsByTransport> =
        systemRepository.connectionsByTransport
            .stateIn(
                viewModelScope,
                SharingStarted.WhileSubscribed(5_000),
                ConnectionsByTransport.Empty,
            )

    private val _networkInterfaces = MutableStateFlow<List<NetworkInterfaceInfo>>(emptyList())
    val networkInterfaces: StateFlow<List<NetworkInterfaceInfo>> = _networkInterfaces.asStateFlow()

    private val _p2pTransports = MutableStateFlow<List<P2PTransportInfo>>(emptyList())
    val p2pTransports: StateFlow<List<P2PTransportInfo>> = _p2pTransports.asStateFlow()

    val hasNetworkPermission: Boolean
        get() = networkRepo.hasLocationOrNearbyPermission()

    init {
        hydrate()
    }

    private fun hydrate() {
        viewModelScope.launch {
            hydrateError = null
            runCatching {
                val database = databaseRepository.getById(databaseId)
                    ?: error("Database not found: $databaseId")
                currentDatabase = database
                currentDittoId = database.databaseId
                transportBluetoothEnabled = database.isBluetoothLeEnabled
                transportLanEnabled = database.isLanEnabled
                transportWifiAwareEnabled = database.isAwdlEnabled
                transportCloudSyncEnabled = database.isCloudSyncEnabled

                val ditto = dittoManager.hydrate(database)
                systemRepository.startObserving(ditto)
                collectionsRepository.startObserving(ditto)
                syncEnabled = true
                val saved = subscriptionsRepository.loadSubscriptions(database.databaseId)

                saved.forEach { sub ->
                    runCatching {
                        val handle = ditto.sync.registerSubscription(sub.query)
                        activeHandles[sub.id] = handle
                    }
                }
                _subscriptions.value = saved
            }.onFailure { e ->
                hydrateError = e.message
            }
        }
    }

    fun loadNetworkDiagnostics() {
        viewModelScope.launch {
            _networkInterfaces.value = networkRepo.fetchInterfaces()
            _p2pTransports.value = networkRepo.fetchP2PTransports()
        }
    }

    fun toggleSync() {
        val ditto = dittoManager.currentInstance() ?: return
        viewModelScope.launch(ioDispatcher) {
            runCatching {
                if (ditto.sync.isActive) {
                    ditto.sync.stop()
                    syncEnabled = false
                } else {
                    ditto.sync.start()
                    syncEnabled = true
                }
            }
        }
    }

    fun addSubscription(name: String, query: String) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        viewModelScope.launch {
            runCatching {
                val sub = DittoSubscription(databaseId = db.databaseId, name = name, query = query)
                val id = subscriptionsRepository.saveSubscription(sub)
                val handle = ditto.sync.registerSubscription(query)
                activeHandles[id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
            editingSubscription = null
        }
    }

    fun updateSubscription(subscription: DittoSubscription) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        viewModelScope.launch {
            runCatching {
                activeHandles.remove(subscription.id)?.close()
                subscriptionsRepository.updateSubscription(subscription)
                val handle = ditto.sync.registerSubscription(subscription.query)
                activeHandles[subscription.id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
            editingSubscription = null
        }
    }

    fun removeSubscription(id: Long) {
        val db = currentDatabase ?: return
        viewModelScope.launch(ioDispatcher) {
            activeHandles.remove(id)?.close()
            subscriptionsRepository.removeSubscription(id)
            _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
        }
    }

    fun addIndex(collection: String, fieldName: String) {
        viewModelScope.launch(ioDispatcher) {
            runCatching {
                collectionsRepository.createIndex(collection, fieldName)
            }.onFailure { e ->
                hydrateError = e.message
            }
            showAddIndex = false
        }
    }

    fun applyTransportSettings(bt: Boolean, lan: Boolean, wifiAware: Boolean) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        viewModelScope.launch(ioDispatcher) {
            isApplyingTransport = true
            runCatching {
                // 1. Stop sync and observers
                ditto.sync.stop()
                systemRepository.stopObserving()

                // 2. Apply new transport config to live Ditto instance
                val updatedDb = db.copy(
                    isBluetoothLeEnabled = bt,
                    isLanEnabled = lan,
                    isAwdlEnabled = wifiAware,
                )
                dittoManager.applyTransportConfig(ditto, updatedDb)

                // 3. Persist to Room so settings survive app restart
                databaseRepository.save(updatedDb)
                currentDatabase = updatedDb

                // 4. Restart sync and re-register observers
                ditto.sync.start()
                systemRepository.startObserving(ditto)
            }.onFailure { e ->
                Log.w(TAG, "applyTransportSettings failed: ${e.message}", e)
            }
            transportBluetoothEnabled = bt
            transportLanEnabled = lan
            transportWifiAwareEnabled = wifiAware
            isApplyingTransport = false
            transportConfigVisible = false
        }
    }

    override fun onCleared() {
        super.onCleared()
        systemRepository.stopObserving()
        collectionsRepository.stopObserving()
        activeHandles.values.forEach { it.close() }
        activeHandles.clear()
        _subscriptions.value = emptyList()
        viewModelScope.launch { dittoManager.close() }
    }
}
