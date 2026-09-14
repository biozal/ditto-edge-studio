import DittoSwift
import Foundation

/// Manages all log sources: live Ditto SDK callback, historical file parsing, app logs, and external imports.
///
/// This service is `@Observable` and must be accessed from the main actor.
/// It also conforms to `DittoDelegate` to receive transport condition callbacks.
@Observable
@MainActor
final class DittoLogCaptureService: DittoDelegate {
    static let shared = DittoLogCaptureService()

    // MARK: - Published State

    private(set) var liveEntries: [LogEntry] = []
    private(set) var historicalEntries: [LogEntry] = []
    private(set) var appEntries: [LogEntry] = []
    private(set) var importedEntries: [LogEntry] = []
    private(set) var importedLabel = ""
    private(set) var isLoading = false
    private(set) var transportEntries: [LogEntry] = []
    private(set) var connectionRequestEntries: [LogEntry] = []

    /// Persists the selected Logging source tab across navigation.
    var selectedSource: LoggingSourceTab = .dittoSDK

    // MARK: - Constants

    private let maxLiveEntries = 10000
    private let maxHistoricalEntries = 10000
    private let maxAppEntries = 5000
    private let maxTransportEntries = 5000
    private let maxConnectionRequestEntries = 5000

    // MARK: - Live Batch Flush

    /// Thread-safe buffer written directly on the Ditto SDK callback thread.
    /// The callback appends here instead of spawning a `Task { @MainActor }`
    /// per log line, so a chatty SDK can't flood the main-actor executor;
    /// a single MainActor flush is scheduled per 250ms batch window.
    @ObservationIgnored
    private nonisolated let liveBuffer = LiveLogBuffer()

    // MARK: - Transport Condition Batch Flush

    @ObservationIgnored private var observedDitto: Ditto?
    @ObservationIgnored private var pendingTransportEntries: [LogEntry] = []
    @ObservationIgnored private var transportFlushTask: Task<Void, Never>?

    // MARK: - Connection Request Batch Flush

    @ObservationIgnored private var connectionRequestDitto: Ditto?
    @ObservationIgnored private var pendingConnectionRequestEntries: [LogEntry] = []
    @ObservationIgnored private var connectionRequestFlushTask: Task<Void, Never>?

    // MARK: - Init

    private init() {}

    // MARK: - Live Capture (Ditto SDK callback)

