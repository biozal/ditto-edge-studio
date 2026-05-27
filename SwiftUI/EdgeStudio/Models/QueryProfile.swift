import Foundation

/// Captured execution profile for a single DQL `SELECT` statement.
///
/// Ditto emits this as an extra item with key `~request_profile`
/// appended to the result set when the statement is prefixed with the
/// `PROFILE` keyword. See `QueryProfileParser` for the dictionary →
/// struct mapping, and `Data/QueryService.swift` for the
/// PROFILE-injection logic.
///
/// All timing values are nanoseconds at source (verified in
/// `ditto-v5/crates/ditto-dql/src/engine/caches/request.rs` —
/// `set_parse_time(ns)`, `set_plan_time(ns)`, `elapsed()` all use
/// `as_nanos() as u64`; per-operator phase times use the same).
/// Use `ProfileTimeFormatter` (introduced with the Profile viewer
/// UI) to render them as ms / µs / ns for display.
struct QueryProfile: Identifiable {
    /// Profile request identifier from Ditto (`~request_profile._id`).
    let id: String
    let appId: String
    let featureFlags: String
    let queryType: String
    let requestType: String
    let resultCount: Int
    let state: String
    /// The statement as Ditto saw it — includes the leading `PROFILE`
    /// keyword we prepended. Display strips the prefix when showing
    /// the user's original query in the header card.
    let text: String
    let times: QueryProfileTimes
    let plan: QueryProfileOperator
    /// Wall-clock instant we parsed the profile on the client. Used
    /// for the "captured at" timestamp in the header — `times.startISO`
    /// is the server-side instant which can differ from the local one.
    let capturedAt: Date
}

/// Top-level timings from `~request_profile.times` (all nanoseconds).
struct QueryProfileTimes {
    /// Total elapsed wall-clock time the request took, end to end.
    let elapsedNs: Int64
    /// Time spent parsing the statement text into an AST.
    let parseNs: Int64
    /// Time spent planning (operator selection, optimisation).
    let planNs: Int64
    /// Server-side ISO timestamp of when the request started.
    /// Preserved as the raw string for round-trip fidelity; the UI
    /// renders it via `ISO8601DateFormatter` when displayed.
    let startISO: String
}

/// One node in the execution-plan tree.
///
/// Profile JSON uses `#operator` for the type name, `#stats` for
/// timing/throughput, an optional `children` array, and zero or more
/// operator-specific attribute keys (`collection`, `alias`,
/// `datasource`, `limit`, `descriptor`, …). The attribute set varies
/// per operator type — we store them as `(key, value)` pairs in
/// insertion order so the card view renders them in the order Ditto
/// returned them.
struct QueryProfileOperator: Identifiable {
    /// Synthesised per-node identifier, stable for the lifetime of
    /// the parsed `QueryProfile`. Drives SwiftUI `ForEach` identity.
    let id: UUID
    /// Operator type name from `#operator` (e.g. `"scan"`, `"sequence"`,
    /// `"limit"`, `"finalProjection"`).
    let name: String
    let stats: QueryProfileStats?
    let children: [QueryProfileOperator]
    /// Operator-specific keys preserved in insertion order. Stored
    /// as `String` so unknown attribute types still render —
    /// `String(describing:)` produces a stable representation for any
    /// `[String: Any]` value the parser encounters.
    let attributes: [(key: String, value: String)]
}

/// Per-operator throughput and timing from `#stats` (nanoseconds).
///
/// Every field is optional because Ditto omits keys that don't apply
/// to a given operator (e.g. a `scan` has no `documentsIn`; a `limit`
/// may have no `recv` phase time).
struct QueryProfileStats {
    let documentsIn: Int?
    let documentsOut: Int?
    /// CPU time inside the operator.
    let execNs: Int64?
    /// Time waiting on upstream operators to feed input.
    let recvNs: Int64?
    /// Time pushing output to downstream operators.
    let sendNs: Int64?
}

// MARK: - Convenience

extension QueryProfile {
    /// The user-facing query text with the leading `PROFILE ` prefix
    /// stripped. Used by the header card so the user sees what they
    /// typed, not what Ditto saw.
    var displayQueryText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("PROFILE ") {
            return String(trimmed.dropFirst("PROFILE ".count))
        }
        return text
    }
}
