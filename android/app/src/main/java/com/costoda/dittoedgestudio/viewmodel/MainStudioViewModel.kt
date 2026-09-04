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
import com.costoda.dittoedgestudio.domain.model.IndexField
import com.costoda.dittoedgestudio.domain.model.MulticastConfig
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

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

    /** True when this item only appears while "Collect Metrics" is enabled — mirrors
     *  SwiftUI's `SidebarDestination.isMetricsDestination`. */
    val isMetricsDestination: Boolean get() = this == APP_METRICS || this == QUERY_METRICS

    companion object {
        /** Rail items visible for the given "Collect Metrics" setting — mirrors SwiftUI's
         *  `MainStudioView.availableDestinations`. */
        fun visibleEntries(metricsEnabled: Boolean): List<StudioNavItem> =
            entries.filter { metricsEnabled || !it.isMetricsDestination }
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
 * The session is supplied as a `() -> StudioSession` lookup lambda — typically a Koin
 * scope query keyed by databaseId. The lambda is invoked on **every** `session`
 * access so this VM always sees the **current** session, even after the user backs
 * out of the studio (closing the Koin scope and `StudioSession`) and re-enters
 * (creating a fresh scope + session). A previous design captured the session as a
 * constructor field, which left the outer VM observing a closed, emptied session's
 * StateFlows after re-entry — manifesting as "my subscriptions disappeared".
 *
 * Tests can pass `{ mockSession }` to inject a deterministic instance.
 */
class MainStudioViewModel(
    private val sessionProvider: () -> StudioSession,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    val session: StudioSession get() = sessionProvider()

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

    // ── Presence Viewer filter state ─────────────────────────────────────────
    // Mirrors iOS PresenceViewerSK.ViewModel.showDirectConnectedOnly. Controls whether
    // remote-to-remote (peer A ↔ peer B) edges are drawn in PresenceGraphView. Defaults
    // to true so the graph starts at the same "direct-only" view as iOS.
    private val _showDirectConnectedOnly = MutableStateFlow(true)
    val showDirectConnectedOnly: StateFlow<Boolean> = _showDirectConnectedOnly.asStateFlow()
    /** Atomic flip — guards against the unlikely concurrent-toggle case. */
    fun toggleDirectConnectedOnly() {
        _showDirectConnectedOnly.update { !it }
    }

    // Presence-viewer controls visibility (the VS Code extension's eye toggle) —
    // hides the legend + Direct toggle + zoom cluster; reset and the eye itself
    // always remain. Session-scoped here so it survives rail-section navigation.
    private val _presenceControlsVisible = MutableStateFlow(true)
    val presenceControlsVisible: StateFlow<Boolean> = _presenceControlsVisible.asStateFlow()
    fun togglePresenceControlsVisible() {
        _presenceControlsVisible.update { !it }
    }

    // Presence-viewer focus mode: the focused peer id (Expanded mesh only, null
    // when unfocused). Hoisted here (like presenceControlsVisible) because the
    // Peers ↔ Viewer tab switch disposes the PresenceGraphView subtree —
    // view-local state would kill an active focus session on every tab hop.
    private val _presenceFocusedPeerId = MutableStateFlow<String?>(null)
    val presenceFocusedPeerId: StateFlow<String?> = _presenceFocusedPeerId.asStateFlow()
    fun setPresenceFocusedPeer(peerId: String?) {
        _presenceFocusedPeerId.value = peerId
    }

    // Snapshot views — used only for initial values of `remember { mutableStateOf(...) }`
    // inside the transport-config sheet, and for non-Compose readers (tests).
    val syncEnabled: Boolean get() = session.syncEnabled.value
    val isApplyingTransport: Boolean get() = session.isApplyingTransport.value
    val transportBluetoothEnabled: Boolean get() = session.transportBluetoothEnabled.value
    val transportLanEnabled: Boolean get() = session.transportLanEnabled.value
    val transportWifiAwareEnabled: Boolean get() = session.transportWifiAwareEnabled.value
    val transportCloudSyncEnabled: Boolean get() = session.transportCloudSyncEnabled.value
    val transportMulticastConfig: MulticastConfig get() = session.transportMulticastConfig.value

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
    /**
     * Suspends until the new subscription is committed to Room. The editor sheet
     * shows a "Saving…" indicator and blocks dismissal while this is in flight, so
     * the user can't back out mid-save and silently lose data. The actual Room
     * write runs under [kotlinx.coroutines.NonCancellable] inside the session.
     */
    suspend fun addSubscription(name: String, query: String): Result<Unit> {
        val result = session.addSubscriptionSuspend(name, query)
        if (result.isSuccess) editingSubscription = null
        return result
    }

    suspend fun updateSubscription(subscription: DittoSubscription): Result<Unit> {
        val result = session.updateSubscriptionSuspend(subscription)
        if (result.isSuccess) editingSubscription = null
        return result
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

    // ── Welcome screen (auto-show on fresh databases) ────────────────────────
    val welcomeCandidateFlow: StateFlow<Boolean> get() = session.welcomeCandidate

    // ── system:metrics dashboard (SDK 5.1) ───────────────────────────────────
    val systemMetrics: StateFlow<com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot>
        get() = session.systemMetrics
    fun startSystemMetricsPolling() = session.startSystemMetricsPolling()
    fun stopSystemMetricsPolling() = session.stopSystemMetricsPolling()

    // ── Debug console (SDK 5.1 debug_socket) ─────────────────────────────────
    val debugConsoleActive: StateFlow<Boolean> get() = session.debugConsoleActive
    suspend fun executeDebugStatement(statement: String): Result<String> =
        session.executeDebugStatement(statement)
    suspend fun closeDebugConsole() = session.closeDebugConsole()
    fun consumeWelcomeTrigger(): Boolean = session.consumeWelcomeTrigger()

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

    /**
     * Creates an index. Returns null on success or the error message on failure;
     * the caller (Add Index sheet) is responsible for dismissing on success and
     * displaying the error otherwise.
     */
    suspend fun addIndex(collection: String, fields: List<IndexField>): String? =
        session.addIndex(collection, fields).fold(
            onSuccess = { null },
            onFailure = { it.message ?: "Failed to create index" },
        )

    fun applyTransportSettings(
        bt: Boolean,
        lan: Boolean,
        wifiAware: Boolean,
        multicast: MulticastConfig = session.transportMulticastConfig.value,
    ) {
        session.applyTransportSettings(bt, lan, wifiAware, multicast)
        transportConfigVisible = false
    }

    // NOTE: We intentionally do NOT close the StudioSession from onCleared(). The session
    // outlives this ViewModel — each studio rail section is its own NavKey entry (Task 4.3),
    // and clearing the VM for one entry must not tear the session down. Session teardown is
    // driven by the Koin `studio` scope's `onClose` hook, fired by the StudioScopeManager
    // composable in AppNavGraph when no studio entry for the databaseId remains on the back
    // stack.
}
