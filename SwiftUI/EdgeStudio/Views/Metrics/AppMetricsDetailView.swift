import Charts
import SwiftUI

struct AppMetricsDetailView: View {
    @State private var processSnapshot = MetricsRepository.processMetricSnapshot()
    @State private var querySnapshot = QueryMetricSnapshot(
        totalQueryCount: 0,
        avgQueryLatencyMs: nil,
        lastQueryLatencyMs: nil
    )
    @State private var queryLatencySamples: [MetricSample] = []
    @State private var storageSnapshot: StorageSnapshot?
    @State private var lastUpdated = Date()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(macOS)
                    processSection
                    #endif
                    queriesSection
                    storageSection
                }
                .padding()
            }
        }
        .task {
            await runRefreshLoop()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("App Metrics")
                .font(.title2)
                .bold()
            Spacer()
            Text("Updated \(timeAgo(lastUpdated))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await refreshMetrics() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Refresh metrics")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Sections

    #if os(macOS)
    private var processSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Process", systemImage: "cpu")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                if let resident = processSnapshot.residentMemoryBytes {
                    MetricCard(
                        title: "Resident Memory",
                        systemImage: "memorychip",
                        currentValue: formatBytes(resident),
                        samples: [],
                        helpText: "The amount of RAM currently occupied by this app's data and code. High values may indicate a memory leak or large data set in memory.",
                        helpURL: URL(string: "https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use")
                    )
                }
                if let virtual_ = processSnapshot.virtualMemoryBytes {
                    MetricCard(
                        title: "Virtual Memory",
                        systemImage: "memorychip.fill",
                        currentValue: formatBytes(virtual_),
                        samples: [],
                        helpText: "The total virtual address space reserved by the process, including memory-mapped files and shared libraries. Much larger than resident memory is normal.",
                        helpURL: URL(string: "https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use")
                    )
                }
                if let cpu = processSnapshot.cpuTimeSeconds {
                    MetricCard(
                        title: "CPU Time",
                        systemImage: "cpu",
                        currentValue: String(format: "%.2fs", cpu),
                        samples: [],
                        helpText: "Cumulative CPU time consumed by all threads in this process since launch, combining user time and system time. Grows continuously as the app does work.",
                        helpURL: URL(string: "https://developer.apple.com/documentation/xcode/improving-your-app-s-performance")
                    )
                }
                if let fds = processSnapshot.openFileDescriptors {
                    MetricCard(
                        title: "Open File Desc.",
                        systemImage: "doc.on.doc",
                        currentValue: "\(fds)",
                        samples: [],
                        helpText: "The number of file descriptors currently open by this process, including files, sockets, and pipes. Ditto databases use file descriptors internally."
                    )
                }
                MetricCard(
                    title: "Process Uptime",
                    systemImage: "clock",
                    currentValue: formatUptime(processSnapshot.processUptimeSeconds),
                    samples: [],
                    helpText: "How long Edge Studio has been running since it last launched."
                )
            }
        }
    }
    #endif

    private var queriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Queries", systemImage: "text.page")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                MetricCard(
                    title: "Total Queries",
                    systemImage: "text.magnifyingglass",
                    currentValue: "\(Int(querySnapshot.totalQueryCount))",
                    samples: [],
                    helpText: "The number of DQL queries executed against the selected Ditto database since the app launched, including queries run automatically by the app on startup."
                )
                if let avg = querySnapshot.avgQueryLatencyMs {
                    MetricCard(
                        title: "Avg Latency",
                        systemImage: "timer",
                        currentValue: formatLatency(avg),
                        samples: queryLatencySamples,
                        helpText: "The mean execution time across all queries recorded this session, measured from just before ditto.store.execute() is called to when it returns."
                    )
                }
                if let last = querySnapshot.lastQueryLatencyMs {
                    MetricCard(
                        title: "Last Latency",
                        systemImage: "timer.circle",
                        currentValue: formatLatency(last),
                        samples: [],
                        helpText: "The execution time of the most recently completed query."
                    )
                }
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Storage", systemImage: "internaldrive")
                .font(.headline)
            if let snap = storageSnapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "Store",
                        systemImage: "cylinder.split.1x2",
                        currentValue: StorageSnapshot.formatMB(snap.storeBytes),
                        samples: [],
                        helpText: "Size of Ditto's document store database files (ditto_store/ directory). Contains all collection documents, indexes, and CRDT state."
                    )
                    MetricCard(
                        title: "Replication",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        currentValue: StorageSnapshot.formatMB(snap.replicationBytes),
                        samples: [],
                        helpText: "Sync state stored per connected peer (ditto_replication/ directory). Grows with the number of peers synced with and the amount of data exchanged."
                    )
                    MetricCard(
                        title: "Attachments",
                        systemImage: "paperclip",
                        currentValue: StorageSnapshot.formatMB(snap.attachmentsBytes),
                        samples: [],
                        helpText: "Binary attachments stored by Ditto (ditto_attachments/ directory)."
                    )
                    MetricCard(
                        title: "Auth",
                        systemImage: "lock",
                        currentValue: StorageSnapshot.formatMB(snap.authBytes),
                        samples: [],
                        helpText: "Authentication and identity credential files (ditto_auth/ directory). Includes certificate and token CBOR files."
                    )
                    MetricCard(
                        title: "SQLite WAL/SHM",
                        systemImage: "cylinder",
                        currentValue: StorageSnapshot.formatMB(snap.walShmBytes),
                        samples: [],
                        helpText: "Write-Ahead Log and Shared Memory files used by SQLite for transaction journaling. Present across all ditto_* directories. Shrinks after a checkpoint."
                    )
                    MetricCard(
                        title: "Logging",
                        systemImage: "doc.plaintext",
                        currentValue: StorageSnapshot.formatMB(snap.logsBytes),
                        samples: [],
                        helpText: "Ditto SDK log files (ditto_logs/ directory). Includes active .log and rotated .log.gz archives."
                    )
                    MetricCard(
                        title: "Other",
                        systemImage: "archivebox",
                        currentValue: StorageSnapshot.formatMB(snap.otherBytes),
                        samples: [],
                        helpText: "Remaining Ditto files: metrics, system info, lock files, and other internal data not covered by the categories above."
                    )
                }
                if !snap.collectionBreakdown.isEmpty {
                    Label("Collections (\(snap.collectionBreakdown.count))", systemImage: "tablecells")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(snap.collectionBreakdown) { col in
                            MetricCard(
                                title: col.name,
                                systemImage: "doc.text",
                                currentValue: StorageSnapshot.formatMB(col.cborPayloadBytes),
                                samples: [],
                                helpText: "\(col.documentCount) documents. Size estimated from CBOR payload — Ditto's native binary format, read via cborData(). Does not include SQLite row overhead, CRDT history, or index entries."
                            )
                        }
                    }
                }
            } else {
                ProgressView("Computing storage…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Refresh

    private func runRefreshLoop() async {
        while !Task.isCancelled {
            await refreshMetrics()
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }

    private func refreshMetrics() async {
        let pSnap = MetricsRepository.processMetricSnapshot()
        let qSnap = await MetricsRepository.queryMetricSnapshot()
        let latencySamps = await MetricsRepository.samples(for: "edge_studio.query.latency_ms")
        let sSnap = try? await StorageRepository.fetchStorageSnapshot()
        processSnapshot = pSnap
        querySnapshot = qSnap
        queryLatencySamples = latencySamps
        storageSnapshot = sSnap
        lastUpdated = Date()
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824.0
        let mb = bytes / 1_048_576.0
        let kb = bytes / 1024.0
        if gb >= 1.0 { return String(format: "%.2f GB", gb) }
        if mb >= 1.0 { return String(format: "%.1f MB", mb) }
        if kb >= 1.0 { return String(format: "%.0f KB", kb) }
        return String(format: "%.0f B", bytes)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func formatLatency(_ ms: Double) -> String {
        if ms < 1.0 { return "<1ms" }
        if ms < 1000.0 { return String(format: "%.1fms", ms) }
        return String(format: "%.2fs", ms / 1000.0)
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        return "\(Int(elapsed / 60))m ago"
    }
}
