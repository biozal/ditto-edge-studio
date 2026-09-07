import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogFileParser Tests")
struct LogFileParserTests {
    // Helper: build a minimal JSONL line with the given timestamp string
    private func jsonlLine(timestamp: String, level: String = "info", message: String = "test") -> String {
        "{\"timestamp\":\"\(timestamp)\",\"level\":\"\(level)\",\"target\":\"test\",\"message\":\"\(message)\"}"
    }

    @Test
    func `JSONL with fractional seconds parses to correct Date`() throws {
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00.123Z")
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        let entry = entries[0]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 13)
        #expect(components.minute == 42)
        #expect(components.second == 0)
    }

    @Test
    func `JSONL without fractional seconds parses to correct Date (not Date())`() throws {
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00Z")
        let before = Date()
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)
        let after = Date()

        #expect(entries.count == 1)
        let ts = entries[0].timestamp
        // Must NOT be the current time (i.e., fallback was not triggered)
        #expect(ts < before || ts > after, "timestamp should not equal Date() — fallback must not have fired")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: ts)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 13)
        #expect(components.minute == 42)
    }

    @Test
    func `JSONL with positive UTC offset parses to correct UTC Date`() throws {
        // 13:42:00+05:30 == 08:12:00 UTC
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00+05:30")
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entries[0].timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 8)
        #expect(components.minute == 12)
    }

    @Test
    func `CocoaLumberjack line with slash separators and UTC time parses to correct Date`() throws {
        // CL format: yyyy/MM/dd HH:mm:ss:SSS LEVEL [file:line]  Message
        let line = "2026/02/27 08:15:30:456 INFO [AppDelegate.swift:42]  App launched"
        let entries = parseCLInlineString(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 8)
        #expect(components.minute == 15)
        #expect(components.second == 30)
    }

    @Test
    func `Unparseable JSONL line still produces an entry with message preserved`() {
        // Valid JSON that's missing required fields produces a best-effort entry
        let line = "{\"foo\":\"bar\",\"message\":\"hello from unparseable\"}"
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        #expect(entries[0].message.contains("hello from unparseable"))
    }

    // MARK: - SDK log directory resolution

    //
    // The persistence directory is NOT the log directory: the SDK writes to
    // `<persistenceDirectory>/ditto_logs/`, and `parseDirectory` is non-recursive.
    // Handing it the root is what made the MCP `get_ditto_logs` tool return an empty
    // array on every build, silently, for as long as it shipped.

    /// A persistence directory laid out the way the SDK lays one out.
    private func makePersistenceDirectory(logDirectoryName: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LogFileParserTests-\(UUID().uuidString)")
        let fm = FileManager.default
        // Siblings the SDK really creates, so a non-recursive scan of the root has
        // plenty to find and still no logs.
        for sibling in ["ditto_store", "ditto_replication", "ditto_attachments"] {
            try fm.createDirectory(at: root.appendingPathComponent(sibling), withIntermediateDirectories: true)
        }
        if let logDirectoryName {
            let logs = root.appendingPathComponent(logDirectoryName)
            try fm.createDirectory(at: logs, withIntermediateDirectories: true)
            let line = jsonlLine(timestamp: "2026-02-27T13:42:00.123Z", message: "hello from the sdk")
            try line.write(to: logs.appendingPathComponent("ditto.log"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test
    func `parseDittoLogs finds the SDK's logs under ditto_logs/`() throws {
        let root = try makePersistenceDirectory(logDirectoryName: "ditto_logs")
        defer { try? FileManager.default.removeItem(at: root) }

        // The defect: the root itself parses to nothing...
        #expect(LogFileParser.parseDirectory(root).isEmpty)
        // ...while the persistence-directory entry point finds the logs.
        let entries = LogFileParser.parseDittoLogs(persistenceDirectory: root)
        #expect(entries.count == 1)
        #expect(entries.first?.message == "hello from the sdk")
    }

    @Test
    func `parseDittoLogs falls back to the older logs/ layout`() throws {
        let root = try makePersistenceDirectory(logDirectoryName: "logs")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LogFileParser.parseDittoLogs(persistenceDirectory: root).count == 1)
        #expect(LogFileParser.sdkLogDirectory(in: root)?.lastPathComponent == "logs")
    }

    @Test
    func `ditto_logs wins over logs when both are present`() throws {
        let root = try makePersistenceDirectory(logDirectoryName: "ditto_logs")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("logs"), withIntermediateDirectories: true
        )

        #expect(LogFileParser.sdkLogDirectory(in: root)?.lastPathComponent == "ditto_logs")
    }

    @Test
    func `A database with no log directory resolves to nil rather than guessing`() throws {
        let root = try makePersistenceDirectory(logDirectoryName: nil)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LogFileParser.sdkLogDirectory(in: root) == nil)
        #expect(LogFileParser.parseDittoLogs(persistenceDirectory: root).isEmpty)
    }
}

// MARK: - Test helpers for writing CocoaLumberjack inline strings to a temp file

private func parseCLInlineString(_ content: String) -> [LogEntry] {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".log")
    guard (try? content.write(to: tempURL, atomically: true, encoding: .utf8)) != nil else { return [] }
    defer { try? FileManager.default.removeItem(at: tempURL) }
    return LogFileParser.parseCocoaLumberjackFiles([tempURL])
}
