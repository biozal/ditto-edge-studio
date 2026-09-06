import SwiftUI

/// Namespace filter for the system-metrics table.
enum SystemMetricsNamespaceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case network = "Network"
    case store = "Store"
    case sync = "Sync"
    case other = "Other"

    var id: String {
        rawValue
    }

    var prefixes: [String]? {
        switch self {
        case .all: return nil
        case .network: return ["ditto.network."]
        case .store: return ["ditto.backend."]
        case .sync: return ["ditto.sync.", "ditto.replication."]
        case .other: return []
        }
    }

    func matches(_ sample: SystemMetricSample) -> Bool {
        switch self {
        case .all:
            return true
        case .other:
            return Self.allCases.compactMap(\.prefixes).flatMap(\.self)
                .contains { sample.key.hasPrefix($0) } == false
        default:
            return prefixes?.contains { sample.key.hasPrefix($0) } ?? false
        }
    }
}

/// Identifiable wrapper so ForEach gets a stable KeyPath-based id per series.
private struct SystemMetricRow: Identifiable {
    let id: String
    let sample: SystemMetricSample
}

/// The `system:metrics` dashboard section (SDK 5.1; parity with the extension's
/// Database Metrics system-metrics section): a namespace-filtered counter table,
/// per-poll deltas, and the dsoq opened-vs-closed divergence alert.
struct SystemMetricsSectionView: View {
    let snapshot: SystemMetricsService.Snapshot
    @Binding var namespaceFilter: SystemMetricsNamespaceFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("System Metrics", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            // Centered, per the segmented-picker pattern in CLAUDE.md — the
            // Spacer pair is what does the centering. Previously this sat hard
            // right of the heading, which read as an afterthought rather than
            // as the control governing the table below it.
            HStack {
                Spacer(minLength: 0)
                DittoSegmentedPicker(
                    options: SystemMetricsNamespaceFilter.allCases,
                    selection: $namespaceFilter
                ) { $0.rawValue }
                    .frame(maxWidth: 320)
                Spacer(minLength: 0)
            }

            switch snapshot.status {
            case .settingDisabled:
                statusNote(
                    "System metrics collection is off. Enable \"Collect system metrics\" in Settings — it takes effect the next time you open a database."
                )
            case .exporterDisabled:
                statusNote(
                    "The SDK exporter wasn't enabled for this session. Close and re-open the database after enabling \"Collect system metrics\"."
                )
            case .noConnection:
                statusNote("No active database connection.")
            case let .error(message):
                statusNote("system:metrics read failed: \(message)", isError: true)
            case .idle, .ready:
                readyBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusNote(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? Color.red : .secondary)
            .padding(.vertical, 4)
    }

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            divergenceBanner

            let filtered = snapshot.samples.filter { namespaceFilter.matches($0) }
            if filtered.isEmpty {
                statusNote(
                    snapshot.samples.isEmpty
                        ? "No metrics reported yet — they accumulate while this section is visible."
                        : "No metrics in this namespace."
                )
            } else {
                ForEach(
                    filtered.map { SystemMetricRow(id: $0.key + "|" + snapshotIdentity($0.labels), sample: $0) }
                ) { row in
                    metricRow(row.sample)
                }
            }

            if let since = snapshot.since {
                Text("Since \(since.formatted(date: .omitted, time: .shortened))" +
                    (snapshot.polledAt.map { " — updated \($0.formatted(date: .omitted, time: .standard))" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotIdentity(_ labels: [String: String]) -> String {
        labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    @ViewBuilder
    private var divergenceBanner: some View {
        let opened = snapshot.samples.first { $0.key == "ditto.network.dsoq.connection.opened" }?.sinceConnect
        let closed = snapshot.samples.first { $0.key == "ditto.network.dsoq.connection.closed" }?.sinceConnect
        if let opened, let closed, opened != closed {
            Label(
                "dsoq connections opened (\(formatValue(opened))) ≠ closed (\(formatValue(closed))) — possible connection leak or handshake issue. Check Log Analyzer → Transport Conditions.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func metricRow(_ sample: SystemMetricSample) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(sample.key.replacingOccurrences(of: "ditto.", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                if !sample.labels.isEmpty {
                    Text(snapshotIdentity(sample.labels))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatValue(sample.sinceConnect) + (sample.unit.isEmpty ? "" : " \(sample.unit)"))
                    .font(.system(.caption, design: .monospaced))
                Text(sample.periodDelta > 0 ? "▲ +\(formatValue(sample.periodDelta))" : "—")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(sample.periodDelta > 0 ? Color.green : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        }
        return value < 10 ? String(format: "%.2f", value) : String(format: "%.1f", value)
    }
}
