import SwiftUI

struct MetricsInspectorView: View {
    @State private var pushgatewayURLText = ""
    @State private var exportIntervalText = "60"
    @State private var statusMessage = ""
    @State private var isConfigured = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exportSection
                Divider()
                statusSection
                Divider()
                actionsSection
            }
            .padding()
        }
        .task {
            await loadCurrentSettings()
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prometheus Export", systemImage: "arrow.up.to.line")
                .font(.headline)

            Text("Pushgateway URL")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("http://localhost:9091 (optional)", text: $pushgatewayURLText)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .autocorrectionDisabled()

            HStack {
                Text("Export interval:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("60", text: $exportIntervalText)
                #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                #endif
                    .frame(width: 60)
                Text("seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button("Apply") {
                Task { await applySettings() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Export Status", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            if statusMessage.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusMessage.hasPrefix("Error") ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusMessage.hasPrefix("Error") ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Button {
                Task { await pushNow() }
            } label: {
                Label("Push Now", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!isConfigured)

            Button {
                Task { await clearMetrics() }
            } label: {
                Label("Clear All Metrics", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Data helpers

    private func loadCurrentSettings() async {
        let url = await PrometheusExportBackend.shared.pushgatewayURL
        let interval = await PrometheusExportBackend.shared.exportIntervalSeconds
        let lastPush = await PrometheusExportBackend.shared.lastPushDate
        let lastError = await PrometheusExportBackend.shared.lastPushError

        pushgatewayURLText = url?.absoluteString ?? ""
        exportIntervalText = "\(interval)"
        isConfigured = url != nil

        if let error = lastError {
            statusMessage = "Error: \(error)"
        } else if let date = lastPush {
            let elapsed = Int(Date().timeIntervalSince(date))
            statusMessage = "Last push: \(elapsed)s ago"
        } else if url != nil {
            statusMessage = "Configured — awaiting first push"
        } else {
            statusMessage = ""
        }
    }

    private func applySettings() async {
        let trimmed = pushgatewayURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.isEmpty ? nil : URL(string: trimmed)
        let interval = Int(exportIntervalText) ?? 60
        await PrometheusExportBackend.shared.configure(url: url, intervalSeconds: interval)
        await loadCurrentSettings()
    }

    private func pushNow() async {
        await PrometheusExportBackend.shared.pushNow()
        await loadCurrentSettings()
    }

    private func clearMetrics() async {
        await InMemoryMetricsStore.shared.reset()
        await QueryMetricsRepository.shared.clearRecords()
        await loadCurrentSettings()
    }
}
