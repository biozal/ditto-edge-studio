package com.costoda.dittoedgestudio.data.session

import android.util.Log
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.DittoStoreObserver
import com.ditto.kotlin.DittoSyncSubscription
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Studio "session" — owns the Ditto instance lifecycle (hydration, sync, subscription handles,
 * store observer handles) for a single [databaseId] for the duration of a user's session in the
 * studio.
 *
 * The session is **not** a [androidx.lifecycle.ViewModel]; it lives inside a Koin `studio` scope
 * keyed by databaseId so that it survives across navigation between rail sections (which will
 * each become a sibling NavKey in Task 4.x) but dies exactly once when the studio is exited.
 *
 * Lifecycle invariant: [close] is idempotent — repeated calls (e.g. Koin scope onClose + an
 * explicit teardown path) close the underlying Ditto exactly once. Guarded by [closed].
 */
class StudioSession(
    private val databaseId: Long,
    private val databaseRepository: DatabaseRepository,
    private val dittoManager: DittoManager,
    private val systemRepository: SystemRepository,
    private val networkRepo: NetworkDiagnosticsRepository,
    private val subscriptionsRepository: SubscriptionsRepository,
    val collectionsRepository: CollectionsRepository,
    val loggingCaptureService: DittoLogCaptureService,
    private val observableRepository: ObservableRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {

    /**
     * Session-owned coroutine scope. The session is not a ViewModel, so there is no viewModelScope
     * — we manage our own scope here. Cancelled inside [close].
     */
    private val sessionScope = CoroutineScope(SupervisorJob() + ioDispatcher)

    private val closed = AtomicBoolean(false)

    // ── Session-scoped ephemeral UI state ─────────────────────────────────────
    /**
     * Ephemeral UI state that must survive rail-section switches. Compose snapshot state so
     * any composable reading these fields recomposes automatically on change.
     */
    val uiState = StudioUiState()

    // ── Hydration / database state ────────────────────────────────────────────
    var hydrateError: String? = null
        private set

    var currentDittoId: String? = null
        private set

    private var currentDatabase: DittoDatabase? = null
    fun currentDatabase(): DittoDatabase? = currentDatabase

    // ── Sync / transport state ────────────────────────────────────────────────
    private val _syncEnabled = MutableStateFlow(false)
    val syncEnabled: StateFlow<Boolean> = _syncEnabled.asStateFlow()

    private val _transportBluetoothEnabled = MutableStateFlow(true)
    val transportBluetoothEnabled: StateFlow<Boolean> = _transportBluetoothEnabled.asStateFlow()

    private val _transportLanEnabled = MutableStateFlow(true)
    val transportLanEnabled: StateFlow<Boolean> = _transportLanEnabled.asStateFlow()

    private val _transportWifiAwareEnabled = MutableStateFlow(false)
    val transportWifiAwareEnabled: StateFlow<Boolean> = _transportWifiAwareEnabled.asStateFlow()

    private val _transportCloudSyncEnabled = MutableStateFlow(true)
    val transportCloudSyncEnabled: StateFlow<Boolean> = _transportCloudSyncEnabled.asStateFlow()

    private val _isApplyingTransport = MutableStateFlow(false)
    val isApplyingTransport: StateFlow<Boolean> = _isApplyingTransport.asStateFlow()

    // ── Subscriptions ─────────────────────────────────────────────────────────
    private val _subscriptions = MutableStateFlow<List<DittoSubscription>>(emptyList())
    val subscriptions: StateFlow<List<DittoSubscription>> = _subscriptions.asStateFlow()

    private val activeHandles = mutableMapOf<Long, DittoSyncSubscription>()

    // ── Observers ─────────────────────────────────────────────────────────────
    private val _observers = MutableStateFlow<List<DittoObservable>>(emptyList())
    val observers: StateFlow<List<DittoObservable>> = _observers.asStateFlow()

    private val activeObserverHandles = mutableMapOf<Long, DittoStoreObserver>()

    private val _observerEvents = MutableStateFlow<List<DittoObserveEvent>>(emptyList())
    val observerEvents: StateFlow<List<DittoObserveEvent>> = _observerEvents.asStateFlow()

    // ── Collections / peers / connections ─────────────────────────────────────
    val collections: StateFlow<List<DittoCollection>> = collectionsRepository.collections
        .stateIn(sessionScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val peersUiState: StateFlow<PeersUiState> = combine(
        systemRepository.localPeer,
        systemRepository.peers,
    ) { local, remote ->
        PeersUiState.Active(localPeer = local, remotePeers = remote)
    }.stateIn(sessionScope, SharingStarted.WhileSubscribed(5_000), PeersUiState.Initializing)

    val connectionsByTransport: StateFlow<ConnectionsByTransport> =
        systemRepository.connectionsByTransport
            .stateIn(
                sessionScope,
                SharingStarted.WhileSubscribed(5_000),
                ConnectionsByTransport.Empty,
            )

    // ── Network diagnostics (lazy fetch) ──────────────────────────────────────
    private val _networkInterfaces = MutableStateFlow<List<NetworkInterfaceInfo>>(emptyList())
    val networkInterfaces: StateFlow<List<NetworkInterfaceInfo>> = _networkInterfaces.asStateFlow()

    private val _p2pTransports = MutableStateFlow<List<P2PTransportInfo>>(emptyList())
    val p2pTransports: StateFlow<List<P2PTransportInfo>> = _p2pTransports.asStateFlow()

    val hasNetworkPermission: Boolean
        get() = networkRepo.hasLocationOrNearbyPermission()

    /**
     * Hydrate the Ditto instance for this session's [databaseId]. Idempotent in the sense that
     * a hydration failure leaves [hydrateError] set; callers may choose to surface it. Starts
     * system + collections observers and pre-registers persisted subscriptions.
     */
    fun hydrate() {
        sessionScope.launch {
            hydrateError = null
            runCatching {
                val database = databaseRepository.getById(databaseId)
                    ?: error("Database not found: $databaseId")
                currentDatabase = database
                currentDittoId = database.databaseId
                _transportBluetoothEnabled.value = database.isBluetoothLeEnabled
                _transportLanEnabled.value = database.isLanEnabled
                _transportWifiAwareEnabled.value = database.isAwdlEnabled
                _transportCloudSyncEnabled.value = database.isCloudSyncEnabled

                val ditto = dittoManager.hydrate(database)
                systemRepository.startObserving(ditto)
                collectionsRepository.startObserving(ditto)
                _syncEnabled.value = true
                val saved = subscriptionsRepository.loadSubscriptions(database.databaseId)

                saved.forEach { sub ->
                    runCatching {
                        val handle = ditto.sync.registerSubscription(sub.query)
                        activeHandles[sub.id] = handle
                    }
                }
                _subscriptions.value = saved
                val savedObservers = observableRepository.loadObservables(database.databaseId)
                _observers.value = savedObservers
            }.onFailure { e ->
                hydrateError = e.message
            }
        }
    }

    fun loadNetworkDiagnostics() {
        sessionScope.launch {
            _networkInterfaces.value = networkRepo.fetchInterfaces()
            _p2pTransports.value = networkRepo.fetchP2PTransports()
        }
    }

    fun toggleSync() {
        val ditto = dittoManager.currentInstance() ?: return
        sessionScope.launch {
            runCatching {
                if (ditto.sync.isActive) {
                    ditto.sync.stop()
                    _syncEnabled.value = false
                } else {
                    ditto.sync.start()
                    _syncEnabled.value = true
                }
            }
        }
    }

    fun addSubscription(name: String, query: String) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                val sub = DittoSubscription(databaseId = db.databaseId, name = name, query = query)
                val id = subscriptionsRepository.saveSubscription(sub)
                val handle = ditto.sync.registerSubscription(query)
                activeHandles[id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
        }
    }

    fun updateSubscription(subscription: DittoSubscription) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                activeHandles.remove(subscription.id)?.close()
                subscriptionsRepository.updateSubscription(subscription)
                val handle = ditto.sync.registerSubscription(subscription.query)
                activeHandles[subscription.id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
        }
    }

    fun removeSubscription(id: Long) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            activeHandles.remove(id)?.close()
            subscriptionsRepository.removeSubscription(id)
            _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
        }
    }

    // ── Observer CRUD ─────────────────────────────────────────────────────────

    fun addObserver(name: String, query: String) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                val obs = DittoObservable(databaseId = db.databaseId, name = name, query = query)
                observableRepository.saveObservable(obs)
                _observers.value = observableRepository.loadObservables(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
        }
    }

    fun updateObserver(observer: DittoObservable, name: String, query: String) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                activeObserverHandles.remove(observer.id)?.close()
                _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }
                val updated = observer.copy(name = name, query = query, isActive = false)
                observableRepository.updateObservable(updated)
                _observers.value = observableRepository.loadObservables(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
        }
    }

    fun removeObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            activeObserverHandles.remove(observer.id)?.close()
            observableRepository.removeObservable(observer.id)
            _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    // ── Observer lifecycle ────────────────────────────────────────────────────

    fun activateObserver(observer: DittoObservable) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        if (activeObserverHandles.containsKey(observer.id)) return

        val handle = ditto.store.registerObserver(observer.query) { queryResult, diff ->
            val docs = queryResult.items.map { it.jsonString() }

            val event = DittoObserveEvent(
                observeId = observer.id.toString(),
                data = docs,
                insertIndexes = diff.insertions.toList(),
                updatedIndexes = diff.updates.toList(),
                deletedIndexes = diff.deletions.toList(),
                movedIndexes = diff.moves.map { it.from to it.to },
                eventTime = java.time.Instant.now().toString(),
            )

            _observerEvents.update { it + event }
        }

        activeObserverHandles[observer.id] = handle
        sessionScope.launch {
            val updated = observer.copy(isActive = true, lastUpdated = System.currentTimeMillis())
            observableRepository.updateObservable(updated)
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    fun deactivateObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        activeObserverHandles.remove(observer.id)?.close()
        _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }

        sessionScope.launch {
            val updated = observer.copy(isActive = false)
            observableRepository.updateObservable(updated)
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    fun isObserverActive(observer: DittoObservable): Boolean =
        activeObserverHandles.containsKey(observer.id)

    fun observerEventsFor(observableId: Long): List<DittoObserveEvent> {
        val obsId = observableId.toString()
        return _observerEvents.value.filter { it.observeId == obsId }
    }

    fun addIndex(collection: String, fieldName: String) {
        sessionScope.launch {
            runCatching {
                collectionsRepository.createIndex(collection, fieldName)
            }.onFailure { e ->
                hydrateError = e.message
            }
        }
    }

    fun applyTransportSettings(bt: Boolean, lan: Boolean, wifiAware: Boolean) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        sessionScope.launch {
            _isApplyingTransport.value = true
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
            _transportBluetoothEnabled.value = bt
            _transportLanEnabled.value = lan
            _transportWifiAwareEnabled.value = wifiAware
            _isApplyingTransport.value = false
        }
    }

    /**
     * Tear down the session. Closes Ditto exactly once (subsequent calls are no-ops) and
     * cancels the session's own coroutine scope.
     *
     * Safe to call from non-suspending contexts (e.g. Koin's `onClose`): the underlying
     * `dittoManager.close()` is suspend, so we drive it via `runBlocking` on the session's
     * dispatcher — acceptable here because this runs once at session teardown.
     */
    fun close() {
        if (!closed.compareAndSet(false, true)) return

        // Stop observer subscriptions on the underlying repositories so any background work
        // they spawned can terminate before we cancel our own scope.
        runCatching { systemRepository.stopObserving() }
        runCatching { collectionsRepository.stopObserving() }

        // Release SDK handles synchronously — these are just resource releases, not suspending.
        activeHandles.values.forEach { runCatching { it.close() } }
        activeHandles.clear()
        _subscriptions.value = emptyList()
        activeObserverHandles.values.forEach { runCatching { it.close() } }
        activeObserverHandles.clear()
        _observers.value = emptyList()
        _observerEvents.value = emptyList()

        // Close the Ditto instance. `dittoManager.close()` is `suspend`, but it is called
        // exactly once here under the AtomicBoolean guard, so a brief blocking wait is fine.
        runCatching { runBlocking { dittoManager.close() } }
            .onFailure { e -> Log.w(TAG, "Error closing Ditto on session close: ${e.message}") }

        // Finally cancel the session scope so any in-flight launches are stopped.
        sessionScope.cancel()
    }

    /** Visible for tests — internal flag check. */
    internal fun isClosed(): Boolean = closed.get()

    companion object {
        private const val TAG = "StudioSession"

        /** Koin scope qualifier — see [com.costoda.dittoedgestudio.data.di.dataModule]. */
        const val SCOPE_QUALIFIER = "studio"

        /** Build the scope id used to look up / create the studio scope for a database. */
        fun scopeId(databaseId: Long): String = "studio:$databaseId"
    }
}

/**
 * UI-facing peers state. Moved out of MainStudioViewModel together with the [StudioSession]
 * that owns it so phones/tablets stay consistent.
 */
sealed class PeersUiState {
    object Initializing : PeersUiState()
    data class Active(
        val localPeer: LocalPeerInfo?,
        val remotePeers: List<SyncStatusInfo>,
    ) : PeersUiState()
}
