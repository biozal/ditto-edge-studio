import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogEntryContext Tests")
struct LogEntryContextTests {
    // MARK: - Helpers

    /// A buffer of `count` entries whose messages are their index, so the
    /// assertions can talk about position without depending on ids.
    private func buffer(count: Int, level: DittoLogLevel = .info) -> [LogEntry] {
        (0 ..< count).map { index in
            LogEntry(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                level: level,
                message: "line-\(index)",
                component: .sync,
                source: .dittoSDK,
                rawLine: "line-\(index)"
            )
        }
    }

    // MARK: - Happy path

    @Test("Slices the default five entries either side")
    func slicesFiveEitherSide() {
        // Arrange
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(entries[10].id, in: entries)

        // Assert
        #expect(context.before.map(\.message) == ["line-5", "line-6", "line-7", "line-8", "line-9"])
        #expect(context.after.map(\.message) == ["line-11", "line-12", "line-13", "line-14", "line-15"])
    }

    @Test("The focused entry is never included in either side")
    func focusedEntryIsExcluded() {
        // Arrange
        let entries = buffer(count: 20)
        let focused = entries[10]

        // Act
        let context = LogEntryContext.around(focused.id, in: entries)

        // Assert — the row renders the focused entry itself between the two
        // groups, so including it here would print it twice.
        #expect(!context.before.contains { $0.id == focused.id })
        #expect(!context.after.contains { $0.id == focused.id })
    }

    @Test("Honours a custom radius")
    func honoursCustomRadius() {
        // Arrange
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(entries[10].id, in: entries, radius: 2)

        // Assert
        #expect(context.before.map(\.message) == ["line-8", "line-9"])
        #expect(context.after.map(\.message) == ["line-11", "line-12"])
    }

    // MARK: - Boundaries

    @Test("Clamps at the start of the buffer")
    func clampsAtStart() {
        // Arrange
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(entries[2].id, in: entries)

        // Assert
        #expect(context.before.map(\.message) == ["line-0", "line-1"])
        #expect(context.after.count == 5)
    }

    @Test("Clamps at the end of the buffer")
    func clampsAtEnd() {
        // Arrange — expanding the newest row is the common case, and it must
        // not trap on the upper bound.
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(entries[19].id, in: entries)

        // Assert
        #expect(context.before.map(\.message) == ["line-14", "line-15", "line-16", "line-17", "line-18"])
        #expect(context.after.isEmpty)
    }

    @Test("A single-entry buffer yields empty context")
    func singleEntryBuffer() {
        // Arrange
        let entries = buffer(count: 1)

        // Act
        let context = LogEntryContext.around(entries[0].id, in: entries)

        // Assert
        #expect(context.isEmpty)
    }

    @Test("A buffer smaller than the radius returns everything else")
    func bufferSmallerThanRadius() {
        // Arrange
        let entries = buffer(count: 3)

        // Act
        let context = LogEntryContext.around(entries[1].id, in: entries)

        // Assert
        #expect(context.before.map(\.message) == ["line-0"])
        #expect(context.after.map(\.message) == ["line-2"])
    }

    // MARK: - Missing entry

    @Test("An id absent from the buffer yields empty context, not a crash")
    func absentIDYieldsEmpty() {
        // Arrange — the buffers are capped, so an expanded entry can be trimmed
        // away underneath the user; switching source replaces the buffer too.
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(UUID(), in: entries)

        // Assert
        #expect(context.isEmpty)
    }

    @Test("An empty buffer yields empty context")
    func emptyBufferYieldsEmpty() {
        #expect(LogEntryContext.around(UUID(), in: []).isEmpty)
    }

    @Test("A non-positive radius yields empty context")
    func nonPositiveRadiusYieldsEmpty() {
        // Arrange
        let entries = buffer(count: 20)

        // Act & Assert
        #expect(LogEntryContext.around(entries[10].id, in: entries, radius: 0).isEmpty)
        #expect(LogEntryContext.around(entries[10].id, in: entries, radius: -3).isEmpty)
    }

    // MARK: - The point of the feature

    @Test("Context comes from the unfiltered buffer, so it can cross a filter")
    func contextCrossesTheFilter() {
        // Arrange — one error surrounded by info lines. This is what expanding
        // an error in the Errors tab must show: the info lines that explain it.
        // Slicing the filtered list would return the other errors instead, which
        // is exactly the information the user already had.
        var entries = buffer(count: 11)
        let errorEntry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 5),
            level: .error,
            message: "boom",
            component: .sync,
            source: .dittoSDK,
            rawLine: "boom"
        )
        entries[5] = errorEntry

        // Act
        let context = LogEntryContext.around(errorEntry.id, in: entries)

        // Assert
        #expect(context.before.allSatisfy { $0.level == .info })
        #expect(context.after.allSatisfy { $0.level == .info })
        #expect(context.before.count == 5)
        #expect(context.after.count == 5)
    }

    @Test("Ordering is preserved on both sides")
    func orderingIsPreserved() {
        // Arrange
        let entries = buffer(count: 20)

        // Act
        let context = LogEntryContext.around(entries[10].id, in: entries)

        // Assert — the drawer prints before + focused + after as one run, so
        // both sides have to stay in buffer order.
        #expect(context.before.map(\.timestamp) == context.before.map(\.timestamp).sorted())
        #expect(context.after.map(\.timestamp) == context.after.map(\.timestamp).sorted())
        #expect(context.before.last?.timestamp ?? .distantPast < entries[10].timestamp)
        #expect(context.after.first?.timestamp ?? .distantFuture > entries[10].timestamp)
    }
}
