import DittoSwift
import Foundation

/// Aggregate statistics over a window of log entries — the data behind the
/// Summary header, the three histograms, and the filter-tab badges.
///
/// Pure value type with no I/O and no UI. `compute` is a single pass over the
/// entry window plus the pattern matches that were already produced for the
/// Problems section, so it adds no extra scanning cost. Run it off the main
/// actor (`LoggingDetailView` does, alongside the pattern scan).
///
/// Parity note: this mirrors what the VS Code extension's `LogAnalyzerService`
/// maintains incrementally at ingest time. Mobile buffers are two orders of
/// magnitude smaller than the extension's 50k line buffer, so recomputing on a
/// throttled change is simpler and fast enough; the *outputs* are what must
/// match across platforms, not the strategy for producing them.
struct LogAnalytics: Sendable {
    // MARK: - Counts

    /// ## `problems` vs `problemEntries`
    ///
    /// `problems` counts pattern **matches**: a line matched by three patterns
    /// contributes three. `problemEntries` counts **distinct entries** with at
    /// least one match. They diverge, and the difference is not cosmetic —
    /// the Problems filter tab can only ever list distinct entries, so a badge
    /// showing `problems` promises rows the table cannot produce. Badges use
    /// `problemEntries` / `criticalEntries`; the Summary header shows
    /// `problems`, which is the honest "how much went wrong" number.
    struct Counts: Sendable, Equatable {
        var critical = 0
        var errors = 0
        var warnings = 0
        var problems = 0
        var problemEntries = 0
        var criticalEntries = 0
        var totalLines = 0
    }

    // MARK: - Histogram bins

    struct VolumeBin: Sendable, Equatable, Identifiable {
        let startMs: Int64
        var counts: [DittoLogLevel: Int]

        var id: Int64 {
            startMs
        }

        var total: Int {
            counts.values.reduce(0, +)
        }

        var start: Date {
            Date(timeIntervalSince1970: Double(startMs) / 1000)
        }
    }

    struct ProblemBin: Sendable, Equatable, Identifiable {
        let startMs: Int64
        var count: Int
        var maxSeverity: Int

        var id: Int64 {
            startMs
        }

        var start: Date {
            Date(timeIntervalSince1970: Double(startMs) / 1000)
        }
    }

    struct DurationBin: Sendable, Equatable, Identifiable {
        let label: String
        var count: Int

        var id: String {
            label
        }

        /// True when no connection landed in this bucket.
        ///
        /// Named `isEmpty` deliberately rather than `isPopulated`: SwiftLint's
        /// `empty_count` rule rewrites `bin.count == 0` at call sites into
        /// `bin.isEmpty`, so the type has to actually offer it or the
        /// autocorrected code stops compiling.
        var isEmpty: Bool {
            count < 1
        }
    }

    // MARK: - Stored properties

    var counts = Counts()
    var volumeByLevel: [VolumeBin] = []
    var problemsOverTime: [ProblemBin] = []
    var connectionDurations: [DurationBin] = Self.emptyDurationBins
    var sessions: [ConnectionSession] = []
    var startTime: Date?
    var endTime: Date?
    var sdkVersion: String?
    var tags: [String] = []

    /// True when there is nothing worth rendering — lets the view skip the
    /// whole analytics section rather than draw empty chrome.
    var isEmpty: Bool {
        counts.totalLines == 0
    }

    /// `06:50:47 → 20:35:08 (13.7h)`, or nil when the window has no span.
    var rangeDescription: String? {
        guard let startTime, let endTime else { return nil }
        let formatter = Self.rangeTimeFormatter
        let span = endTime.timeIntervalSince(startTime)
        return "\(formatter.string(from: startTime)) → \(formatter.string(from: endTime)) (\(Self.humanDuration(span)))"
    }

    // MARK: - Binning constants

    //
    // Normative for all three platforms — see `docs/LOG_ANALYZER_SPEC.md`.
    // Sourced from the VS Code extension's `Histograms.ts` (`NICE_BINS_MS`,
    // `DURATION_BINS`). `LogAnalyticsTests` pins these values so a change here
    // is a deliberate, cross-platform decision rather than a local drift.

    /// Candidate bin widths, in milliseconds, coarsest last.
    static let volumeBinCandidatesMs: [Int64] = [
        1000, 5000, 30000, 60000, 300_000, 600_000, 1_800_000
    ]

    /// Bin count the width picker aims for across the full time range.
    static let volumeBinTargetBuckets = 40

    /// Upper bounds, in seconds, for the connection-duration buckets. The final
    /// bucket is unbounded.
    static let durationBins: [(label: String, maxSeconds: TimeInterval)] = [
        ("0–1s", 1),
        ("1–5s", 5),
        ("5–30s", 30),
        ("30s–5m", 300),
        ("5m+", .infinity)
    ]

    static var emptyDurationBins: [DurationBin] {
        durationBins.map { DurationBin(label: $0.label, count: 0) }
    }

