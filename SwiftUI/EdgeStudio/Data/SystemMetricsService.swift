import DittoSwift
import Foundation

/// Polls the SDK 5.1 `system:metrics` virtual collection and accumulates deltas
/// (parity with the VS Code extension's `SystemMetricsService`).
///
/// The collection FLUSHES the registry on every read, so samples carry per-read
/// deltas — this service keeps running totals in `snapshot.samples` (since the
/// first poll of this session). Poll cadence is 5 s; callers start when the
/// dashboard is visible and the `.task` cancels polling when it leaves.
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
    private var pollTask: Task<Void, Never>?
    /// Set by this instance's very first `pollOnce`. An instance property, not a
    /// per-round local: a manual Refresh that lands before the loop's own first
    /// poll — or a return visit to the screen — must not re-zero the totals.
    private var hasZeroed = false

    static let pollInterval: Duration = .seconds(5)
    static let query = "SELECT * FROM system:metrics"

    /// Idempotent. Call from the dashboard's `.task`; cancellation stops the loop.
    func start() {
        guard pollTask == nil else { return }

        guard UserDefaults.standard.object(forKey: "collectSystemMetrics") as? Bool ?? true else {
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

    /// One immediate read ahead of the cadence, for the dashboard's Refresh
    /// button. Safe to call while the loop is running: reads flush Ditto's
    /// registry, so an extra read only moves activity from the next poll's
    /// delta into this one — the accumulated totals stay correct.
    func refreshNow() async {
        await pollOnce()
    }

    private func pollOnce() async {
        guard let ditto = await DittoManager.shared.dittoSelectedApp else {
            snapshot = Snapshot(status: .noConnection)
            return
        }
        if !hasZeroed {
            // Very first poll this service instance ever makes: drop anything a
            // previous owner left behind so "since" marks this database open.
            // Deliberately NOT re-run per visibility round — leaving and
            // returning to the screen continues the same running totals (the
            // missed activity folds into the next poll's delta), which is what
            // makes a pinned series' since-connect number mean something.
            samples.removeAll()
            hasZeroed = true
        }
        do {
            let results = try await ditto.store.execute(query: Self.query)
            // Defensive per-item serialization (item.jsonData() traps on bad values —
            // same rule as the observers pipeline).
            let rows: [[String: Any]] = results.items.compactMap { item in
                let cleaned = item.value.compactMapValues { $0 }
                guard let data = try? JSONSerialization.data(withJSONObject: cleaned),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return obj
            }
            for item in results.items {
                item.dematerialize()
            }

            if SystemMetricsAccumulator.isExporterDisabled(rows: rows) {
                snapshot = Snapshot(status: .exporterDisabled)
                return
            }
            let since = samples.isEmpty ? Date.now : (snapshot.since ?? Date.now)
            SystemMetricsAccumulator.accumulate(rows: rows, into: &samples)
            snapshot = Snapshot(
                samples: samples.values.sorted { $0.key < $1.key },
                status: .ready,
                since: since,
                polledAt: Date.now
            )
        } catch {
            snapshot = Snapshot(status: .error(error.localizedDescription), errorMessage: error.localizedDescription)
        }
    }
}
