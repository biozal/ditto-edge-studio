import DittoSwift
import Foundation

/// Manages all log sources: live Ditto SDK callback, historical file parsing, app logs, and external imports.
///
/// This service is `@Observable` and must be accessed from the main actor.
@Observable
@MainActor
final class DittoLogCaptureService {
    static let shared = DittoLogCaptureService()

    // MARK: - Published State

    private(set) var liveEntries: [LogEntry] = []
    private(set) var historicalEntries: [LogEntry] = []
    private(set) var appEntries: [LogEntry] = []
    private(set) var importedEntries: [LogEntry] = []
    private(set) var importedLabel = ""
    private(set) var isLoading = false

    // MARK: - Constants

    private let maxLiveEntries = 10000
    private let maxHistoricalEntries = 10000
    private let maxAppEntries = 5000

    // MARK: - Live Batch Flush

    @ObservationIgnored private var pendingLiveEntries: [LogEntry] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    // MARK: - Init

    private init() {}

    // MARK: - Live Capture (Ditto SDK callback)

    /// Starts streaming live log entries from the Ditto SDK callback.
    func startLiveCapture(persistenceDir _: URL) {
        DittoLogger.setCustomLogCallback { [weak self] level, message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let entry = LogEntry(
                    timestamp: Date(),
                    level: level,
                    message: message,
                    component: LogComponent.heuristic(from: message),
                    source: .dittoSDK,
                    rawLine: message
                )
                pendingLiveEntries.append(entry)
                if flushTask == nil {
                    flushTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(250))
                        self?.flushPendingEntries()
                    }
                }
            }
        }
        Log.info("DittoLogCaptureService: live capture started")
    }

    /// Stops live log streaming.
    func stopLiveCapture() {
        flushTask?.cancel()
        flushTask = nil
        flushPendingEntries()
        DittoLogger.setCustomLogCallback(nil)
        Log.info("DittoLogCaptureService: live capture stopped")
    }

    private func flushPendingEntries() {
        guard !pendingLiveEntries.isEmpty else { flushTask = nil; return }
        liveEntries.append(contentsOf: pendingLiveEntries)
        if liveEntries.count > maxLiveEntries {
            liveEntries.removeFirst(liveEntries.count - maxLiveEntries)
        }
        pendingLiveEntries.removeAll()
        flushTask = nil
    }

    // MARK: - Historical Log Loading (file-based)

    /// Loads historical log entries from the SDK persistence directory.
    /// Reads `.log` (plain) and `.log.gz` (gzip) files on a background task.
    func loadHistoricalLogs(from persistenceDir: URL) async {
        isLoading = true
        defer { isLoading = false }

        let logsDir = persistenceDir.appendingPathComponent("logs")
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
}
