import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogEntry Filter Tests")
struct LogEntryFilterTests {
    // MARK: - Helpers

    private func makeEntry(secondsFromNow: TimeInterval) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSinceNow: secondsFromNow),
            level: .info,
            message: "test",
            component: .other,
            source: .application,
            rawLine: "test"
        )
    }

    private func makeEntry(at date: Date) -> LogEntry {
        LogEntry(
            timestamp: date,
            level: .info,
            message: "test",
            component: .other,
            source: .application,
            rawLine: "test"
        )
    }

    // MARK: - Tests

    @Test("Entry inside range returns true")
    func entryInsideRange() {
        let start = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let end = Date(timeIntervalSinceNow: 0)       // now
        let entry = makeEntry(secondsFromNow: -1800)  // 30 min ago — inside

        #expect(LogEntry.isWithinDateRange(entry, start: start, end: end) == true)
    }

    @Test("Entry before range start returns false")
    func entryBeforeRangeStart() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end = Date(timeIntervalSinceNow: 0)
        let entry = makeEntry(secondsFromNow: -7200) // 2 hours ago — before start

        #expect(LogEntry.isWithinDateRange(entry, start: start, end: end) == false)
    }

    @Test("Entry after range end returns false")
    func entryAfterRangeEnd() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end = Date(timeIntervalSinceNow: -1800) // 30 min ago
        let entry = makeEntry(secondsFromNow: -60)  // 1 min ago — after end

        #expect(LogEntry.isWithinDateRange(entry, start: start, end: end) == false)
    }

    @Test("Entry exactly at start boundary returns true (inclusive)")
    func entryAtStartBoundary() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end = Date(timeIntervalSinceNow: 0)
        let entry = makeEntry(at: start) // exactly at start

        #expect(LogEntry.isWithinDateRange(entry, start: start, end: end) == true)
    }

    @Test("Entry exactly at end boundary returns true (inclusive)")
    func entryAtEndBoundary() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end = Date(timeIntervalSinceNow: 0)
        let entry = makeEntry(at: end) // exactly at end

        #expect(LogEntry.isWithinDateRange(entry, start: start, end: end) == true)
    }

    @Test("Full-day range (midnight to 23:59:59) contains a midday entry")
    func fullDayRangeContainsMidday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        // end = 23:59:59 today
        let end = today.addingTimeInterval(86399)
        // midday = 12:00:00 today
        let midday = today.addingTimeInterval(43200)

        let entry = makeEntry(at: midday)

        #expect(LogEntry.isWithinDateRange(entry, start: today, end: end) == true)
    }
}
