package com.costoda.dittoedgestudio.data.session

import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.ditto.DebugSocketClient
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
import com.costoda.dittoedgestudio.domain.model.IndexField
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.MeshTopology
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.ObserveEventStore
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.DittoStoreObserver
import com.ditto.kotlin.DittoSyncSubscription
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

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
    private val historyRepository: com.costoda.dittoedgestudio.data.repository.HistoryRepository,
    private val appPreferences: com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway,
    private val context: android.content.Context,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val teardownDispatcher: CoroutineDispatcher = Dispatchers.IO,
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
    // StateFlow-backed so Compose readers (e.g. the Query Metrics section's loading
    // gate in AppNavGraph) recompose when hydration completes or fails. The plain
    // [hydrateError] / [currentDittoId] getters remain as snapshot reads for
    // non-reactive callers (MainStudioViewModel's init gate, tests).
    private val _hydrateError = MutableStateFlow<String?>(null)
    val hydrateErrorFlow: StateFlow<String?> = _hydrateError.asStateFlow()
    val hydrateError: String? get() = _hydrateError.value

    private val _currentDittoId = MutableStateFlow<String?>(null)
    val currentDittoIdFlow: StateFlow<String?> = _currentDittoId.asStateFlow()
    val currentDittoId: String? get() = _currentDittoId.value

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

    // ── Welcome screen auto-show ─────────────────────────────────────────────
    /**
     * True after hydration when the database looks fresh (no subscriptions, no
     * query history) — the scaffold may then offer the Welcome tour, subject to
     * the user's "show on new database" preference. Set once per session.
     */
    private val _welcomeCandidate = MutableStateFlow(false)
    val welcomeCandidate: StateFlow<Boolean> = _welcomeCandidate.asStateFlow()
    private val welcomeAutoShown = AtomicBoolean(false)

    /**
     * Returns true exactly once per session when [welcomeCandidate] is set —
     * the caller then navigates to the Welcome screen. Prevents re-triggering
     * on rail-section switches or list/detail recomposition.
     */
    fun consumeWelcomeTrigger(): Boolean =
        _welcomeCandidate.value && welcomeAutoShown.compareAndSet(false, true)

    // ── system:metrics (SDK 5.1) dashboard ────────────────────────────────────
    // Parity port of the extension's SystemMetricsService: the virtual collection
    // flushes the registry per read, so samples accumulate deltas since connect.
    private val systemMetricSamples =
        java.util.Collections.synchronizedMap(mutableMapOf<String, com.costoda.dittoedgestudio.domain.model.SystemMetricSample>())

    private val _systemMetrics = MutableStateFlow(
        com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
            samples = emptyList(),
            status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.IDLE,
        ),
    )
    val systemMetrics: StateFlow<com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot> =
        _systemMetrics.asStateFlow()

    private var systemMetricsJob: Job? = null

    /**
     * Starts 5-second polling of `SELECT * FROM system:metrics`. Idempotent; call from
     * the dashboard's on-visible and [stopSystemMetricsPolling] on-hidden. When the
     * "Collect system metrics" setting is off, reports SETTING_DISABLED and stays idle
     * (the exporter is startup-gated — nothing to poll until the next open).
     */
    fun startSystemMetricsPolling() {
        if (systemMetricsJob?.isActive == true) return
        systemMetricsJob = sessionScope.launch {
            if (!appPreferences.collectSystemMetrics.first()) {
                _systemMetrics.value = com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
                    samples = emptyList(),
                    status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.SETTING_DISABLED,
                )
                return@launch
            }
            val sinceMs = System.currentTimeMillis()
            var zeroed = false
            while (true) {
                // Re-check per iteration (extension + Swift parity): hydrate() is async, so
                // arriving at the dashboard before it completes must recover automatically.
                val ditto = dittoManager.currentInstance()
                if (ditto == null) {
                    _systemMetrics.value = com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
                        samples = emptyList(),
                        status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.NO_CONNECTION,
                    )
                    delay(SYSTEM_METRICS_POLL_INTERVAL_MS)
                    continue
                }
                if (!zeroed) {
                    // First poll of a session: samples may predate us (shared session on
                    // section re-entry) — reset so "since connect" matches this open.
                    synchronized(systemMetricSamples) { systemMetricSamples.clear() }
                    zeroed = true
                }
                try {
                    val rows = ditto.store.execute(SYSTEM_METRICS_QUERY) { result ->
                        result.items.mapNotNull { item ->
                            runCatching {
                                com.costoda.dittoedgestudio.data.repository.parseJsonToMap(
                                    org.json.JSONObject(item.jsonString()),
                                )
                            }.getOrNull()
                        }
                    }
                    if (com.costoda.dittoedgestudio.domain.model.SystemMetricsAccumulator.isExporterDisabled(rows)) {
                        _systemMetrics.value = com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
                            samples = emptyList(),
                            status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.EXPORTER_DISABLED,
                        )
                    } else {
                        synchronized(systemMetricSamples) {
                            com.costoda.dittoedgestudio.domain.model.SystemMetricsAccumulator.accumulate(
                                rows,
                                samples = systemMetricSamples,
                            )
                        }
                        _systemMetrics.value = com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
                            samples = synchronized(systemMetricSamples) {
                                systemMetricSamples.values.toList().sortedBy { it.key }
                            },
                            status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.READY,
                            sinceMs = sinceMs,
                            polledAtMs = System.currentTimeMillis(),
                        )
                    }
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    _systemMetrics.value = com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot(
                        samples = emptyList(),
                        status = com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus.ERROR,
                        errorMessage = e.message,
                    )
                }
                delay(SYSTEM_METRICS_POLL_INTERVAL_MS)
            }
        }
    }

    fun stopSystemMetricsPolling() {
        systemMetricsJob?.cancel()
        systemMetricsJob = null
    }

    // ── Debug Console (SDK 5.1 debug_socket) ─────────────────────────────────
    // Parity with the extension's Debug Console: runtime `ALTER SYSTEM` spawns an
    // unauthenticated newline-DQL listener on a unix socket inside app-private
    // storage; the client is serial-FIFO with a 30 s timeout and a 64 MiB line cap.
    private val debugSocketClient = DebugSocketClient()

    /** True while the debug socket listener is up (set when the console opened). */
    private val _debugConsoleActive = MutableStateFlow(false)
    val debugConsoleActive: StateFlow<Boolean> = _debugConsoleActive.asStateFlow()

    private fun debugSocketPath(): String = java.io.File(context.cacheDir, "ditto-debug.sock").absolutePath

    /**
     * Enables the debug socket for this session's Ditto and connects the client.
     * Idempotent. Returns the socket path on success.
     */
    suspend fun openDebugConsole(): Result<String> {
        val ditto = dittoManager.currentInstance()
            ?: return Result.failure(IllegalStateException("No active Ditto instance"))
        return runCatching {
            val path = debugSocketPath()
            ditto.store.execute("ALTER SYSTEM SET debug_socket = '$path'")
            debugSocketClient.connect(path)
            _debugConsoleActive.value = true
            path
        }
    }

    /** Runs one DQL statement over the debug socket. Opens the console on demand. */
    suspend fun executeDebugStatement(statement: String): Result<String> {
        if (!_debugConsoleActive.value) {
            openDebugConsole().onFailure { return Result.failure(it) }
        }
        return runCatching { debugSocketClient.execute(statement) }
    }

    /** Closes the client and tears the listener down (listener dies with Ditto anyway). */
    suspend fun closeDebugConsole() {
        _debugConsoleActive.value = false
        debugSocketClient.closeAndWait()
        runCatching {
            dittoManager.currentInstance()
                ?.store?.execute("ALTER SYSTEM SET debug_socket = ''")
        }
    }

    /**
     * Bounded capture buffer (SwiftUI `ObservableEventStore` parity): events are
     * in-memory only and hard-capped at [ObserveEventStore.DEFAULT_CAPACITY] with
     * FIFO eviction so a hot observed query can't grow memory without bound.
     *
     * Threading: Ditto invokes observer callbacks on SDK-owned threads, the flush
     * job ticks on the multi-threaded session IO dispatcher, and purge paths run on
     * the caller's thread (main for deactivate). Every access to the store and the
     * pending deque therefore goes through [observerEventPipelineLock], and
     * drain-append-publish and pending-remove-store-remove-publish are each atomic
     * under it — otherwise a flush racing a purge could resurrect events for a
     * deactivated observer.
     */
    private val observeEventStore = ObserveEventStore()
    private val pendingObserverEvents = ArrayDeque<DittoObserveEvent>()
    private val observerEventPipelineLock = Any()

    /**
     * Coalescing flush (SwiftUI 100 ms `observedEventFlushInterval` parity): SDK
     * callbacks land in [pendingObserverEvents] and a single job drains them into
     * the store / StateFlow every [OBSERVER_EVENT_FLUSH_INTERVAL_MS] so a burst of
     * emissions produces one recomposition batch instead of one per event.
     * Runs only while at least one observer is active.
     */
    private var observerEventFlushJob: Job? = null

    private fun enqueueObserverEvent(event: DittoObserveEvent) {
        synchronized(observerEventPipelineLock) { pendingObserverEvents.addLast(event) }
    }

    private fun ensureObserverEventFlushRunning() {
        if (observerEventFlushJob?.isActive == true) return
        observerEventFlushJob = sessionScope.launch {
            while (true) {
                delay(OBSERVER_EVENT_FLUSH_INTERVAL_MS)
                flushPendingObserverEvents()
            }
        }
    }

    /** Stops the flush loop when no observer is active; drops nothing. */
    private fun stopObserverEventFlush() {
        observerEventFlushJob?.cancel()
        observerEventFlushJob = null
        flushPendingObserverEvents()
    }

    private fun flushPendingObserverEvents() {
        synchronized(observerEventPipelineLock) {
            if (pendingObserverEvents.isEmpty()) return
            observeEventStore.appendAll(pendingObserverEvents.toList())
            pendingObserverEvents.clear()
            _observerEvents.value = observeEventStore.events
        }
    }

    /** Removes [observeId]'s events from both the pending deque and the store. */
    private fun purgeObserverEvents(observeId: String) {
        synchronized(observerEventPipelineLock) {
            pendingObserverEvents.removeAll { it.observeId == observeId }
            observeEventStore.removeEventsForObserver(observeId)
            _observerEvents.value = observeEventStore.events
        }
    }

    private fun stopFlushWhenNoObserversActive() {
        if (activeObserverHandles.isEmpty()) stopObserverEventFlush()
    }

    // ── Collections / peers / connections ─────────────────────────────────────
    val collections: StateFlow<List<DittoCollection>> = collectionsRepository.collections
        .stateIn(sessionScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val peersUiState: StateFlow<PeersUiState> = combine(
        systemRepository.localPeer,
        systemRepository.peers,
        systemRepository.meshTopology,
    ) { local, remote, mesh ->
        PeersUiState.Active(localPeer = local, remotePeers = remote, meshTopology = mesh)
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
     * Guards against concurrent [hydrate] runs. Two MainStudioViewModel instances
     * (activity-store + Nav3 entry-store) can be constructed in the same composition
     * pass and both call [hydrate] from their `init`; without a guard both coroutines
     * would race DittoManager.hydrate on the same persistence directory.
     */
    private val hydrateMutex = Mutex()

    /**
     * Hydrate the Ditto instance for this session's [databaseId]. Idempotent in the sense that
     * a hydration failure leaves [hydrateError] set; callers may choose to surface it. Starts
     * system + collections observers and pre-registers persisted subscriptions.
     *
     * Concurrency: if a hydrate is already in flight, the second call waits for it to
     * finish and then returns WITHOUT re-running — the in-flight run already covers it.
     */
    fun hydrate() {
        sessionScope.launch {
            if (!hydrateMutex.tryLock()) {
                // Another hydrate is in flight — join it rather than racing a second
                // DittoManager.hydrate on the same persistence directory.
                hydrateMutex.lock()
                hydrateMutex.unlock()
                return@launch
            }
            try {
                _hydrateError.value = null
                runCatching {
                    // If a previous session for this databaseId is still closing Ditto on the
                    // teardown scope, wait for it to finish before opening the same persistence
                    // directory. Opening while the old instance still holds the file lock will
                    // fail; this guarantees reopen-after-close safety even with rapid re-entry.
                    DittoTeardownRegistry.awaitCloseFor(databaseId)

                    val database = databaseRepository.getById(databaseId)
                        ?: error("Database not found: $databaseId")
                    currentDatabase = database
                    _currentDittoId.value = database.databaseId

                    // Derive picker modes from credentials (mirrors SwiftUI QueryViewModel lines
                    // 86–98). HTTP only appears when both URL and key are non-blank. If the user's
                    // prior pick is no longer valid (e.g. credentials dropped mid-session), reset
                    // back to "Local" so the picker can't render a stale selection.
                    val modes = if (database.httpApiUrl.isBlank() || database.httpApiKey.isBlank()) {
                        listOf("Local")
                    } else {
                        listOf("Local", "HTTP")
                    }
                    uiState.queryWorkbench.executeModes.value = modes
                    if (uiState.queryWorkbench.executeMode.value !in modes) {
                        uiState.queryWorkbench.executeMode.value = "Local"
                    }

                    _transportBluetoothEnabled.value = database.isBluetoothLeEnabled
                    _transportLanEnabled.value = database.isLanEnabled
                    _transportWifiAwareEnabled.value = database.isAwdlEnabled
                    _transportCloudSyncEnabled.value = database.isCloudSyncEnabled

                    val ditto = dittoManager.hydrate(database)
                    systemRepository.startObserving(ditto)
                    collectionsRepository.startObserving(ditto)
                    // SwiftUI parity: DittoManager starts the log-only transport-condition
                    // collector and the (auto-allow) connection-request handler on open.
                    loggingCaptureService.startTransportConditionObservation(ditto)
                    loggingCaptureService.startConnectionRequestHandler(ditto)
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

                    // Welcome auto-show eligibility (SwiftUI MainStudioViewModel.performLoad
                    // parity): a fresh database has no subscriptions and no query history.
                    // The UI layer still gates on the "show on new database" preference.
                    _welcomeCandidate.value =
                        saved.isEmpty() && historyRepository.loadHistory(database.databaseId).isEmpty()
                }.onFailure { e ->
                    _hydrateError.value = e.message
                }
            } finally {
                hydrateMutex.unlock()
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
                    // Re-run the full open sequence rather than a bare sync.start():
                    // ALTER SYSTEM state is in-memory, so scopes and startup settings
                    // must be re-applied and re-verified on every sync start (a query
                    // editor `ALTER SYSTEM RESET ALL` could have cleared them).
                    dittoManager.startSync()
                    _syncEnabled.value = true
                }
            }
        }
    }

    /**
     * Suspends until the subscription is written to Room. The Room write itself runs
     * under [NonCancellable] so a fast back-tap by the user can never race the
     * editor's coroutine and lose data — even if the caller's scope is cancelled
     * mid-flight, the persisted record still lands.
     *
     * Returns a [Result] so the caller (the editor sheet) can decide whether to
     * dismiss or surface an error.
     */
    suspend fun addSubscriptionSuspend(name: String, query: String): Result<Unit> {
        val ditto = dittoManager.currentInstance()
            ?: return Result.failure(IllegalStateException("Ditto instance not ready"))
        val db = currentDatabase
            ?: return Result.failure(IllegalStateException("Database not hydrated"))
        return withContext(NonCancellable + ioDispatcher) {
            runCatching {
                val sub = DittoSubscription(databaseId = db.databaseId, name = name, query = query)
                val id = subscriptionsRepository.saveSubscription(sub)
                val handle = ditto.sync.registerSubscription(query)
                activeHandles[id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
                Unit
            }.onFailure { e ->
                // Gated: the SDK error can embed the user's subscription DQL.
                // Never write save failures to _hydrateError: that channel is
                // reserved for open-failure and gates the Query Metrics
                // section. The returned Result surfaces the error inline.
                if (BuildConfig.DEBUG) {
                    Log.e(TAG, "addSubscriptionSuspend failed: ${e.message}", e)
                }
            }
        }
    }

    suspend fun updateSubscriptionSuspend(subscription: DittoSubscription): Result<Unit> {
        val ditto = dittoManager.currentInstance()
            ?: return Result.failure(IllegalStateException("Ditto instance not ready"))
        val db = currentDatabase
            ?: return Result.failure(IllegalStateException("Database not hydrated"))
        return withContext(NonCancellable + ioDispatcher) {
            runCatching {
                activeHandles.remove(subscription.id)?.close()
                subscriptionsRepository.updateSubscription(subscription)
                val handle = ditto.sync.registerSubscription(subscription.query)
                activeHandles[subscription.id] = handle
                _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
                Unit
            }.onFailure { e ->
                // Surfaced via the returned Result — see addSubscriptionSuspend.
                if (BuildConfig.DEBUG) {
                    Log.e(TAG, "updateSubscriptionSuspend failed: ${e.message}", e)
                }
            }
        }
    }

    fun removeSubscription(id: Long) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            activeHandles.remove(id)?.close()
            withContext(NonCancellable) {
                subscriptionsRepository.removeSubscription(id)
            }
            _subscriptions.value = subscriptionsRepository.loadSubscriptions(db.databaseId)
        }
    }

    // ── Observer CRUD ─────────────────────────────────────────────────────────

    fun addObserver(name: String, query: String) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                val obs = DittoObservable(databaseId = db.databaseId, name = name, query = query)
                // Same data-loss-on-back-tap concern as addSubscription — keep the
                // Room write under NonCancellable.
                withContext(NonCancellable) {
                    observableRepository.saveObservable(obs)
                }
                _observers.value = observableRepository.loadObservables(db.databaseId)
            }.onFailure { e ->
                // Never via _hydrateError (reserved for open-failure) — see
                // addSubscriptionSuspend.
                if (BuildConfig.DEBUG) {
                    Log.e(TAG, "addObserver failed: ${e.message}", e)
                }
            }
        }
    }

    fun updateObserver(observer: DittoObservable, name: String, query: String) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            runCatching {
                activeObserverHandles.remove(observer.id)?.close()
                purgeObserverEvents(observer.id.toString())
                stopFlushWhenNoObserversActive()
                val updated = observer.copy(name = name, query = query, isActive = false)
                withContext(NonCancellable) {
                    observableRepository.updateObservable(updated)
                }
                _observers.value = observableRepository.loadObservables(db.databaseId)
            }.onFailure { e ->
                // Never via _hydrateError (reserved for open-failure) — see
                // addSubscriptionSuspend.
                if (BuildConfig.DEBUG) {
                    Log.e(TAG, "updateObserver failed: ${e.message}", e)
                }
            }
        }
    }

    fun removeObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        sessionScope.launch {
            activeObserverHandles.remove(observer.id)?.close()
            withContext(NonCancellable) {
                observableRepository.removeObservable(observer.id)
            }
            purgeObserverEvents(observer.id.toString())
            stopFlushWhenNoObserversActive()
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    // ── Observer lifecycle ────────────────────────────────────────────────────

    fun activateObserver(observer: DittoObservable) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        if (activeObserverHandles.containsKey(observer.id)) return

        val handle = ditto.store.registerObserver(observer.query) { queryResult, diff ->
            // Serialize defensively per document (SwiftUI parity: skip a bad doc
            // rather than let one failure kill the observer callback).
            val docs = queryResult.items.mapNotNull { item ->
                runCatching { item.jsonString() }.getOrNull()
            }

            val event = DittoObserveEvent(
                observeId = observer.id.toString(),
                data = docs,
                insertIndexes = diff.insertions.toList(),
                updatedIndexes = diff.updates.toList(),
                deletedIndexes = diff.deletions.toList(),
                movedIndexes = diff.moves.map { it.from to it.to },
                eventTime = java.time.Instant.now().toString(),
            )

            enqueueObserverEvent(event)
        }

        activeObserverHandles[observer.id] = handle
        ensureObserverEventFlushRunning()
        sessionScope.launch {
            val updated = observer.copy(isActive = true, lastUpdated = System.currentTimeMillis())
            observableRepository.updateObservable(updated)
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    fun deactivateObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        activeObserverHandles.remove(observer.id)?.close()
        purgeObserverEvents(observer.id.toString())
        stopFlushWhenNoObserversActive()

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

    /**
     * Creates an index and returns the result so callers (e.g. the Add Index sheet)
     * can surface failures inline. Runs on the session scope's IO dispatcher.
     *
     * [CancellationException] is rethrown rather than wrapped in the [Result]: a
     * cancelled call (caller left composition, or this session's scope was cancelled
     * by [close]) is not a "failed to create index" outcome, and wrapping it would
     * both misreport it and break structured cancellation.
     */
    suspend fun addIndex(collection: String, fields: List<IndexField>): Result<Unit> =
        withContext(sessionScope.coroutineContext) {
            try {
                collectionsRepository.createIndex(collection, fields)
                Result.success(Unit)
            } catch (ce: CancellationException) {
                throw ce
            } catch (e: Exception) {
                Result.failure(e)
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

                // 3. Persist to Room so settings survive app restart, and keep the
                // manager's active config current so the restart re-applies the new
                // transports rather than the ones the database was opened with.
                databaseRepository.save(updatedDb)
                currentDatabase = updatedDb
                dittoManager.refreshActiveConfigIfMatching(updatedDb)

                // 4. Restart sync through the DittoManager funnel — every sync start
                // re-applies and re-verifies the advanced configuration — then
                // re-register observers.
                dittoManager.startSync()
                systemRepository.startObserving(ditto)
            }.onFailure { e ->
                if (BuildConfig.DEBUG) {
                    Log.w(TAG, "applyTransportSettings failed: ${e.message}", e)
                }
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
     * Safe to call from the main thread (e.g. Koin's `onClose` fired from
     * `DisposableEffect.onDispose`): the fast synchronous portion (handle releases,
     * StateFlow resets) runs inline, but the suspending `dittoManager.close()` is dispatched
     * to [DittoTeardownRegistry] on [teardownDispatcher] — a process-wide supervisor scope
     * that survives this session's own scope cancellation. The resulting [Job] is registered
     * by [databaseId] so that a subsequent `hydrate()` for the same database can `join()` it
     * before opening, eliminating the file-lock race on rapid re-entry.
     */
    fun close() {
        if (!closed.compareAndSet(false, true)) return

        // Stop observer subscriptions on the underlying repositories so any background work
        // they spawned can terminate before we cancel our own scope.
        runCatching { systemRepository.stopObserving() }
        runCatching { collectionsRepository.stopObserving() }
        runCatching { loggingCaptureService.stopTransportConditionObservation() }
        runCatching { loggingCaptureService.stopConnectionRequestHandler() }
        stopSystemMetricsPolling()
        runCatching { debugSocketClient.close() }
        _debugConsoleActive.value = false

        // Release SDK handles synchronously — these are just resource releases, not suspending.
        activeHandles.values.forEach { runCatching { it.close() } }
        activeHandles.clear()
        _subscriptions.value = emptyList()
        activeObserverHandles.values.forEach { runCatching { it.close() } }
        activeObserverHandles.clear()
        _observers.value = emptyList()
        observerEventFlushJob?.cancel()
        observerEventFlushJob = null
        synchronized(observerEventPipelineLock) {
            pendingObserverEvents.clear()
            observeEventStore.clear()
            _observerEvents.value = emptyList()
        }

        // Dispatch the suspending Ditto close to the teardown registry. We MUST NOT run it on
        // `sessionScope` (cancelled below) or block the calling (main) thread (ANR risk).
        DittoTeardownRegistry.launchClose(
            databaseId = databaseId,
            dispatcher = teardownDispatcher,
        ) {
            // NonCancellable: even if the registry's job is cancelled by something exotic, the
            // native Ditto release must complete to free the persistence-directory lock.
            withContext(NonCancellable) {
                // dittoManager.close() must be invoked exactly ONCE — a timed-out native close
                // keeps running, so retrying would race two concurrent closes on one handle.
                // The timeout therefore wraps a join() on a child job (cancelling a join never
                // cancels the job), giving us the slow-close warning without a second close.
                val closeJob = launch {
                    runCatching { dittoManager.close() }
                        .onFailure { e ->
                            if (BuildConfig.DEBUG) {
                                Log.w(TAG, "Error closing Ditto on session close: ${e.message}")
                            }
                        }
                }
                val completedInTime = withTimeoutOrNull(CLOSE_WARN_TIMEOUT_MS) { closeJob.join() }
                if (completedInTime == null) {
                    if (BuildConfig.DEBUG) {
                        Log.w(
                            TAG,
                            "Ditto close exceeded ${CLOSE_WARN_TIMEOUT_MS}ms for databaseId=$databaseId; " +
                                "continuing to wait without abandoning the close.",
                        )
                    }
                    closeJob.join()
                }
            }
        }

        // Finally cancel the session scope so any in-flight launches are stopped. The teardown
        // job lives on its own supervisor scope and is unaffected by this cancellation.
        sessionScope.cancel()
    }

    /** Visible for tests — internal flag check. */
    internal fun isClosed(): Boolean = closed.get()

    companion object {
        private const val TAG = "StudioSession"

        /** SwiftUI `observedEventFlushInterval` parity (100 ms event coalescing). */
        private const val OBSERVER_EVENT_FLUSH_INTERVAL_MS = 100L

        /** `system:metrics` poll cadence (extension parity: 5 s while visible). */
        private const val SYSTEM_METRICS_POLL_INTERVAL_MS = 5_000L
        private const val SYSTEM_METRICS_QUERY = "SELECT * FROM system:metrics"

        /** WARN threshold for slow Ditto teardown; we still wait for completion past this. */
        private const val CLOSE_WARN_TIMEOUT_MS: Long = 5_000L

        /** Koin scope qualifier — see [com.costoda.dittoedgestudio.data.di.dataModule]. */
        const val SCOPE_QUALIFIER = "studio"

        /** Build the scope id used to look up / create the studio scope for a database. */
        fun scopeId(databaseId: Long): String = "studio:$databaseId"
    }
}

/**
 * Process-wide registry of in-flight Ditto teardown jobs, keyed by databaseId.
 *
 * Why a registry: when the user exits the studio, Koin's scope `onClose` fires on the main
 * thread from `DisposableEffect.onDispose`. The native `Ditto.close()` call must NOT block
 * that thread (ANR risk) and must NOT run on the session's own scope (which we cancel in the
 * same call). But the user can immediately re-enter the same database — a fresh
 * [StudioSession] will then try to open the same persistence directory while the previous
 * native instance is still releasing its file lock. This registry lets the new session
 * `await()` the in-flight close for its databaseId before opening, eliminating the race
 * without re-introducing a blocking call on the main thread.
 *
 * The registry uses an internal `SupervisorJob` so a failed teardown doesn't poison sibling
 * databaseId teardowns, and `Dispatchers.IO` for the close work itself (overridable per-call
 * for tests via the [dispatcher] parameter to [launchClose]).
 */
internal object DittoTeardownRegistry {
    private val supervisor = SupervisorJob()
    private val inFlight = ConcurrentHashMap<Long, Job>()

    /**
     * Launch a teardown [block] for [databaseId] on a scope that survives any caller-scope
     * cancellation. The returned [Job] is registered (and auto-removed on completion) so
     * [awaitCloseFor] can join it from a fresh session's hydrate path.
     */
    fun launchClose(
        databaseId: Long,
        dispatcher: CoroutineDispatcher,
        block: suspend () -> Unit,
    ): Job {
        val scope = CoroutineScope(supervisor + dispatcher)
        val job = scope.launch { block() }
        inFlight[databaseId] = job
        job.invokeOnCompletion { inFlight.remove(databaseId, job) }
        return job
    }

    /** Suspend until any in-flight teardown for [databaseId] completes; no-op otherwise. */
    suspend fun awaitCloseFor(databaseId: Long) {
        inFlight[databaseId]?.join()
    }

    /** Visible for tests — exposes the in-flight job for direct assertions. */
    internal fun inFlightJob(databaseId: Long): Job? = inFlight[databaseId]
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
        val meshTopology: MeshTopology = MeshTopology.Empty,
    ) : PeersUiState()
}
