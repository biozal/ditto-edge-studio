import Foundation

/// One metric series sample (parity with the VS Code extension's
/// `SystemMetricSample`). The SDK 5.1 `system:metrics` virtual collection
/// FLUSHES the registry on every read, so each row carries a per-read delta —
/// running totals are accumulated host-side, keyed by metric + sorted labels.
struct SystemMetricSample: Equatable {
    /// Bare metric name, e.g. `ditto.network.dsoq.connection.opened`.
    let key: String
    /// Label map (sqlite metrics label by `db` role, recovery by `cause`, …).
    let labels: [String: String]
    let description: String
    let unit: String
    /// `histogram` when the row carries `count`/`dcount`; otherwise `counter`
    /// (counters and gauges share one row shape — `current`/`updates`/`delta`).
    let kind: SystemMetricKind
    /// Running total since the host connected: counters accumulate `delta`,
    /// histograms accumulate `dcount`.
    var sinceConnect: Double
    /// The most recent read's delta alone (counters: `delta`; histograms: `dcount`).
    var periodDelta: Double
    /// Histograms only: accumulated `dsum` since connect.
    var sumSinceConnect: Double?
    /// Histograms only: latest cumulative absolute max reported by the store.
    var absMax: Double?
}

enum SystemMetricKind: String {
    case counter
    case histogram
}

enum SystemMetricsAccumulator {
    /// Stable per-series signature: metric key plus its sorted label map.
    static func seriesSignature(key: String, labels: [String: String]) -> String {
        let sorted = labels.keys.sorted().map { "\($0)=\(labels[$0] ?? "")" }.joined(separator: ",")
        return "\(key){\(sorted)}"
    }

    /// Folds one flush of `system:metrics` rows into `samples`.
    /// Placeholder/garbage rows are ignored.
    static func accumulate(rows: [[String: Any]], into samples: inout [String: SystemMetricSample]) {
        for row in rows {
            guard let parsed = parseMetricRow(row) else { continue }
            let sig = seriesSignature(key: parsed.key, labels: parsed.labels)
            if var existing = samples[sig] {
                existing.sinceConnect += parsed.delta
                existing.periodDelta = parsed.delta
                if parsed.kind == .histogram {
                    existing.sumSinceConnect = (existing.sumSinceConnect ?? 0) + parsed.deltaSum
                    if let absMax = parsed.absMax {
                        existing.absMax = absMax
                    }
                }
                samples[sig] = existing
            } else {
                samples[sig] = SystemMetricSample(
                    key: parsed.key,
                    labels: parsed.labels,
                    description: parsed.description,
                    unit: parsed.unit,
                    kind: parsed.kind,
                    sinceConnect: parsed.delta,
                    periodDelta: parsed.delta,
                    sumSinceConnect: parsed.kind == .histogram ? parsed.deltaSum : nil,
                    absMax: parsed.kind == .histogram ? parsed.absMax : nil
                )
            }
        }
    }

    /// True when a SELECT answered but the exporter isn't installed — the row
    /// set is exactly the placeholder `{status: "disabled", …}` shape.
    static func isExporterDisabled(rows: [[String: Any]]) -> Bool {
        !rows.isEmpty
            && rows.allSatisfy { $0["key"] == nil }
            && rows.contains { ($0["status"] as? String) == "disabled" }
    }

    // MARK: - Row parsing

    private struct ParsedRow {
        let key: String
        let labels: [String: String]
        let description: String
        let unit: String
        let kind: SystemMetricKind
        let delta: Double
        let deltaSum: Double
        let absMax: Double?
    }

    private static func parseMetricRow(_ row: [String: Any]) -> ParsedRow? {
        guard let key = row["key"] as? String, !key.isEmpty else { return nil }
        var labels: [String: String] = [:]
        if let rawLabels = row["labels"] as? [String: Any] {
            for (k, v) in rawLabels where v is String {
                labels[k] = v as? String
            }
        }
        let isHistogram = number(row["count"]) != nil || number(row["dcount"]) != nil
        return ParsedRow(
            key: key,
            labels: labels,
            description: (row["description"] as? String) ?? "",
            unit: (row["unit"] as? String) ?? "",
            kind: isHistogram ? .histogram : .counter,
            delta: number(row[isHistogram ? "dcount" : "delta"]) ?? 0,
            deltaSum: number(row["dsum"]) ?? 0,
            absMax: number(row["abs_max"])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        // Note: `Any` numerics bridge to NSNumber — check isFinite on the bridged
        // value so NaN/inf read as "no delta" rather than polluting totals.
        if let n = value as? NSNumber {
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        return nil
    }
}
