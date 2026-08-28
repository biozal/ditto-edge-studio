import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogPatternEngine Tests")
struct LogPatternEngineTests {
    // MARK: - Helpers

    private func makeEntry(
        level: DittoLogLevel = .info,
        message: String = "hello",
        component: LogComponent = .sync
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: level,
            message: message,
            component: component,
            source: .dittoSDK,
            rawLine: ""
        )
    }

    private func makePattern(
        key: String,
        pattern: String,
        severity: Int = 3,
        recommendation: String = "fix it",
        levelFilter: String? = nil,
        tagFilter: String? = nil,
        userTag: String? = nil,
        source: PatternSource = .bundled
    ) -> LogPattern {
        LogPattern(
            key: key,
            body: LogPatternBody(
                pattern: pattern,
                severity: severity,
                recommendation: recommendation,
                levelFilter: levelFilter,
                tagFilter: tagFilter,
                userTag: userTag
            ),
            levelFilter: parseLogLevelFilter(levelFilter),
            source: source
        )
    }

    // MARK: - Level filter token parsing

    @Test("level filter tokens map to SDK levels including extension spellings")
    func levelFilterTokens() {
        #expect(parseLogLevelFilter(nil) == nil)
        #expect(parseLogLevelFilter("") == nil)
        #expect(parseLogLevelFilter("error") == .error)
        #expect(parseLogLevelFilter("warn") == .warning)
        #expect(parseLogLevelFilter("warning") == .warning)
        #expect(parseLogLevelFilter("info") == .info)
        #expect(parseLogLevelFilter("debug") == .debug)
        #expect(parseLogLevelFilter("trace") == .verbose)
        #expect(parseLogLevelFilter("verbose") == .verbose)
        #expect(parseLogLevelFilter("ERROR") == .error)
        #expect(parseLogLevelFilter("bogus") == nil)
    }

    // MARK: - Scan semantics

    @Test("message matching is case-insensitive")
    func caseInsensitiveMatch() {
        let engine = LogPatternEngine(patterns: ["p": makePattern(key: "p", pattern: "deadlock")])
        let matches = engine.scan(makeEntry(message: "possible DEADLOCK detected"))
        #expect(matches.count == 1)
        #expect(matches[0].key == "p")
    }

    @Test("level filter is an exact equality, not at-least")
    func exactLevelFilter() {
        let engine = LogPatternEngine(patterns: [
            "err": makePattern(key: "err", pattern: "deadlock", levelFilter: "error"),
            "wrn": makePattern(key: "wrn", pattern: "deadlock", levelFilter: "warn"),
        ])
        // An error line must not fire the warn-scoped variant.
        let errorMatches = engine.scan(makeEntry(level: .error, message: "deadlock elapsed"))
        #expect(errorMatches.map(\.key) == ["err"])
        let warnMatches = engine.scan(makeEntry(level: .warning, message: "deadlock elapsed"))
        #expect(warnMatches.map(\.key) == ["wrn"])
    }

    @Test("tag filter matches against the component display name")
    func tagFilterScoping() {
        let engine = LogPatternEngine(patterns: [
            "p": makePattern(key: "p", pattern: "msg", tagFilter: "Sync"),
        ])
        #expect(!engine.scan(makeEntry(message: "msg here", component: .sync)).isEmpty)
        #expect(engine.scan(makeEntry(message: "msg here", component: .store)).isEmpty)
    }

    @Test("user tag is carried on the compiled pattern")
    func userTagCarried() {
        let engine = LogPatternEngine(patterns: [
            "p": makePattern(key: "p", pattern: "msg", userTag: "auth-flow"),
        ])
        #expect(engine.scan(makeEntry(message: "msg here"))[0].userTag == "auth-flow")
    }

    @Test("scanAll returns chronological matches across entries")
    func scanAllOrder() {
        let engine = LogPatternEngine(patterns: ["p": makePattern(key: "p", pattern: "err")])
        let entries = [
            makeEntry(message: "nothing"),
            makeEntry(message: "err one"),
            makeEntry(message: "err two"),
        ]
        let matches = engine.scanAll(entries)
        #expect(matches.count == 2)
        #expect(matches[0].entry.message == "err one")
        #expect(matches[1].entry.message == "err two")
    }

    @Test("scanAll caps the window to the newest maxEntries")
    func scanAllWindowCap() {
        let engine = LogPatternEngine(patterns: ["p": makePattern(key: "p", pattern: "hit")])
        let entries = (1...10).map { i in
            makeEntry(message: i <= 5 ? "hit \(i)" : "miss \(i)")
        }
        // Only the last 5 entries (all "miss") are scanned.
        #expect(engine.scanAll(entries, maxEntries: 5).isEmpty)
        #expect(engine.scanAll(entries, maxEntries: 10).count == 5)
    }

    @Test("testMatch respects pattern, level and tag filters")
    func testMatchSemantics() {
        let body = LogPatternBody(
            pattern: "Query too big",
            severity: 5,
            recommendation: "split the query",
            levelFilter: "warn",
            tagFilter: "Sync"
        )
        #expect(LogPatternEngine.testMatch(body: body, level: .warning, tag: "Sync", message: "Query too big. Nope"))
        #expect(!LogPatternEngine.testMatch(body: body, level: .error, tag: "Sync", message: "Query too big. Nope"))
        #expect(!LogPatternEngine.testMatch(body: body, level: .warning, tag: "Store", message: "Query too big. Nope"))
        #expect(!LogPatternEngine.testMatch(body: body, level: .warning, tag: "Sync", message: "unrelated"))
    }

    // MARK: - Validation (ReDoS guards)

    @Test("blank key is rejected")
    func blankKeyRejected() {
        #expect(LogPatternEngine.rejectReason(key: "  ", body: validBody(), source: .bundled) != nil)
    }

    @Test("empty pattern and recommendation are rejected")
    func emptyFieldsRejected() {
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(pattern: ""), source: .bundled) != nil)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(recommendation: "  "), source: .bundled) != nil)
    }

    @Test("severity outside 1-5 is rejected")
    func severityRangeRejected() {
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(severity: 0), source: .bundled) != nil)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(severity: 6), source: .bundled) != nil)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(severity: 1), source: .bundled) == nil)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(severity: 5), source: .bundled) == nil)
    }

    @Test("user patterns are rejected beyond the length cap; bundled are not")
    func lengthCapUserOnly() {
        let longPattern = String(repeating: "a", count: LogPatternEngine.maxUserPatternLength + 1)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(pattern: longPattern), source: .user) != nil)
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(pattern: longPattern), source: .bundled) == nil)
    }

    @Test("nested quantifiers are rejected for user patterns only")
    func nestedQuantifierRejected() {
        let body = validBody(pattern: "(a+)+")
        #expect(
            LogPatternEngine.rejectReason(key: "k", body: body, source: .user)
                == "pattern nests a quantifier inside a quantified group, which can backtrack exponentially"
        )
        #expect(LogPatternEngine.rejectReason(key: "k", body: body, source: .bundled) == nil)
    }

    @Test("invalid regex is rejected")
    func invalidRegexRejected() {
        #expect(LogPatternEngine.rejectReason(key: "k", body: validBody(pattern: "(["), source: .user) != nil)
    }

    @Test("unknown level_filter token is rejected")
    func unknownLevelTokenRejected() {
        let body = LogPatternBody(
            pattern: "boom",
            severity: 3,
            recommendation: "fix it",
            levelFilter: "critikal"
        )
        #expect(
            LogPatternEngine.rejectReason(key: "k", body: body, source: .user)
                == "unknown level_filter 'critikal' (expected error|warning|info|debug|verbose)"
        )
        let valid = LogPatternBody(pattern: "boom", severity: 3, recommendation: "fix it", levelFilter: "error")
        #expect(LogPatternEngine.rejectReason(key: "k", body: valid, source: .user) == nil)
    }

    @Test("invalid tag_filter regex is rejected")
    func invalidTagFilterRejected() {
        let body = LogPatternBody(pattern: "boom", severity: 3, recommendation: "fix it", tagFilter: "([")
        let reason = LogPatternEngine.rejectReason(key: "k", body: body, source: .bundled)
        #expect(reason?.hasPrefix("tag_filter is not a valid regex") == true)
    }

    @Test("nested quantifier tag_filter is rejected for user patterns only")
    func nestedQuantifierTagFilterRejected() {
        let body = LogPatternBody(pattern: "boom", severity: 3, recommendation: "fix it", tagFilter: "(a+)+")
        #expect(
            LogPatternEngine.rejectReason(key: "k", body: body, source: .user)?
                .hasPrefix("tag_filter nests a quantifier") == true
        )
        #expect(LogPatternEngine.rejectReason(key: "k", body: body, source: .bundled) == nil)
    }

    @Test("user tag is trimmed at compile time")
    func userTagTrimmed() {
        let pattern = makePattern(key: "p", pattern: "msg", userTag: "  auth-flow  ")
        let engine = LogPatternEngine(patterns: ["p": pattern])
        #expect(engine.scan(makeEntry(message: "a msg"))[0].userTag == "auth-flow")
    }

    @Test("bundled catalog file parses and validates cleanly")
    func bundledCatalogValidates() throws {
        let bodies = try loadBundledCatalog()
        #expect(bodies.count == 13)
        for (key, body) in bodies {
            #expect(LogPatternEngine.rejectReason(key: key, body: body, source: .bundled) == nil)
        }
    }

    // MARK: - Catalog fixtures (ported from the VS Code extension's
    //         src/logAnalyzer/patterns/__fixtures__)

    private func catalogEngine() throws -> LogPatternEngine {
        let bodies = try loadBundledCatalog()
        var patterns: [String: LogPattern] = [:]
        for (key, body) in bodies {
            patterns[key] = LogPattern(
                key: key,
                body: body,
                levelFilter: parseLogLevelFilter(body.levelFilter),
                source: .bundled
            )
        }
        return LogPatternEngine(patterns: patterns)
    }

    private func loadBundledCatalog() throws -> [String: LogPatternBody] {
        // Tests run against the test bundle, not the app bundle — locate the
        // resource relative to this source file instead.
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Logging/
            .deletingLastPathComponent() // EdgeStudioUnitTests/
            .deletingLastPathComponent() // SwiftUI/
            .appendingPathComponent("EdgeStudio/Resources/problem_patterns.json")
        let data = try Data(contentsOf: resourceURL)
        return try JSONDecoder().decode([String: LogPatternBody].self, from: data)
    }

    private func sdkEntry(_ level: DittoLogLevel, _ message: String) -> LogEntry {
        makeEntry(level: level, message: message, component: .sync)
    }

    @Test("catalog contains the four v5-1 replication/eviction patterns")
    func catalogContainsNewPatterns() throws {
        let keys = try catalogEngine().compiled.map(\.key)
        #expect(keys.count == 13)
        for key in [
            "replication_metadata_corrupt_recovery",
            "replication_consecutive_resets",
            "replication_reset_local_trigger",
            "post_eviction_cleanup_frequent",
        ] {
            #expect(keys.contains(key), Comment(rawValue: "\(key) missing from catalog"))
        }
    }

    @Test("fixture — metadata corrupt recovery matches at WARN only")
    func fixtureMetadataCorrupt() throws {
        let engine = try catalogEngine()
        let message = "session metadata database was corrupt on open; deleting and reinitializing "
            + "this peer's metadata, then retrying "
            + "{\"remote.peer_id\":\"peer-9f2a\",\"error\":\"corruption: checksum mismatch\"}"
        #expect(
            engine.scan(sdkEntry(.warning, message)).map(\.key) == ["replication_metadata_corrupt_recovery"]
        )
        #expect(engine.scan(sdkEntry(.info, message)).isEmpty)
    }

    @Test("fixture — consecutive resets match at WARN, first-reset INFO does not")
    func fixtureConsecutiveResets() throws {
        let engine = try catalogEngine()
        let warnMessage = "resetting replication state with remote peer; sync performance may be "
            + "temporarily degraded {\"consecutive_resets\":3}"
        let infoMessage = "resetting replication state with remote peer; sync performance may be temporarily degraded"
        #expect(
            engine.scan(sdkEntry(.warning, warnMessage)).map(\.key) == ["replication_consecutive_resets"])
        #expect(engine.scan(sdkEntry(.info, infoMessage)).isEmpty)
    }

    @Test("fixture — local-trigger reset matches at WARN, benign INFO does not")
    func fixtureLocalTriggerReset() throws {
        let engine = try catalogEngine()
        let warnMessage = "replication reset was triggered by local peer {\"error\":\"metadata was corrupt on open\"}"
        let infoMessage = "replication reset was triggered by local peer {\"error\":\"session forgotten\"}"
        #expect(
            engine.scan(sdkEntry(.warning, warnMessage)).map(\.key) == ["replication_reset_local_trigger"])
        #expect(engine.scan(sdkEntry(.info, infoMessage)).isEmpty)
    }

    @Test("fixture — post-eviction cleanup matches at INFO (no level filter)")
    func fixturePostEviction() throws {
        let engine = try catalogEngine()
        let message = "post-eviction session cleanup is running too frequently, which may cause "
            + "excessive local overhead {\"run_count\":3,\"window_ms\":30000}"
        #expect(
            engine.scan(sdkEntry(.info, message)).map(\.key) == ["post_eviction_cleanup_frequent"]
        )
    }

    private func validBody(
        pattern: String = "boom",
        severity: Int = 3,
        recommendation: String = "fix it"
    ) -> LogPatternBody {
        LogPatternBody(pattern: pattern, severity: severity, recommendation: recommendation)
    }
}
