package com.costoda.dittoedgestudio.viewmodel

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.DataUsage
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.domain.model.EventFilterMode
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import kotlinx.coroutines.flow.StateFlow

enum class StudioNavItem(val label: String, val icon: ImageVector) {
    SUBSCRIPTIONS("Subscriptions", Icons.Outlined.Sync),
    QUERY("Query", Icons.Outlined.Storage),
    OBSERVERS("Observers", Icons.Outlined.Visibility),
    LOGGING("Logging", Icons.Outlined.Description),
    APP_METRICS("App Metrics", Icons.Outlined.Memory),
    QUERY_METRICS("Query Metrics", Icons.AutoMirrored.Outlined.ManageSearch),
    DISK_USAGE("Disk Usage", Icons.Outlined.DataUsage);

    val helpFileName: String get() = when (this) {
        SUBSCRIPTIONS -> "subscription.md"
        QUERY -> "query.md"
        OBSERVERS -> "observe.md"
        LOGGING -> "logging.md"
        APP_METRICS -> "appmetrics.md"
        QUERY_METRICS -> "querymetrics.md"
        DISK_USAGE -> "diskusage.md"
    }
}

// PeersUiState was moved to com.costoda.dittoedgestudio.data.session.PeersUiState
// so it can live alongside the StudioSession that owns the underlying flow. Call sites
// should `import com.costoda.dittoedgestudio.data.session.PeersUiState` directly.

/**
 * Studio UI coordinator. Owns purely visual / panel / picker state (selectedNavItem,
 * dataPanelVisible, inspectorVisible, sheet toggles, paging cursors for the observer events
 * list, etc.) and delegates everything Ditto-session-related to [StudioSession].
 *
 * The session is supplied by the UI via `parametersOf` after looking up / creating the
 * Koin `studio` scope keyed by databaseId — see [com.costoda.dittoedgestudio.ui.navigation.AppNavGraph].
 *
 * Public surface intentionally mirrors the pre-extraction shape so [MainStudioScreen]
 * call sites stay stable.
 */
