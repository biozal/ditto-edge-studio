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
    SUBSCRIPTIONS("Presence", Icons.Outlined.Sync),
    QUERY("Query Workbench", Icons.Outlined.Storage),
    OBSERVERS("Observation", Icons.Outlined.Visibility),
    LOGGING("Log Analyzer", Icons.Outlined.Description),
    APP_METRICS("App Metrics", Icons.Outlined.Memory),
    QUERY_METRICS("Query Metrics", Icons.AutoMirrored.Outlined.ManageSearch),
    DISK_USAGE("Database Metrics", Icons.Outlined.DataUsage);

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
 * Studio UI coordinator. Owns purely visual / panel / picker state (selectedNavItem, sheet
 * toggles, paging cursors for the observer events list, etc.) and delegates everything
 * Ditto-session-related to [StudioSession].
 *
 * The session is supplied by the UI via `parametersOf` after looking up / creating the
 * Koin `studio` scope keyed by databaseId — see [com.costoda.dittoedgestudio.ui.navigation.AppNavGraph].
 */
class MainStudioViewModel(
    val session: StudioSession,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    companion object {
        internal const val KEY_SELECTED_NAV = "selectedNavItem"
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

    // ── Pure UI state delegated to session.uiState (survives rail-section switches) ──────────
    // Delegating vars: get/set forward to the session-scoped StudioUiState so these properties
    // survive per-entry VM recreation. All existing call sites compile unchanged.
    var transportConfigVisible: Boolean
        get() = session.uiState.transportConfigVisible
        set(value) { session.uiState.transportConfigVisible = value }
    var showAddIndex: Boolean
        get() = session.uiState.showAddIndex
        set(value) { session.uiState.showAddIndex = value }
    var editingSubscription: DittoSubscription?
        get() = session.uiState.editingSubscription
        set(value) { session.uiState.editingSubscription = value }
    var editingObserver: DittoObservable?
        get() = session.uiState.editingObserver
        set(value) { session.uiState.editingObserver = value }
    var selectedObserver: DittoObservable?
        get() = session.uiState.selectedObserver
        set(value) { session.uiState.selectedObserver = value }
    var selectedEvent: DittoObserveEvent?
        get() = session.uiState.selectedEvent
        set(value) { session.uiState.selectedEvent = value }
    var eventFilterMode: EventFilterMode
        get() = session.uiState.eventFilterMode
        set(value) { session.uiState.eventFilterMode = value }
    var eventPageSize: Int
        get() = session.uiState.eventPageSize
        set(value) { session.uiState.eventPageSize = value }
    var eventCurrentPage: Int
        get() = session.uiState.eventCurrentPage
        set(value) { session.uiState.eventCurrentPage = value }

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

    // ── Thin facades over StudioSession ──────────────────────────────────────

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
    // outlives this ViewModel — each studio rail section is its own NavKey entry (Task 4.3),
    // and clearing the VM for one entry must not tear the session down. Session teardown is
    // driven by the Koin `studio` scope's `onClose` hook, fired by the StudioScopeManager
    // composable in AppNavGraph when no studio entry for the databaseId remains on the back
    // stack.
}