    /// Starts streaming live log entries from the Ditto SDK callback.
    ///
    /// The callback is process-wide; `stopLiveCapture()` (called from the
    /// Logging view's `.onDisappear` and from database close) clears it again
    /// via `DittoLogger.setCustomLogCallback(nil)`.
    func startLiveCapture(persistenceDir _: URL) {
        DittoLogger.setCustomLogCallback { [weak self] level, message in
            guard let self else { return }
            let entry = LogEntry(
                timestamp: Date.now,
                level: level,
                message: message,
                component: LogComponent.heuristic(from: message),
                source: .dittoSDK,
                rawLine: message
            )
            // Buffer on the callback thread; hop to the MainActor only once
            // per batch window (when no flush is already scheduled).
            if liveBuffer.append(entry) {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self?.flushPendingEntries()
                }
            }
        }
        Log.info("DittoLogCaptureService: live capture started")
    }

    /// Stops live log streaming. Clears the process-wide SDK callback FIRST so
    /// no new lines arrive, then drains whatever is still buffered.
    func stopLiveCapture() {
        DittoLogger.setCustomLogCallback(nil)
        flushPendingEntries()
        Log.info("DittoLogCaptureService: live capture stopped")
    }

    private func flushPendingEntries() {
        let batch = liveBuffer.drain()
        guard !batch.isEmpty else { return }
        liveEntries.append(contentsOf: batch)
        // Trim only once we're a slack margin past the cap, so the O(n) shift is
        // amortized over many flushes instead of running on every flush at cap.
        if liveEntries.count > maxLiveEntries + 512 {
            liveEntries.removeFirst(liveEntries.count - maxLiveEntries)
        }
    }

    // MARK: - Historical Log Loading (file-based)

    /// Loads historical log entries from the SDK persistence directory.
    /// Reads `.log` (plain) and `.log.gz` (gzip) files on a background task.
    func loadHistoricalLogs(from persistenceDir: URL) async {
        isLoading = true
        defer { isLoading = false }

        // The SDK writes its rotating logs to `ditto_logs/`; older SDK layouts
        // used `logs/`. Reading only `logs/` silently returned zero entries on
        // every current build — verified against every persistence directory
        // under Application Support/ditto_edge_studio, all of which have
        // `ditto_logs/` and none of which have `logs/`. Mirrors the directory
        // probe `LoggingDetailView.exportDittoSDKLogs(to:)` already performs.
        let fileManager = FileManager.default
        let candidateDir = ["ditto_logs", "logs"]
            .map { persistenceDir.appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }
        guard let logsDir = candidateDir else {
            Log.warning("DittoLogCaptureService: no SDK log directory under \(persistenceDir.path)")
            historicalEntries = []
            return
        }
        let entries = await Task.detached(priority: .utility) {
            LogFileParser.parseDirectory(logsDir)
        }.value

        historicalEntries = Array(entries.sorted { $0.timestamp < $1.timestamp }.suffix(maxHistoricalEntries))
        Log.info("DittoLogCaptureService: loaded \(entries.count) historical entries (capped at \(maxHistoricalEntries))")
    }

    // MARK: - App Log Loading (CocoaLumberjack)

    /// Loads app log entries from CocoaLumberjack files.
    func loadAppLogs() async {
        isLoading = true
        defer { isLoading = false }

        let logFileURLs = LoggingService.shared.getAllLogFiles()
        let entries = await Task.detached(priority: .utility) {
            LogFileParser.parseCocoaLumberjackFiles(logFileURLs)
        }.value

        appEntries = Array(entries.sorted { $0.timestamp < $1.timestamp }.suffix(maxAppEntries))
        Log.info("DittoLogCaptureService: loaded \(entries.count) app log entries (capped at \(maxAppEntries))")
    }

    // MARK: - External Import

    /// Imports log files from an external directory (e.g. exported from another device).
    func importFromDirectory(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }

        let label = url.lastPathComponent
        let entries = await Task.detached(priority: .utility) {
            // Try parsing as Ditto SDK log dir first, then fallback to CocoaLumberjack
            let sdkEntries = LogFileParser.parseDirectory(url)
            if !sdkEntries.isEmpty {
                return sdkEntries.map { entry in
                    LogEntry(
                        id: entry.id,
                        timestamp: entry.timestamp,
                        level: entry.level,
                        message: entry.message,
                        component: entry.component,
                        source: .imported(label: label),
                        rawLine: entry.rawLine
                    )
                }
            }
            // Fallback: try CocoaLumberjack format
            let fileManager = FileManager.default
            let files = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "log" } ?? []
            let appEntries = LogFileParser.parseCocoaLumberjackFiles(files)
            return appEntries.map { entry in
                LogEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    level: entry.level,
                    message: entry.message,
                    component: entry.component,
                    source: .imported(label: label),
                    rawLine: entry.rawLine
                )
            }
        }.value

        importedLabel = label
        importedEntries = entries.sorted { $0.timestamp < $1.timestamp }
        Log.info("DittoLogCaptureService: imported \(entries.count) entries from '\(label)'")
    }

    /// Clears all imported entries and resets the import label.
    func clearImported() {
        importedEntries = []
        importedLabel = ""
    }

    /// Clears live entries (useful for a fresh capture session).
    func clearLive() {
        liveEntries = []
    }

    /// Clears all loaded historical entries.
    func clearHistorical() {
        historicalEntries = []
    }

    // MARK: - Transport Condition Observer

    /// Starts observing Ditto transport condition changes via the DittoDelegate.
    func startTransportConditionObserver(ditto: Ditto) {
        guard observedDitto !== ditto else { return }
        observedDitto = ditto
        ditto.delegate = self
        Log.info("DittoLogCaptureService: transport condition observer started")
    }

    /// Stops the transport condition observer and flushes any pending entries.
    func stopTransportConditionObserver() {
        transportFlushTask?.cancel()
        transportFlushTask = nil
        flushTransportEntries()
        observedDitto?.delegate = nil
        observedDitto = nil
        Log.info("DittoLogCaptureService: transport condition observer stopped")
    }

    /// DittoDelegate — called on delegateEventQueue (background thread)
    nonisolated func dittoTransportConditionDidChange(
        ditto _: Ditto,
        condition: DittoTransportCondition,
        subsystem: DittoConditionSource
    ) {
        let msg = "Transport: \(subsystem) → \(condition)"
        let entry = LogEntry(
            timestamp: Date.now,
            level: .info,
            message: msg,
            component: .transport,
            source: .transportConditions,
            rawLine: msg
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingTransportEntries.append(entry)
            if transportFlushTask == nil {
                transportFlushTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self?.flushTransportEntries()
                }
            }
        }
    }

    /// Clears all transport condition entries.
    func clearTransportEntries() {
        transportEntries = []
    }

    private func flushTransportEntries() {
        guard !pendingTransportEntries.isEmpty else { transportFlushTask = nil; return }
        transportEntries.append(contentsOf: pendingTransportEntries)
        if transportEntries.count > maxTransportEntries + 512 {
            transportEntries.removeFirst(transportEntries.count - maxTransportEntries)
        }
        pendingTransportEntries.removeAll()
        transportFlushTask = nil
    }

    // MARK: - Connection Request Handler

    /// Installs the connection request handler on the Ditto instance.
    /// Every incoming connection is unconditionally accepted — this is log-only.
    func startConnectionRequestHandler(ditto: Ditto) {
        guard connectionRequestDitto !== ditto else { return }
        connectionRequestDitto = ditto
        ditto.presence.connectionRequestHandler = { [weak self] request async -> DittoConnectionRequestAuthorization in
            let identity = request.identityServiceMetadata.isEmpty ? "none" : String(describing: request.identityServiceMetadata)
            let meta = request.peerMetadata.isEmpty ? "none" : String(describing: request.peerMetadata)
            let msg = "Connection Request | type=\(request.connectionType) | key=\(request.peerKey)" +
                " | identity=\(identity) | meta=\(meta)"
            let entry = LogEntry(
                timestamp: Date.now,
                level: .info,
                message: msg,
                component: .auth,
                source: .connectionRequests,
                rawLine: msg
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                pendingConnectionRequestEntries.append(entry)
                if connectionRequestFlushTask == nil {
                    connectionRequestFlushTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        self?.flushConnectionRequestEntries()
                    }
                }
            }
            return .allow
        }
        Log.info("DittoLogCaptureService: connection request handler started")
    }

    /// Removes the connection request handler and flushes any pending entries.
    func stopConnectionRequestHandler() {
        connectionRequestFlushTask?.cancel()
        connectionRequestFlushTask = nil
        flushConnectionRequestEntries()
        connectionRequestDitto?.presence.connectionRequestHandler = nil
        connectionRequestDitto = nil
        Log.info("DittoLogCaptureService: connection request handler stopped")
    }

    /// Clears all connection request entries.
    func clearConnectionRequestEntries() {
        connectionRequestEntries = []
    }

    private func flushConnectionRequestEntries() {
        guard !pendingConnectionRequestEntries.isEmpty else { connectionRequestFlushTask = nil; return }
        connectionRequestEntries.append(contentsOf: pendingConnectionRequestEntries)
        if connectionRequestEntries.count > maxConnectionRequestEntries + 512 {
            connectionRequestEntries.removeFirst(connectionRequestEntries.count - maxConnectionRequestEntries)
        }
        pendingConnectionRequestEntries.removeAll()
        connectionRequestFlushTask = nil
    }
}

// MARK: - LiveLogBuffer

/// Lock-protected buffer for live log entries arriving on the Ditto SDK
/// callback thread. Lets the callback append synchronously (no per-line
/// `Task { @MainActor }` hop) and coalesces MainActor flushes: `append`
/// returns `true` only when no flush is currently scheduled, so the caller
/// schedules exactly one flush per batch window.
private final class LiveLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private var isFlushScheduled = false

    /// Appends an entry. Returns `true` when the caller must schedule a
    /// MainActor flush (i.e. none is pending).
    func append(_ entry: LogEntry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        guard !isFlushScheduled else { return false }
        isFlushScheduled = true
        return true
    }

    /// Drains the pending entries and rearms the scheduler flag. The swap and
    /// the flag reset happen under the same lock acquisition so no entry can
    /// be stranded unflushed.
    func drain() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        isFlushScheduled = false
        let batch = entries
        entries.removeAll(keepingCapacity: true)
        return batch
    }
}
