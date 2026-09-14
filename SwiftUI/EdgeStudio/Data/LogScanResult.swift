import Foundation

/// Everything one throttled analyzer pass produces, so the whole computation
/// can happen in a single detached task and cross back to the main actor once.
///
/// Splitting these into separate passes would mean walking the same entry
/// window several times per refresh, and deriving the id sets or user-tag map
/// as computed properties would rebuild them on every SwiftUI body evaluation
/// rather than once per scan.
struct LogScanResult: Sendable {
    let matches: [LogPatternEngine.Match]
    let analytics: LogAnalytics
    /// Entry ids with at least one pattern match — the Problems tab's row set.
    let problemIDs: Set<UUID>
    /// Entry ids matched by a severity-5 pattern — the Critical tab's row set.
    let criticalIDs: Set<UUID>
    /// `user_tag` labels per entry, sorted and deduped, for the row chips.
    let userTags: [UUID: [String]]
}