    /// Picks the finest bin width that keeps the bucket count at or below
    /// `volumeBinTargetBuckets`, so a 10-minute window and a 14-hour window both
    /// render a readable number of bars.
    static func pickBinWidthMs(rangeMs: Int64, target: Int = volumeBinTargetBuckets) -> Int64 {
        let want = Double(max(rangeMs, 1)) / Double(max(target, 1))
        for candidate in volumeBinCandidatesMs where Double(candidate) >= want {
            return candidate
        }
        return volumeBinCandidatesMs.last ?? 1_800_000
    }

    // MARK: - Compute

    /// Aggregates `entries` (and the `matches` already produced for them by
    /// `LogPatternEngine`) into a full analytics snapshot.
    ///
    /// - Parameters:
    ///   - entries: the active source's buffer, in any order.
    ///   - matches: pattern matches over the same entries. Matches whose entry
    ///     is outside `entries` are still counted toward `problems` — the
    ///     pattern scan and the display window can legitimately differ in size.
    static func compute(entries: [LogEntry], matches: [LogPatternEngine.Match]) -> LogAnalytics {
        var result = LogAnalytics()
        guard !entries.isEmpty else { return result }

        // ── Pass 1: per-entry counts, time range, tags, SDK version ──────────
        var counts = Counts()
        counts.totalLines = entries.count
        var earliest = entries[0].timestamp
        var latest = entries[0].timestamp
        var tagSet = Set<String>()
        var sdkVersion: String?

        for entry in entries {
            switch entry.level {
            case .error: counts.errors += 1
            case .warning: counts.warnings += 1
            default: break
            }
            if entry.timestamp < earliest {
                earliest = entry.timestamp
            }
            if entry.timestamp > latest {
                latest = entry.timestamp
            }
            tagSet.insert(entry.component.rawValue)
            // Guarded on nil so this is one substring probe per line until the
            // first hit, not a regex on every line for the life of the view.
            if sdkVersion == nil, entry.message.contains("sdk.version=") {
                sdkVersion = extractSDKVersion(from: entry.message)
            }
        }

        // ── Problem accounting ───────────────────────────────────────────────
        var problemEntryIDs = Set<UUID>()
        var criticalEntryIDs = Set<UUID>()
        for match in matches {
            counts.problems += 1
            problemEntryIDs.insert(match.entry.id)
            if match.pattern.severity >= 5 {
                counts.critical += 1
                criticalEntryIDs.insert(match.entry.id)
            }
        }
        counts.problemEntries = problemEntryIDs.count
        counts.criticalEntries = criticalEntryIDs.count

        // ── Histograms ───────────────────────────────────────────────────────
        let rangeMs = Int64(latest.timeIntervalSince(earliest) * 1000)
        let binMs = pickBinWidthMs(rangeMs: max(rangeMs, 1000))

        var volume: [Int64: [DittoLogLevel: Int]] = [:]
        for entry in entries {
            let bin = binStart(entry.timestamp, binMs: binMs)
            volume[bin, default: [:]][entry.level, default: 0] += 1
        }

        var problemBins: [Int64: (count: Int, maxSeverity: Int)] = [:]
        for match in matches {
            let bin = binStart(match.entry.timestamp, binMs: binMs)
            var current = problemBins[bin] ?? (count: 0, maxSeverity: 1)
            current.count += 1
            current.maxSeverity = max(current.maxSeverity, match.pattern.severity)
            problemBins[bin] = current
        }

        let tracker = LogConnectionTracker.track(entries)

        result.counts = counts
        result.volumeByLevel = volume
            .sorted { $0.key < $1.key }
            .map { VolumeBin(startMs: $0.key, counts: $0.value) }
        result.problemsOverTime = problemBins
            .sorted { $0.key < $1.key }
            .map { ProblemBin(startMs: $0.key, count: $0.value.count, maxSeverity: $0.value.maxSeverity) }
        result.connectionDurations = binDurations(tracker.closedSessions)
        result.sessions = tracker.sessions
        result.startTime = earliest
        result.endTime = latest
        result.sdkVersion = sdkVersion
        result.tags = tagSet.sorted()
        return result
    }

    /// Buckets closed sessions by duration. Empty buckets are retained so the
    /// chart's axis stays stable as data arrives instead of reflowing.
    static func binDurations(_ sessions: [ConnectionSession]) -> [DurationBin] {
        var bins = emptyDurationBins
        for session in sessions {
            guard let duration = session.duration else { continue }
            if let index = durationBins.firstIndex(where: { duration < $0.maxSeconds }) {
                bins[index].count += 1
            }
        }
        return bins
    }

    // MARK: - Helpers

    private static func binStart(_ date: Date, binMs: Int64) -> Int64 {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        return (ms / binMs) * binMs
    }

    /// Pulls `5.1.0` out of `… sdk.version=5.1.0 …`.
    static func extractSDKVersion(from message: String) -> String? {
        guard let range = message.range(of: "sdk.version=") else { return nil }
        let rest = message[range.upperBound...]
        let value = rest.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    static func humanDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "<1s"
        }
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        if seconds < 3600 {
            return String(format: "%.1fm", seconds / 60)
        }
        if seconds < 86400 {
            return String(format: "%.1fh", seconds / 3600)
        }
        return String(format: "%.1fd", seconds / 86400)
    }

    private static let rangeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
