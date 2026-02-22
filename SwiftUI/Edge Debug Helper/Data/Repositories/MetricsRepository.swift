import Foundation

#if os(macOS)
import Darwin
#endif

// MARK: - Snapshot types

struct ProcessMetricSnapshot: Sendable {
    let residentMemoryBytes: Double?
    let virtualMemoryBytes: Double?
    let cpuTimeSeconds: Double?
    let openFileDescriptors: Int?
    let processUptimeSeconds: Double
}

struct QueryMetricSnapshot: Sendable {
    let totalQueryCount: Double
    let avgQueryLatencyMs: Double?
    let lastQueryLatencyMs: Double?
}

// MARK: - MetricsRepository

enum MetricsRepository {
    static let appStartDate = Date() // captures first access ≈ app launch

    // MARK: - Process metrics (synchronous — Darwin APIs are thread-safe)

    static func processMetricSnapshot() -> ProcessMetricSnapshot {
        #if os(macOS)
        return ProcessMetricSnapshot(
            residentMemoryBytes: getResidentMemory(),
            virtualMemoryBytes: getVirtualMemory(),
            cpuTimeSeconds: getCPUTime(),
            openFileDescriptors: getOpenFDCount(),
            processUptimeSeconds: Date().timeIntervalSince(MetricsRepository.appStartDate)
        )
        #else
        return ProcessMetricSnapshot(
            residentMemoryBytes: nil,
            virtualMemoryBytes: nil,
            cpuTimeSeconds: nil,
            openFileDescriptors: nil,
            processUptimeSeconds: Date().timeIntervalSince(MetricsRepository.appStartDate)
        )
        #endif
    }

    // MARK: - Query metrics (async — reads from InMemoryMetricsStore actor)

    static func queryMetricSnapshot() async -> QueryMetricSnapshot {
        let totalCount = await InMemoryMetricsStore.shared.latestValue(for: "edge_studio.queries.total") ?? 0.0
        let latencySamples = await InMemoryMetricsStore.shared.samplesForLabel("edge_studio.query.latency_ms")
        let avg: Double? = latencySamples.isEmpty
            ? nil
            : latencySamples.reduce(0.0) { $0 + $1.value } / Double(latencySamples.count)
        return QueryMetricSnapshot(
            totalQueryCount: totalCount,
            avgQueryLatencyMs: avg,
            lastQueryLatencyMs: latencySamples.last?.value
        )
    }

    static func samples(for label: String) async -> [MetricSample] {
        await InMemoryMetricsStore.shared.samplesForLabel(label)
    }

    // MARK: - Prometheus lifecycle

    static func startCollecting() async {
        await PrometheusExportBackend.shared.startExporting()
    }

    static func stopCollecting() async {
        await PrometheusExportBackend.shared.stopExporting()
    }

    // MARK: - macOS Darwin helpers

    #if os(macOS)
    private static func getResidentMemory() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) : nil
    }

    private static func getVirtualMemory() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.virtual_size) : nil
    }

    private static func getCPUTime() -> Double? {
        var tinfo = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &tinfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let userTime = Double(tinfo.user_time.seconds) + Double(tinfo.user_time.microseconds) / 1_000_000.0
        let sysTime = Double(tinfo.system_time.seconds) + Double(tinfo.system_time.microseconds) / 1_000_000.0
        return userTime + sysTime
    }

    private static func getOpenFDCount() -> Int? {
        var count = 0
        for fd in 0 ..< 1024 where fcntl(Int32(fd), F_GETFL) != -1 {
            count += 1
        }
        return count
    }
    #endif
}
