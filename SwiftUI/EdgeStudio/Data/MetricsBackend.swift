import Foundation

// MARK: - MetricSample

struct MetricSample {
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
        list.append(MetricSample(timestamp: Date.now, value: value))
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

struct AppMetricsCounter {
    let label: String

    func increment(by amount: Double = 1.0) {
        Task.detached(priority: .utility) {
            await InMemoryMetricsStore.shared.increment(label: label, by: amount)
        }
    }
}

// MARK: - AppMetricsTimer

struct AppMetricsTimer {
    let label: String

    func recordMilliseconds(_ ms: Double) {
        Task.detached(priority: .utility) {
            await InMemoryMetricsStore.shared.record(label: label, value: ms)
        }
    }
}
