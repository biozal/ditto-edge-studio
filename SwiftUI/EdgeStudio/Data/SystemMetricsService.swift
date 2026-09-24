import DittoSwift
import Foundation

/// Polls the SDK 5.1 `system:metrics` virtual collection and accumulates deltas
/// (parity with the VS Code extension's `SystemMetricsService`).
///
/// The collection FLUSHES the registry on every read, so samples carry per-read
/// deltas — this service keeps running totals in `snapshot.samples` (since the
/// first poll of this session). Poll cadence is 5 s; callers start when the
/// dashboard is visible and stop polling when it leaves. The database session's
/// view model owns this service so navigating away does not discard totals.
@MainActor @Observable
final class SystemMetricsService {
    enum Status: Equatable {
        case idle
        /// "Collect system metrics" is off — the exporter is startup-gated, so
        /// nothing polls until the next database open with the setting on.
        case settingDisabled
        case noConnection
        /// The SDK answered but the exporter wasn't installed (placeholder rows).
        case exporterDisabled
        case ready
        case error(String)
    }

    struct Snapshot: Equatable {
        var samples: [SystemMetricSample] = []
        var status: Status = .idle
        /// First accumulation's timestamp — the "since connect" zero point.
        var since: Date?
        var polledAt: Date?
        var errorMessage: String?
    }

    private(set) var snapshot = Snapshot()
    private var samples: [String: SystemMetricSample] = [:]
    // Status snapshots may be replaced during transient failures. The zero point
    // belongs to the retained accumulator, so recovery must not move it forward.
    private var accumulationStartedAt: Date?
    private var pollTask: Task<Void, Never>?
    private var sessionEnded = false
    private let readRows: @MainActor () async throws -> [[String: Any]]?

    /// The reader is injectable to exercise the same accumulation and lifecycle
    /// path without requiring a live SDK store. Nil means no database is open.
    init(readRows: (@MainActor () async throws -> [[String: Any]]?)? = nil) {
        self.readRows = readRows ?? Self.readSelectedRows
    }

    static let pollInterval: Duration = .seconds(5)
    static let query = "SELECT * FROM system:metrics"

    /// Idempotent. Call from the dashboard's `.task`; cancellation stops the loop.
    func start() {
        guard !sessionEnded, pollTask == nil else { return }

        guard StudioPreferences.store.object(forKey: "collectSystemMetrics") as? Bool ?? true else {
            snapshot = Snapshot(status: .settingDisabled)
            return
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await pollOnce()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Terminal teardown for this database session. Unlike leaving the screen,
    /// closing a database clears its totals and rejects late poll completions.
    func endSession() {
        sessionEnded = true
        stop()
        samples.removeAll()
        accumulationStartedAt = nil
        snapshot = Snapshot()
    }

    /// One immediate read ahead of the cadence, for the dashboard's Refresh
    /// button. Safe to call while the loop is running: reads flush Ditto's
    /// registry, so an extra read only moves activity from the next poll's
    /// delta into this one — the accumulated totals stay correct.
    func refreshNow() async {
        await pollOnce()
    }

    private func pollOnce() async {
        guard !sessionEnded else { return }
        do {
            let rows = try await readRows()
            guard !sessionEnded else { return }
            guard let rows else {
                snapshot = Snapshot(status: .noConnection)
                return
            }

            if SystemMetricsAccumulator.isExporterDisabled(rows: rows) {
                snapshot = Snapshot(status: .exporterDisabled)
                return
            }
            let since = accumulationStartedAt ?? Date.now
            accumulationStartedAt = since
            SystemMetricsAccumulator.accumulate(rows: rows, into: &samples)
            snapshot = Snapshot(
                samples: samples.values.sorted { $0.key < $1.key },
                status: .ready,
                since: since,
                polledAt: Date.now
            )
        } catch {
            guard !sessionEnded else { return }
            snapshot = Snapshot(status: .error(error.localizedDescription), errorMessage: error.localizedDescription)
        }
    }

    private static func readSelectedRows() async throws -> [[String: Any]]? {
        guard let ditto = await DittoManager.shared.dittoSelectedApp else { return nil }
        let results = try await ditto.store.execute(query: query)
        // Defensive serialization: item.jsonData() traps on invalid values.
        let rows: [[String: Any]] = results.items.compactMap { item in
            let cleaned = item.value.compactMapValues { $0 }
            guard let data = try? JSONSerialization.data(withJSONObject: cleaned),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj
        }
        for item in results.items {
            item.dematerialize()
        }
        return rows
    }
}
