package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConnectionRequestAuthorization
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import com.ditto.kotlin.DittoPresence
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import java.util.Date
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Three-layer log capture service with performance safeguards against high-volume SDK logging.
 *
 * Layer 1 — Ingestion (lock-free ConcurrentLinkedDeque, SDK callback thread safe)
 * Layer 2 — Backing store (ArrayDeque on Dispatchers.IO, drained every 250ms)
 * Layer 3 — Display StateFlow (snapshot on Dispatchers.Default, at most every 500ms)
 */
class DittoLogCaptureService(
    private val loggingService: LoggingService,
    private val scope: CoroutineScope,
) {
    companion object {
        internal const val MAX_RAW_PENDING = 2_000
        internal const val EAGER_DRAIN_THRESHOLD = 500
        internal const val MAX_DRAIN_PER_CYCLE = 500
        internal const val FLUSH_INTERVAL_MS = 250L
        internal const val DISPLAY_REFRESH_MS = 500L
        internal const val MAX_LIVE_ENTRIES = 10_000
        internal const val MAX_HISTORICAL_ENTRIES = 10_000
        internal const val MAX_APP_ENTRIES = 5_000
        internal const val MAX_TRANSPORT_ENTRIES = 5_000
        internal const val MAX_CONNECTION_REQUEST_ENTRIES = 5_000
        /**
     * Cap on **rendered rows**, applied by `LoggingScreen` after filtering.
     *
     * It is deliberately *not* applied to [liveEntries]. Publishing only the
     * newest 200 entries used to mean every number on the Logging screen —
     * badges, both histograms, connection durations, tags, the time range, the
     * context slice — was computed over at most 200 live lines while the store
     * held up to [MAX_LIVE_ENTRIES]. It also silently neutralised pairing
     * connection sessions "over the full buffer", because the full buffer the UI
     * could see *was* 200 lines, and it made the [bufferNearlyFull] /
     * [entriesDropped] banners describe a store the UI never read.
     *
     * The row cap belongs at the display layer; the data source publishes
     * everything it retains.
     */
    internal const val MAX_DISPLAYED_ENTRIES = 200
    }

    // ── Layer 1: lock-free raw event buffer ──────────────────────────────────
    private data class RawEvent(val level: DittoLogLevel, val message: String)

    private val rawPendingBuffer = ConcurrentLinkedDeque<RawEvent>()
    private val droppedCount = AtomicInteger(0)

    // ── Layer 2: backing store ────────────────────────────────────────────────
    private val liveBackingStore = ArrayDeque<LogEntry>()
    private val liveBackingStoreLock = Any()
    private var displayNeedsRefresh = false

    // ── Layer 3: display StateFlows ───────────────────────────────────────────
    private val _liveEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val liveEntries: StateFlow<List<LogEntry>> = _liveEntries.asStateFlow()

    private val _historicalEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val historicalEntries: StateFlow<List<LogEntry>> = _historicalEntries.asStateFlow()

    /**
     * [historicalEntries] and [liveEntries] merged into one chronological stream
     * — the population the SDK tab analyses.
     *
     * Merged **here**, on a background dispatcher, rather than in a
     * `derivedStateOf` in the composable. Both inputs are already sorted, so this
     * is a linear two-pointer merge rather than a sort, and it now runs over up
     * to [MAX_HISTORICAL_ENTRIES] + [MAX_LIVE_ENTRIES] = 20 000 entries every
     * time [emitSnapshot] publishes (twice a second while capturing). Walking and
     * allocating a list that size at that rate on the composition thread is
     * exactly the kind of thing that makes the screen janky; `conflate()` also
     * lets the merge drop intermediate buffers when publishing outruns it, which
     * a `derivedStateOf` cannot do.
     */
    val sdkEntries: StateFlow<List<LogEntry>> =
        combine(_historicalEntries, _liveEntries) { historical, live ->
            mergeByTimestamp(historical, live)
        }
            .conflate()
            .flowOn(Dispatchers.Default)
            .stateIn(scope, SharingStarted.Eagerly, emptyList())

    private val _appEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val appEntries: StateFlow<List<LogEntry>> = _appEntries.asStateFlow()

    // Transport-condition stream (SwiftUI .transportConditions source parity).
    private val _transportConditionEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val transportConditionEntries: StateFlow<List<LogEntry>> = _transportConditionEntries.asStateFlow()

    // Connection-request stream (SwiftUI .connectionRequests source parity).
    private val _connectionRequestEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val connectionRequestEntries: StateFlow<List<LogEntry>> = _connectionRequestEntries.asStateFlow()
    private var transportConditionJob: Job? = null
    private var connectionRequestDitto: Ditto? = null

    /**
     * Monotonic counter that advances **every time any capture stream's content
     * changes** — a live snapshot publish, a transport-condition or
     * connection-request append, a historical/app reload, or a clear.
     *
     * It exists because list **size** is not a usable change key. Every stream
     * here is a ring buffer trimmed to an exact cap ([MAX_LIVE_ENTRIES] and
     * friends), so once a capture is at cap the size is pinned forever while the
     * contents keep churning. A `snapshotFlow { … entries.size }` in the UI is
     * distinct-until-changed, so it emits once on reaching the cap and then never
     * again: the pattern scan, the analytics, both histograms and every badge
     * freeze at the moment the buffer fills — precisely when a high-volume
     * capture most needs them. (SwiftUI does not hit this because it trims with a
     * 512-entry slack margin, so its count oscillates.)
     *
     * Consumers that need to re-run work when the log content changes must key on
     * this value, not on a collection size. The measured behaviour is pinned by
     * `DittoLogCaptureServiceTest` — "live buffer size pins at the cap while
     * content keeps changing" and "ingestSequence advances after the cap where
     * size does not".
     */
    private val _ingestSequence = MutableStateFlow(0L)
    val ingestSequence: StateFlow<Long> = _ingestSequence.asStateFlow()

    private fun bumpIngestSequence() {
        _ingestSequence.update { it + 1 }
    }

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _pendingNewEntriesCount = MutableStateFlow(0)
    val pendingNewEntriesCount: StateFlow<Int> = _pendingNewEntriesCount.asStateFlow()

    private val _bufferNearlyFull = MutableStateFlow(false)
    val bufferNearlyFull: StateFlow<Boolean> = _bufferNearlyFull.asStateFlow()

    private val _entriesDropped = MutableStateFlow(false)
    val entriesDropped: StateFlow<Boolean> = _entriesDropped.asStateFlow()

    /** Set to true by the UI when the user scrolls away from the bottom. */
    @Volatile var isLivePaused: Boolean = false

    private val _isCapturing = AtomicBoolean(false)
    private var collectionJob: Job? = null
    private var drainJob: Job? = null
    private var displayJob: Job? = null
    private var lastSnapshotSize = 0

    // ── Public API ────────────────────────────────────────────────────────────

    fun startLiveCapture() {
        if (!_isCapturing.compareAndSet(false, true)) return

        rawPendingBuffer.clear()
        synchronized(liveBackingStoreLock) { liveBackingStore.clear() }
        _liveEntries.value = emptyList()
        _pendingNewEntriesCount.value = 0
        droppedCount.set(0)
        _bufferNearlyFull.value = false
        _entriesDropped.value = false
        displayNeedsRefresh = false
        lastSnapshotSize = 0
        bumpIngestSequence()

        collectionJob = scope.launch(Dispatchers.IO) {
            collectDittoEvents()
        }
        drainJob = scope.launch(Dispatchers.IO) {
            startDrainLoop()
        }
        displayJob = scope.launch(Dispatchers.Default) {
            startDisplayLoop()
        }
    }

    fun stopLiveCapture() {
        if (!_isCapturing.compareAndSet(true, false)) return
        collectionJob?.cancel()
        drainJob?.cancel()
        displayJob?.cancel()
        collectionJob = null
        drainJob = null
        displayJob = null
        // Drain remaining raw events into backing store before stopping
        drainRawBuffer()
        emitSnapshot()
    }

    fun loadHistoricalLogs(cacheDir: File) {
        scope.launch(Dispatchers.IO) {
            _isLoading.value = true
            runCatching {
                // Export gzip JSONL from Ditto's internal logger
                val tempFile = File(cacheDir, "ditto_export_${System.currentTimeMillis()}.jsonl.gz")
                try {
                    if (tempFile.exists()) tempFile.delete()
                    cacheDir.mkdirs()
                    DittoLogger.exportToFile(tempFile.absolutePath)
                    val entries = LogFileParser.parseGzipJsonlFile(tempFile)
                    val trimmed = if (entries.size > MAX_HISTORICAL_ENTRIES) {
                        entries.takeLast(MAX_HISTORICAL_ENTRIES)
                    } else {
                        entries
                    }
                    _historicalEntries.value = trimmed
                    bumpIngestSequence()
                } finally {
                    runCatching { tempFile.delete() }
                }
            }
            _isLoading.value = false
        }
    }

    fun loadAppLogs() {
        scope.launch(Dispatchers.IO) {
            runCatching {
                val logsDir = loggingService.getLogsDirectory()
                val entries = LogFileParser.parseDirectory(logsDir)
                val trimmed = if (entries.size > MAX_APP_ENTRIES) {
                    entries.takeLast(MAX_APP_ENTRIES)
                } else {
                    entries
                }
                _appEntries.value = trimmed
                bumpIngestSequence()
            }
        }
    }

    fun clearLive() {
        synchronized(liveBackingStoreLock) { liveBackingStore.clear() }
        _liveEntries.value = emptyList()
        _pendingNewEntriesCount.value = 0
        lastSnapshotSize = 0
        bumpIngestSequence()
    }

    fun clearHistorical() {
        _historicalEntries.value = emptyList()
        bumpIngestSequence()
    }

    fun clearApp() {
        loggingService.clearAllLogs()
        _appEntries.value = emptyList()
        bumpIngestSequence()
    }

    fun clearTransportConditions() {
        _transportConditionEntries.value = emptyList()
        bumpIngestSequence()
    }

    fun clearConnectionRequests() {
        _connectionRequestEntries.value = emptyList()
        bumpIngestSequence()
    }

    // ── Transport conditions (SwiftUI DittoDelegate parity) ─────────────────

    /**
     * Collects `Ditto.transportCondition` events into the transport-conditions
     * log tab. Idempotent per Ditto instance (Swift's `observedDitto !== ditto`
     * guard).
     */
    fun startTransportConditionObservation(ditto: Ditto) {
        if (transportConditionJob?.isActive == true) return
        transportConditionJob = scope.launch(Dispatchers.IO) {
            ditto.transportCondition.collect { event ->
                val msg = "Transport: ${event.subsystem} → ${event.condition}"
                val entry = LogEntry(
                    timestamp = Date(),
                    level = DittoLogLevel.Info,
                    message = msg,
                    component = LogComponent.TRANSPORT,
                    source = LogEntrySource.TransportConditions,
                    rawLine = msg,
                )
                _transportConditionEntries.update { current ->
                    (current + entry).let {
                        if (it.size > MAX_TRANSPORT_ENTRIES) it.takeLast(MAX_TRANSPORT_ENTRIES) else it
                    }
                }
                bumpIngestSequence()
            }
        }
    }

    fun stopTransportConditionObservation() {
        transportConditionJob?.cancel()
        transportConditionJob = null
        _transportConditionEntries.value = emptyList()
    }

    // ── Connection requests (SwiftUI presence.connectionRequestHandler parity) ─

    /**
     * Installs a log-only connection request handler on the Ditto instance —
     * every incoming connection is unconditionally accepted.
     */
    fun startConnectionRequestHandler(ditto: Ditto) {
        if (connectionRequestDitto === ditto) return
        connectionRequestDitto = ditto
        ditto.presence.connectionRequestHandler = DittoPresence.ConnectionRequestHandler { request ->
            val msg = "Connection Request | type=${request.connectionType} | key=${request.peerKey}" +
                " | identity=${request.identityServiceMetadataJsonString.ifBlank { "none" }}" +
                " | meta=${request.peerMetadataJsonString.ifBlank { "none" }}"
            val entry = LogEntry(
                timestamp = Date(),
                level = DittoLogLevel.Info,
                message = msg,
                component = LogComponent.AUTH,
                source = LogEntrySource.ConnectionRequests,
                rawLine = msg,
            )
            _connectionRequestEntries.update { current ->
                (current + entry).let {
                    if (it.size > MAX_CONNECTION_REQUEST_ENTRIES) it.takeLast(MAX_CONNECTION_REQUEST_ENTRIES) else it
                }
            }
            bumpIngestSequence()
            DittoConnectionRequestAuthorization.Allow
        }
    }

    fun stopConnectionRequestHandler() {
        connectionRequestDitto?.presence?.connectionRequestHandler = null
        connectionRequestDitto = null
        _connectionRequestEntries.value = emptyList()
    }

    fun resetPendingCount() {
        _pendingNewEntriesCount.value = 0
        lastSnapshotSize = synchronized(liveBackingStoreLock) { liveBackingStore.size }
    }

    /** Called from DittoManager when a log event is received from the observeLogEvents() Flow. */
    internal fun onLiveDittoEvent(level: DittoLogLevel, message: String) {
        // Layer 1: drop oldest if buffer is full (lock-free)
        if (rawPendingBuffer.size >= MAX_RAW_PENDING) {
            rawPendingBuffer.poll()
            droppedCount.incrementAndGet()
            if (!_entriesDropped.value) _entriesDropped.value = true
        }
        rawPendingBuffer.addLast(RawEvent(level, message))

        // Eager drain if buffer is getting large
        if (rawPendingBuffer.size >= EAGER_DRAIN_THRESHOLD) {
            scope.launch(Dispatchers.IO) { drainRawBuffer() }
        }
    }

    // ── Internal pipeline ─────────────────────────────────────────────────────

    private suspend fun collectDittoEvents() {
        try {
            DittoLogger.observeLogEvents().collect { event ->
                onLiveDittoEvent(event.level, event.message)
            }
        } catch (_: Exception) {
            // Collection cancelled or SDK exception — stop gracefully
        }
    }

    private suspend fun startDrainLoop() {
        while (_isCapturing.get()) {
            delay(FLUSH_INTERVAL_MS)
            drainRawBuffer()
        }
    }

    private suspend fun startDisplayLoop() {
        while (_isCapturing.get()) {
            delay(DISPLAY_REFRESH_MS)
            if (!displayNeedsRefresh) continue
            displayNeedsRefresh = false

            val currentSize = synchronized(liveBackingStoreLock) { liveBackingStore.size }
            _bufferNearlyFull.value = currentSize > (MAX_LIVE_ENTRIES * 0.9).toInt()

            if (isLivePaused) {
                val newEntries = currentSize - lastSnapshotSize
                if (newEntries > 0) {
                    _pendingNewEntriesCount.value += newEntries
                    lastSnapshotSize = currentSize
                }
                continue
            }
            emitSnapshot()
        }
    }

    internal fun drainRawBuffer() {
        val batch = mutableListOf<RawEvent>()
        repeat(MAX_DRAIN_PER_CYCLE) {
            batch.add(rawPendingBuffer.poll() ?: return@repeat)
        }
        if (batch.isEmpty()) return

        val parsed = batch.map { raw ->
            LogEntry(
                id = UUID.randomUUID(),
                timestamp = Date(),
                level = raw.level,
                message = raw.message,
                component = LogComponent.heuristic(raw.message),
                source = LogEntrySource.DittoSDK,
                rawLine = "${raw.level.name}|${raw.message}",
            )
        }

        synchronized(liveBackingStoreLock) {
            liveBackingStore.addAll(parsed)
            while (liveBackingStore.size > MAX_LIVE_ENTRIES) {
                liveBackingStore.removeFirst()
            }
        }
        displayNeedsRefresh = true
    }

    /**
     * Publishes the **whole** retained backing store, not the newest
     * [MAX_DISPLAYED_ENTRIES] — see that constant for what truncating here broke.
     * Runs at most once per [DISPLAY_REFRESH_MS] and only when new entries
     * actually arrived, so the copy is bounded to twice a second while capturing.
     *
     * `internal` rather than private so tests can drive it without running the
     * display loop — the previous cap assertion passed vacuously because nothing
     * ever published.
     */
    internal fun emitSnapshot() {
        val snapshot = synchronized(liveBackingStoreLock) {
            lastSnapshotSize = liveBackingStore.size
            liveBackingStore.toList()
        }
        _liveEntries.value = snapshot
        _pendingNewEntriesCount.value = 0
        bumpIngestSequence()
    }

    /** Returns the flow of DittoLogger events — exposed for testing. */
    internal fun dittoLogEventFlow(): Flow<com.ditto.kotlin.DittoLogger.DittoLogEvent> =
        DittoLogger.observeLogEvents()

    /**
     * Linear merge of two lists that are each already in timestamp order — the
     * shape both inputs always have. `(a + b).sortedBy { it.timestamp }` would
     * box a `Date` comparison per element and hand TimSort a 20 000-element
     * array to discover the same two runs; this walks it once.
     *
     * Ties keep the left (historical) entry first, matching `sortedBy`'s
     * stability, so the ordering is unchanged from the previous implementation.
     */
    internal fun mergeByTimestamp(left: List<LogEntry>, right: List<LogEntry>): List<LogEntry> {
        if (left.isEmpty()) return right
        if (right.isEmpty()) return left
        val out = ArrayList<LogEntry>(left.size + right.size)
        var i = 0
        var j = 0
        while (i < left.size && j < right.size) {
            if (right[j].timestamp.time < left[i].timestamp.time) out.add(right[j++]) else out.add(left[i++])
        }
        while (i < left.size) out.add(left[i++])
        while (j < right.size) out.add(right[j++])
        return out
    }
}
