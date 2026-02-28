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

    @Test("JSONL with fractional seconds parses to correct Date")
    func jsonlWithFractionalSeconds() {
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00.123Z")
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        let entry = entries[0]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 13)
        #expect(components.minute == 42)
        #expect(components.second == 0)
    }

    @Test("JSONL without fractional seconds parses to correct Date (not Date())")
    func jsonlWithoutFractionalSeconds() {
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00Z")
        let before = Date()
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)
        let after = Date()

        #expect(entries.count == 1)
        let ts = entries[0].timestamp
        // Must NOT be the current time (i.e., fallback was not triggered)
        #expect(ts < before || ts > after, "timestamp should not equal Date() — fallback must not have fired")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: ts)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 13)
        #expect(components.minute == 42)
    }

    @Test("JSONL with positive UTC offset parses to correct UTC Date")
    func jsonlWithPositiveOffset() {
        // 13:42:00+05:30 == 08:12:00 UTC
        let line = jsonlLine(timestamp: "2026-02-27T13:42:00+05:30")
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entries[0].timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 8)
        #expect(components.minute == 12)
    }

    @Test("CocoaLumberjack line with slash separators and UTC time parses to correct Date")
    func cocoaLumberjackSlashFormat() {
        // CL format: yyyy/MM/dd HH:mm:ss:SSS LEVEL [file:line]  Message
        let line = "2026/02/27 08:15:30:456 INFO [AppDelegate.swift:42]  App launched"
        let entries = parseCLInlineString(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 27)
        #expect(components.hour == 8)
        #expect(components.minute == 15)
        #expect(components.second == 30)
    }

    @Test("Unparseable JSONL line still produces an entry with message preserved")
    func unparseableJSONLLineProducesEntry() {
        // Valid JSON that's missing required fields produces a best-effort entry
        let line = "{\"foo\":\"bar\",\"message\":\"hello from unparseable\"}"
        let entries = LogFileParser.parseJSONLString(line, source: .dittoSDK)

        #expect(entries.count == 1)
        #expect(entries[0].message.contains("hello from unparseable"))
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
