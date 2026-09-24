import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogAnalytics Tests")
struct LogAnalyticsTests {
    // MARK: - Helpers

    private func entry(
        _ message: String = "hello",
        at seconds: TimeInterval = 0,
        level: DittoLogLevel = .info,
        component: LogComponent = .sync,
        rawLine: String? = nil
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: seconds),
            level: level,
            message: message,
            component: component,
            source: .dittoSDK,
            rawLine: rawLine ?? message
        )
    }

    private func pattern(key: String, severity: Int, userTag: String? = nil) -> LogPattern {
        LogPattern(
            key: key,
            body: LogPatternBody(
                pattern: ".", severity: severity, recommendation: "fix it", userTag: userTag
            ),
            levelFilter: nil,
            source: .bundled
        )
    }

    private func match(_ entry: LogEntry, key: String, severity: Int) -> LogPatternEngine.Match {
        guard let compiled = LogPatternEngine.compile(pattern(key: key, severity: severity)) else {
            Issue.record("pattern failed to compile")
            fatalError("unreachable — compile of a literal '.' pattern cannot fail")
        }
        return LogPatternEngine.Match(pattern: compiled, entry: entry)
    }

    private func connectionEntry(_ verb: String, at seconds: TimeInterval, id: String) -> LogEntry {
        entry(
            "physical connection \(verb) remote=pkA role=Client transport_type=Awdl connection_id=\(id)",
            at: seconds
        )
    }

    // MARK: - Empty input

    @Test("An empty buffer produces an empty, renderable snapshot")
    func emptyInput() {
        // Act
        let analytics = LogAnalytics.compute(entries: [], matches: [])

        // Assert
        #expect(analytics.isEmpty)
        #expect(analytics.counts.totalLines == 0)
        #expect(analytics.volumeByLevel.isEmpty)
        #expect(analytics.problemsOverTime.isEmpty)
        #expect(analytics.startTime == nil)
        #expect(analytics.rangeDescription == nil)
        // Duration buckets are always present so the chart axis never reflows.
        #expect(analytics.connectionDurations.count == LogAnalytics.durationBins.count)
    }

    // MARK: - Counts

    @Test("Level counts follow entry levels")
    func levelCounts() {
        // Arrange
        let entries = [
            entry(level: .error), entry(level: .error),
            entry(level: .warning),
            entry(level: .info), entry(level: .debug), entry(level: .verbose)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert
        #expect(analytics.counts.errors == 2)
        #expect(analytics.counts.warnings == 1)
        #expect(analytics.counts.totalLines == 6)
    }

    @Test("problems counts occurrences while problemEntries counts distinct entries")
    func problemsVersusProblemEntries() {
        // Arrange — one line matched by three patterns. `problems` is the
        // honest "how much went wrong" total; `problemEntries` is what the
        // Problems tab can actually list. A badge sourced from `problems`
        // would promise three rows where only one exists.
        let shared = entry("boom", at: 10, level: .error)
        let matches = [
            match(shared, key: "a", severity: 3),
            match(shared, key: "b", severity: 3),
            match(shared, key: "c", severity: 3)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: [shared], matches: matches)

        // Assert
        #expect(analytics.counts.problems == 3)
        #expect(analytics.counts.problemEntries == 1)
    }

    @Test("critical counts occurrences while criticalEntries counts distinct entries")
    func criticalVersusCriticalEntries() {
        // Arrange
        let shared = entry("boom", at: 10, level: .error)
        let other = entry("bang", at: 11, level: .error)
        let matches = [
            match(shared, key: "a", severity: 5),
            match(shared, key: "b", severity: 5),
            match(other, key: "c", severity: 4)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: [shared, other], matches: matches)

        // Assert
        #expect(analytics.counts.critical == 2)
        #expect(analytics.counts.criticalEntries == 1)
        #expect(analytics.counts.problemEntries == 2)
        #expect(analytics.counts.problems == 3)
    }

    @Test("Severity below 5 is not critical")
    func severityFourIsNotCritical() {
        // Arrange
        let logEntry = entry("uh oh", at: 1, level: .error)

        // Act
        let analytics = LogAnalytics.compute(
            entries: [logEntry], matches: [match(logEntry, key: "a", severity: 4)]
        )

        // Assert
        #expect(analytics.counts.critical == 0)
        #expect(analytics.counts.criticalEntries == 0)
        #expect(analytics.counts.problemEntries == 1)
    }

    // MARK: - Bin width selection
    //
    // These pin the normative values shared with Android and the VS Code
    // extension (docs/LOG_ANALYZER_SPEC.md). Changing one is a deliberate
    // cross-platform decision, not a local tweak.

    @Test("Bin width candidates match the cross-platform spec")
    func binCandidatesMatchSpec() {
        #expect(LogAnalytics.volumeBinCandidatesMs == [1_000, 5_000, 30_000, 60_000, 300_000, 600_000, 1_800_000])
        #expect(LogAnalytics.volumeBinTargetBuckets == 40)
    }

    // Ladder: the finest candidate whose width keeps the bucket count at or
    // below the 40-bucket target. Cases pair range → expected width:
    // 1s→1s, 40s→1s, 200s→5s, 20m→30s, 40m→60s, 13.7h→30m, overflow→30m.
    @Test("Bin width scales with the time range", arguments: zip(
        [Int64(1_000), 40_000, 200_000, 1_200_000, 2_400_000, 49_320_000, Int64.max / 2],
        [Int64(1_000), 1_000, 5_000, 30_000, 60_000, 1_800_000, 1_800_000]
    ))
    func binWidthScalesWithRange(rangeMs: Int64, expected: Int64) {
        #expect(LogAnalytics.pickBinWidthMs(rangeMs: rangeMs) == expected)
    }

    // MARK: - Volume histogram

    @Test("Entries are bucketed by bin start and split by level")
    func volumeBinning() {
        // Arrange — a 40s span bins at 1s, so these land in three buckets.
        let entries = [
            entry(at: 0, level: .info),
            entry(at: 0.5, level: .error),
            entry(at: 1, level: .info),
            entry(at: 40, level: .warning)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert
        #expect(analytics.volumeByLevel.count == 3)
        #expect(analytics.volumeByLevel.map(\.startMs) == [0, 1_000, 40_000])
        #expect(analytics.volumeByLevel[0].counts[.info] == 1)
        #expect(analytics.volumeByLevel[0].counts[.error] == 1)
        #expect(analytics.volumeByLevel[0].total == 2)
        #expect(analytics.volumeByLevel[2].counts[.warning] == 1)
    }

    @Test("Volume bins come back in ascending time order")
    func volumeBinsAreSorted() {
        // Arrange — deliberately unsorted input; bins are keyed by a dictionary
        // internally, whose iteration order is not stable.
        let entries = [entry(at: 30), entry(at: 0), entry(at: 15)]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert
        #expect(analytics.volumeByLevel.map(\.startMs) == analytics.volumeByLevel.map(\.startMs).sorted())
    }

    // MARK: - Problems histogram

    @Test("A problem bin reports the worst severity it contains")
    func problemBinTakesMaxSeverity() {
        // Arrange
        let first = entry("a", at: 0, level: .error)
        let second = entry("b", at: 0.2, level: .error)
        let matches = [
            match(first, key: "low", severity: 2),
            match(second, key: "high", severity: 5)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: [first, second], matches: matches)

        // Assert
        #expect(analytics.problemsOverTime.count == 1)
        #expect(analytics.problemsOverTime[0].count == 2)
        #expect(analytics.problemsOverTime[0].maxSeverity == 5)
    }

    // MARK: - Duration bucketing

    @Test("Duration buckets match the cross-platform spec")
    func durationBucketLabelsMatchSpec() {
        #expect(LogAnalytics.durationBins.map(\.label) == ["0–1s", "1–5s", "5–30s", "30s–5m", "5m+"])
    }

    // Buckets are half-open (`duration < maxSeconds`), so a value sitting
    // exactly on a boundary belongs to the next bucket up.
    @Test("Durations land in the right bucket at every boundary", arguments: zip(
        [0.0, 0.9, 1.0, 4.9, 5.0, 29.9, 30.0, 299.9, 300.0, 10_000.0] as [TimeInterval],
        [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]
    ))
    func durationBucketBoundaries(duration: TimeInterval, expectedIndex: Int) {
        // Arrange
        let session = ConnectionSession(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: duration),
            remotePeer: "pkA", transport: "Awdl", role: "Client", connectionId: "1"
        )

        // Act
        let bins = LogAnalytics.binDurations([session])

        // Assert
        #expect(bins[expectedIndex].count == 1)
        #expect(bins.reduce(0) { $0 + $1.count } == 1)
    }

    @Test("Open sessions are excluded from the duration buckets")
    func openSessionsAreNotBucketed() {
        // Arrange
        let open = ConnectionSession(
            start: Date(timeIntervalSince1970: 0), end: nil,
            remotePeer: "pkA", transport: "Awdl", role: "Client", connectionId: "1"
        )

        // Act
        let bins = LogAnalytics.binDurations([open])

        // Assert
        #expect(bins.reduce(0) { $0 + $1.count } == 0)
        #expect(bins.count == LogAnalytics.durationBins.count)
    }

    @Test("Connection sessions are reconstructed from the entry buffer")
    func connectionDurationsComeFromEntries() {
        // Arrange
        let entries = [
            connectionEntry("started", at: 0, id: "1"),
            connectionEntry("ended", at: 7, id: "1")
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert — 7s lands in the "5–30s" bucket.
        #expect(analytics.connectionDurations[2].count == 1)
        #expect(analytics.sessions.count == 1)
    }

    // MARK: - Metadata

    @Test("SDK version is pulled from the first line that announces it")
    func extractsSDKVersion() {
        // Arrange
        let entries = [
            entry("no version here", at: 0),
            entry("ditto starting sdk.version=5.1.0 build=release", at: 1),
            entry("later sdk.version=9.9.9", at: 2)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert — first hit wins; the field is latched.
        #expect(analytics.sdkVersion == "5.1.0")
    }

    @Test("SDK version extraction handles the value being last on the line")
    func extractsSDKVersionAtEndOfLine() {
        #expect(LogAnalytics.extractSDKVersion(from: "starting sdk.version=5.1.0") == "5.1.0")
        #expect(LogAnalytics.extractSDKVersion(from: "sdk.version=") == nil)
        #expect(LogAnalytics.extractSDKVersion(from: "nothing to see") == nil)
    }

    @Test("Tags are the distinct components, sorted")
    func tagsAreSortedComponents() {
        // Arrange
        let entries = [
            entry(at: 0, component: .sync),
            entry(at: 1, component: .auth),
            entry(at: 2, component: .sync)
        ]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert
        #expect(analytics.tags == ["Auth", "Sync"])
    }

    @Test("The time range spans the earliest and latest entry regardless of input order")
    func timeRangeIsOrderIndependent() {
        // Arrange
        let entries = [entry(at: 500), entry(at: 100), entry(at: 300)]

        // Act
        let analytics = LogAnalytics.compute(entries: entries, matches: [])

        // Assert
        #expect(analytics.startTime == Date(timeIntervalSince1970: 100))
        #expect(analytics.endTime == Date(timeIntervalSince1970: 500))
        #expect(analytics.rangeDescription?.contains("→") == true)
    }

    @Test("Human duration formatting picks a sensible unit", arguments: zip(
        [0.5, 45.0, 90.0, 5_400.0, 129_600.0] as [TimeInterval],
        ["<1s", "45s", "1.5m", "1.5h", "1.5d"]
    ))
    func humanDurationUnits(seconds: TimeInterval, expected: String) {
        #expect(LogAnalytics.humanDuration(seconds) == expected)
    }
}

// MARK: - Filter tab semantics

@Suite("LogFilterTab Tests")
struct LogFilterTabTests {
    private func entry(level: DittoLogLevel) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: level,
            message: "m",
            component: .sync,
            source: .dittoSDK,
            rawLine: "m"
        )
    }

    @Test("Badge counts use distinct-entry totals, not occurrence totals")
    func badgesUseDistinctEntryCounts() {
        // Arrange — a badge sourced from `problems` (5) or `critical` (3) would
        // promise more rows than the table can list.
        var counts = LogAnalytics.Counts()
        counts.totalLines = 100
        counts.errors = 7
        counts.warnings = 9
        counts.problems = 5
        counts.problemEntries = 2
        counts.critical = 3
        counts.criticalEntries = 1

        // Act & Assert
        #expect(LogFilterTab.all.badgeCount(counts) == 100)
        #expect(LogFilterTab.error.badgeCount(counts) == 7)
        #expect(LogFilterTab.warning.badgeCount(counts) == 9)
        #expect(LogFilterTab.problem.badgeCount(counts) == 2)
        #expect(LogFilterTab.critical.badgeCount(counts) == 1)
    }

    @Test("Level tabs match on level equality")
    func levelTabsMatchOnLevel() {
        let errorEntry = entry(level: .error)
        let warnEntry = entry(level: .warning)

        #expect(LogFilterTab.error.accepts(errorEntry, problemIDs: [], criticalIDs: []))
        #expect(!LogFilterTab.error.accepts(warnEntry, problemIDs: [], criticalIDs: []))
        #expect(LogFilterTab.warning.accepts(warnEntry, problemIDs: [], criticalIDs: []))
    }

    @Test("Problem and Critical tabs match on the scan's id sets")
    func problemTabsMatchOnIDSets() {
        // Arrange
        let hit = entry(level: .info)
        let miss = entry(level: .info)

        // Act & Assert
        #expect(LogFilterTab.problem.accepts(hit, problemIDs: [hit.id], criticalIDs: []))
        #expect(!LogFilterTab.problem.accepts(miss, problemIDs: [hit.id], criticalIDs: []))
        #expect(LogFilterTab.critical.accepts(hit, problemIDs: [hit.id], criticalIDs: [hit.id]))
        #expect(!LogFilterTab.critical.accepts(hit, problemIDs: [hit.id], criticalIDs: []))
    }

    @Test("All accepts everything")
    func allAcceptsEverything() {
        #expect(LogFilterTab.all.accepts(entry(level: .verbose), problemIDs: [], criticalIDs: []))
    }

    @Test("Only the All tab leaves the level chips in charge")
    func onlyAllDefersToLevelChips() {
        #expect(!LogFilterTab.all.overridesLevelChips)
        for tab in LogFilterTab.allCases where tab != .all {
            #expect(tab.overridesLevelChips)
        }
    }
}