class MainStudioViewModel(
    val session: StudioSession,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    companion object {
        internal const val KEY_SELECTED_NAV = "selectedNavItem"
        internal const val KEY_DATA_PANEL_VISIBLE = "dataPanelVisible"
        internal const val KEY_INSPECTOR_VISIBLE = "inspectorVisible"
    }

    // Backing Compose state initialised from the handle so Compose can observe changes,
    // with write-through to the handle so values survive process death.
    private var _selectedNavItem by mutableStateOf(
        savedStateHandle.get<String>(KEY_SELECTED_NAV)
            ?.let { saved -> StudioNavItem.entries.firstOrNull { it.name == saved } }
            ?: StudioNavItem.SUBSCRIPTIONS
    )
    var selectedNavItem: StudioNavItem
        get() = _selectedNavItem
        set(value) { _selectedNavItem = value; savedStateHandle[KEY_SELECTED_NAV] = value.name }

    private var _dataPanelVisible by mutableStateOf(
        savedStateHandle.get<Boolean>(KEY_DATA_PANEL_VISIBLE) ?: true
    )
    var dataPanelVisible: Boolean
        get() = _dataPanelVisible
        set(value) { _dataPanelVisible = value; savedStateHandle[KEY_DATA_PANEL_VISIBLE] = value }

    private var _inspectorVisible by mutableStateOf(
        savedStateHandle.get<Boolean>(KEY_INSPECTOR_VISIBLE) ?: false
    )
    var inspectorVisible: Boolean
        get() = _inspectorVisible
        set(value) { _inspectorVisible = value; savedStateHandle[KEY_INSPECTOR_VISIBLE] = value }

    // ── Pure UI state (sheets, panels, transient pickers) ────────────────────
    var bottomBarExpanded by mutableStateOf(true)
    var transportConfigVisible by mutableStateOf(false)
    var fabMenuExpanded by mutableStateOf(false)
    var connectionPopupVisible by mutableStateOf(false)
    var showAddIndex by mutableStateOf(false)

    var editingSubscription by mutableStateOf<DittoSubscription?>(null)
    var editingObserver by mutableStateOf<DittoObservable?>(null)

    var selectedObserver by mutableStateOf<DittoObservable?>(null)
    var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
    var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
    var eventPageSize by mutableStateOf(25)
    var eventCurrentPage by mutableStateOf(0)

    // ── Session passthroughs (keep call sites stable) ─────────────────────────

    val loggingCaptureService: DittoLogCaptureService get() = session.loggingCaptureService
    val collectionsRepository: CollectionsRepository get() = session.collectionsRepository
    val collections: StateFlow<List<DittoCollection>> get() = session.collections
    val subscriptions: StateFlow<List<DittoSubscription>> get() = session.subscriptions
    val observers: StateFlow<List<DittoObservable>> get() = session.observers
    val observerEvents: StateFlow<List<DittoObserveEvent>> get() = session.observerEvents
    val peersUiState: StateFlow<PeersUiState> get() = session.peersUiState
    val connectionsByTransport: StateFlow<ConnectionsByTransport> get() = session.connectionsByTransport
    val networkInterfaces: StateFlow<List<NetworkInterfaceInfo>> get() = session.networkInterfaces
    val p2pTransports: StateFlow<List<P2PTransportInfo>> get() = session.p2pTransports

    val currentDittoId: String? get() = session.currentDittoId
    val hydrateError: String? get() = session.hydrateError
    val hasNetworkPermission: Boolean get() = session.hasNetworkPermission

    // Reactive flags — exposed as StateFlow so the screen's `collectAsStateWithLifecycle`
    // recomposes when sync starts/stops or transport-apply finishes.
    val syncEnabledFlow: StateFlow<Boolean> get() = session.syncEnabled
    val isApplyingTransportFlow: StateFlow<Boolean> get() = session.isApplyingTransport

    // Snapshot views — used only for initial values of `remember { mutableStateOf(...) }`
    // inside the transport-config sheet, and for non-Compose readers (tests).
    val syncEnabled: Boolean get() = session.syncEnabled.value
    val isApplyingTransport: Boolean get() = session.isApplyingTransport.value
    val transportBluetoothEnabled: Boolean get() = session.transportBluetoothEnabled.value
    val transportLanEnabled: Boolean get() = session.transportLanEnabled.value
    val transportWifiAwareEnabled: Boolean get() = session.transportWifiAwareEnabled.value
    val transportCloudSyncEnabled: Boolean get() = session.transportCloudSyncEnabled.value

    init {
        // Idempotent — StudioSession.hydrate is safe to invoke on first VM creation only,
        // which mirrors prior behaviour where the ViewModel's `init` called `hydrate()`.
        // Scope-level construction guarantees this VM is created at most once per studio
        // session; subsequent rail-section navigations reuse the same scope.
        if (session.currentDittoId == null && session.hydrateError == null) {
            session.hydrate()
        }
    }

    // ── Thin facades to keep MainStudioScreen call sites unchanged ────────────

    fun loadNetworkDiagnostics() = session.loadNetworkDiagnostics()
    fun toggleSync() = session.toggleSync()
    fun addSubscription(name: String, query: String) {
        session.addSubscription(name, query)
        editingSubscription = null
    }
    fun updateSubscription(subscription: DittoSubscription) {
        session.updateSubscription(subscription)
        editingSubscription = null
    }
    fun removeSubscription(id: Long) = session.removeSubscription(id)

    fun addObserver(name: String, query: String) {
        session.addObserver(name, query)
        editingObserver = null
    }
    fun updateObserver(observer: DittoObservable, name: String, query: String) {
        session.updateObserver(observer, name, query)
        editingObserver = null
    }
    fun removeObserver(observer: DittoObservable) {
        session.removeObserver(observer)
        if (selectedObserver?.id == observer.id) {
            selectedObserver = null
            selectedEvent = null
        }
    }
    fun activateObserver(observer: DittoObservable) = session.activateObserver(observer)
    fun deactivateObserver(observer: DittoObservable) {
        session.deactivateObserver(observer)
        if (selectedObserver?.id == observer.id) {
            selectedEvent = null
            eventCurrentPage = 0
        }
    }
    fun isObserverActive(observer: DittoObservable): Boolean = session.isObserverActive(observer)

    fun selectObserver(observer: DittoObservable) {
        selectedObserver = observer
        selectedEvent = null
        eventCurrentPage = 0
        eventFilterMode = EventFilterMode.ALL
    }

    fun selectEvent(event: DittoObserveEvent) {
        selectedEvent = event
    }

    fun selectedObserverEvents(): List<DittoObserveEvent> {
        val obsId = selectedObserver?.id ?: return emptyList()
        return session.observerEventsFor(obsId)
    }

    fun addIndex(collection: String, fieldName: String) {
        session.addIndex(collection, fieldName)
        showAddIndex = false
    }

    fun applyTransportSettings(bt: Boolean, lan: Boolean, wifiAware: Boolean) {
        session.applyTransportSettings(bt, lan, wifiAware)
        transportConfigVisible = false
    }

    // NOTE: We intentionally do NOT close the StudioSession from onCleared(). The session
    // outlives this ViewModel — when rail sections become separate NavKey entries (Task 4.x)
    // each section will instantiate its own VM, and clearing one must not tear the session
    // down. Session teardown is driven by the Koin `studio` scope's `onClose` hook, fired
    // from a DisposableEffect on the StudioKey entry in AppNavGraph.
}
