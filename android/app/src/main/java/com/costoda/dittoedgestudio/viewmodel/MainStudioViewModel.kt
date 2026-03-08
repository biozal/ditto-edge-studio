package com.costoda.dittoedgestudio.viewmodel

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
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
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
    QUERY_METRICS("Query Metrics", Icons.AutoMirrored.Outlined.ManageSearch),
}

sealed class PeersUiState {
    object Initializing : PeersUiState()
    data class Active(
        val localPeer: LocalPeerInfo?,
        val remotePeers: List<SyncStatusInfo>,
    ) : PeersUiState()
}

class MainStudioViewModel(
    private val databaseId: Long,
    private val databaseRepository: DatabaseRepository,
    private val dittoManager: DittoManager,
    private val systemRepository: SystemRepository,
    private val networkRepo: NetworkDiagnosticsRepository,
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

    var transportBluetoothEnabled by mutableStateOf(true)
    var transportLanEnabled by mutableStateOf(true)
    var transportWifiAwareEnabled by mutableStateOf(false)
    var transportCloudSyncEnabled by mutableStateOf(true)

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
                transportBluetoothEnabled = database.isBluetoothLeEnabled
                transportLanEnabled = database.isLanEnabled
                transportWifiAwareEnabled = database.isAwdlEnabled
                transportCloudSyncEnabled = database.isCloudSyncEnabled
                val ditto = dittoManager.hydrate(database)
                systemRepository.startObserving(ditto)
                syncEnabled = true
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
        viewModelScope.launch(Dispatchers.IO) {
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

    fun applyTransportSettings(bt: Boolean, lan: Boolean, wifiAware: Boolean) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        dittoManager.applyTransportConfig(
            ditto,
            db.copy(
                isBluetoothLeEnabled = bt,
                isLanEnabled = lan,
                isAwdlEnabled = wifiAware,
            ),
        )
        transportBluetoothEnabled = bt
        transportLanEnabled = lan
        transportWifiAwareEnabled = wifiAware
        transportConfigVisible = false
    }

    override fun onCleared() {
        super.onCleared()
        systemRepository.stopObserving()
        viewModelScope.launch { dittoManager.close() }
    }
}
