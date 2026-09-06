import Foundation

/// The log entries immediately surrounding one focused entry.
///
/// ## Why this is sliced from the *unfiltered* buffer
///
/// The whole point of context is to show what the SDK was doing around a line,
/// which is almost always something the current filter hides. Slicing the
/// filtered display list instead would mean that expanding an error in the
/// Errors tab shows five other errors — the neighbours you already had, and
/// none of the ones that explain them. So `around(_:in:)` is always handed the
/// active source buffer, never `cachedFilteredEntries`.
///
/// This mirrors the VS Code analyzer's `getLineDetail`, which slices the
/// service's whole `lineBuffer` rather than the queried rows.
/// Deliberately not Equatable: that would require `LogEntry` to be, and nothing
/// here needs value equality — the view keys off the expanded entry's id.
struct LogEntryContext: Sendable {
    /// Entries immediately before the focused one, oldest first.
    let before: [LogEntry]
    /// Entries immediately after the focused one, oldest first.
    let after: [LogEntry]

    static let empty = LogEntryContext(before: [], after: [])

    var isEmpty: Bool {
        before.isEmpty && after.isEmpty
    }

    /// Default number of entries shown on each side, matching the VS Code
    /// analyzer's `contextBefore` / `contextAfter`.
    static let defaultRadius = 5

    /// Slices up to `radius` entries either side of the entry with `id`.
    ///
    /// Returns `.empty` when the id is not in `entries` — which happens
    /// legitimately: the buffer is capped, so an entry the user expanded can be
    /// trimmed away underneath them, and a source switch replaces the buffer
    /// entirely. A linear scan is fine here because this only runs for a single
    /// expanded row, never per visible row.
    static func around(_ id: UUID, in entries: [LogEntry], radius: Int = defaultRadius) -> LogEntryContext {
        guard radius > 0, let index = entries.firstIndex(where: { $0.id == id }) else { return .empty }
        let lowerBound = entries.index(index, offsetBy: -radius, limitedBy: entries.startIndex) ?? entries.startIndex
        let upperBound = entries.index(index, offsetBy: radius + 1, limitedBy: entries.endIndex) ?? entries.endIndex
        return LogEntryContext(
            before: Array(entries[lowerBound ..< index]),
            after: Array(entries[entries.index(after: index) ..< upperBound])
        )
    }
}
