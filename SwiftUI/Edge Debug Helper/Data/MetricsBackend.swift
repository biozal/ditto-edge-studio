import Foundation

// MARK: - MetricSample

struct MetricSample: Sendable {
    let timestamp: Date
    let value: Double
}

// MARK: - InMemoryMetricsStore

actor InMemoryMetricsStore {
    static let shared = InMemoryMetricsStore()

    private let maxSamples = 120 // ~2 minutes at 1/sec
    private var samplesByLabel: [String: [MetricSample]] = [:]
    private var counters: [String: Double] = [:]

    init() {}

    func record(label: String, value: Double) {
        var list = samplesByLabel[label] ?? []
        list.append(MetricSample(timestamp: Date(), value: value))
        if list.count > maxSamples {
            list = Array(list.suffix(maxSamples))
        }
        samplesByLabel[label] = list
    }

    func increment(label: String, by amount: Double = 1.0) {
        let current = counters[label] ?? 0.0
        let newValue = current + amount
        counters[label] = newValue
        record(label: label, value: newValue)
    }

    func samplesForLabel(_ label: String) -> [MetricSample] {
        samplesByLabel[label] ?? []
    }

    func latestValue(for label: String) -> Double? {
        counters[label] ?? samplesByLabel[label]?.last?.value
    }

    func countersSnapshot() -> [String: Double] {
        counters
    }

    func reset() {
        samplesByLabel = [:]
        counters = [:]
    }
}

// MARK: - AppMetricsCounter

struct AppMetricsCounter: Sendable {
    let label: String

    func increment(by amount: Double = 1.0) {
        Task.detached(priority: .utility) {
            await InMemoryMetricsStore.shared.increment(label: label, by: amount)
        }
    }
}

// MARK: - AppMetricsTimer

struct AppMetricsTimer: Sendable {
    let label: String

    func recordMilliseconds(_ ms: Double) {
        Task.detached(priority: .utility) {
            await InMemoryMetricsStore.shared.record(label: label, value: ms)
        }
    }
}

// MARK: - PrometheusExportBackend

actor PrometheusExportBackend {
    static let shared = PrometheusExportBackend()

    private(set) var pushgatewayURL: URL?
    private(set) var exportIntervalSeconds = 60
    private(set) var lastPushDate: Date?
    private(set) var lastPushError: String?
    private(set) var isRunning = false

    private var exportTask: Task<Void, Never>?

    private init() {}

    func configure(url: URL?, intervalSeconds: Int) {
        pushgatewayURL = url
        exportIntervalSeconds = max(10, intervalSeconds)
        stopExporting()
        if url != nil {
            startExporting()
        }
    }

    func startExporting() {
        guard !isRunning, pushgatewayURL != nil else { return }
        isRunning = true
        let interval = exportIntervalSeconds
        exportTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.pushMetrics()
            }
        }
    }

    func stopExporting() {
        isRunning = false
        exportTask?.cancel()
        exportTask = nil
    }

    func pushNow() async {
        await pushMetrics()
    }

    private func pushMetrics() async {
        guard let url = pushgatewayURL else { return }
        let pushURL = url.appendingPathComponent("metrics/job/edge_studio")
        let metricsText = await prometheusTextFormat()

        var request = URLRequest(url: pushURL)
        request.httpMethod = "PUT"
        request.setValue("text/plain; version=0.0.4", forHTTPHeaderField: "Content-Type")
        request.httpBody = metricsText.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200 ... 299).contains(httpResponse.statusCode)
            {
                lastPushDate = Date()
                lastPushError = nil
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                lastPushError = "HTTP \(code)"
            }
        } catch {
            lastPushError = error.localizedDescription
        }
    }

    private func prometheusTextFormat() async -> String {
        let counters = await InMemoryMetricsStore.shared.countersSnapshot()
        var lines: [String] = []
        for (label, value) in counters.sorted(by: { $0.key < $1.key }) {
            let safeName = label
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: "-", with: "_")
            lines.append("# HELP \(safeName) Edge Studio metric")
            lines.append("# TYPE \(safeName) gauge")
            lines.append("\(safeName) \(value)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
