package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import com.ditto.kotlin.DittoLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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

    private val _appEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val appEntries: StateFlow<List<LogEntry>> = _appEntries.asStateFlow()

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
            }
        }
    }

    fun clearLive() {
        synchronized(liveBackingStoreLock) { liveBackingStore.clear() }
        _liveEntries.value = emptyList()
        _pendingNewEntriesCount.value = 0
        lastSnapshotSize = 0
    }

    fun clearHistorical() {
        _historicalEntries.value = emptyList()
    }

    fun clearApp() {
        loggingService.clearAllLogs()
        _appEntries.value = emptyList()
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

    private fun emitSnapshot() {
        val snapshot = synchronized(liveBackingStoreLock) {
            if (liveBackingStore.size > MAX_DISPLAYED_ENTRIES) {
                liveBackingStore.takeLast(MAX_DISPLAYED_ENTRIES)
            } else {
                liveBackingStore.toList()
            }
        }
        _liveEntries.value = snapshot
        lastSnapshotSize = synchronized(liveBackingStoreLock) { liveBackingStore.size }
        _pendingNewEntriesCount.value = 0
    }

    /** Returns the flow of DittoLogger events — exposed for testing. */
    internal fun dittoLogEventFlow(): Flow<com.ditto.kotlin.DittoLogger.DittoLogEvent> =
        DittoLogger.observeLogEvents()
}
