import DittoSwift
import Foundation

/// A physical connection between this peer and a remote peer, reconstructed
/// from the SDK's `physical connection started` / `physical connection ended`
/// log lines.
struct ConnectionSession: Sendable, Equatable {
    let start: Date
    var end: Date?
    let remotePeer: String
    let transport: String
    let role: String
    let connectionId: String?

    /// Seconds the connection was open, or nil while it is still open.
    var duration: TimeInterval? {
        guard let end else { return nil }
        return end.timeIntervalSince(start)
    }
}

/// One parsed connection lifecycle event.
///
/// ## Why this is not a single regex
///
/// The SDK emits the *same* logical event in two different encodings, and the
/// SwiftUI app consumes both:
///
/// - **Live capture** (`DittoLogger.setCustomLogCallback`) delivers a flattened
///   text line whose body carries `key=value` pairs:
///   `physical connection started remote=pkAoc… role=Client transport_type=Awdl connection_id=9`
/// - **Historical capture** (`LogFileParser.parseDirectory`) reads the SDK's
///   rotating `ditto_logs/*.log` files, which are **JSON Lines**. There the
///   message is just `"physical connection started"` and the fields are
///   siblings of it in the JSON object:
///   `{"message":"physical connection started","remote":"pkAoc…","role":"Client","transport_type":"Awdl","connection_id":"9"}`
///
/// A `remote=([^\s]+)` regex — the shape the VS Code extension uses, where only
/// the flattened encoding exists — matches **nothing** in the file encoding.
/// Verified against a real capture: `grep -c 'transport_type=' ditto-logs-*.log`
/// returns 0 while the same file holds 4 `physical connection started` records.
/// So `extract` tries the structured form first (the JSON is already retained
/// verbatim on `LogEntry.rawLine`) and falls back to the flattened form.
struct LogConnectionEvent: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case started
        case ended
        /// Ditto re-initialised; every open connection is implicitly torn down.
        case reinit
    }

    let kind: Kind
    let timestamp: Date
    let remotePeer: String
    let transport: String
    let role: String
    let connectionId: String?

    // MARK: - Extraction

    fileprivate static let unknown = "unknown"

    /// Compiled once — `NSRegularExpression` compilation is expensive and these
    /// run against every log entry whose message survives the cheap prefilter.
    private enum RE {
        // swiftlint:disable force_try
        static let remote = try! NSRegularExpression(pattern: #"remote=([^\s]+)"#, options: .caseInsensitive)
        static let transport = try! NSRegularExpression(pattern: #"transport_type=([^\s]+)"#, options: .caseInsensitive)
        static let role = try! NSRegularExpression(pattern: #"role=([^\s]+)"#, options: .caseInsensitive)
        static let connectionId = try! NSRegularExpression(pattern: #"connection_id=([^\s]+)"#, options: .caseInsensitive)
        // swiftlint:enable force_try
    }

    /// Parses a connection lifecycle event out of `entry`, or returns nil when
    /// the entry is not one. Cheap for the overwhelming majority of lines: a
    /// substring prefilter runs before any regex or JSON work.
    static func extract(from entry: LogEntry) -> LogConnectionEvent? {
        let message = entry.message

        // Prefilter. Every branch below needs one of these substrings, and
        // ~99.9% of log lines contain neither, so this is the only work most
        // lines pay for.
        let isConnectionLine = message.range(of: "physical connection", options: .caseInsensitive) != nil
        let isReinitLine = !isConnectionLine && message.contains("ditto_init")
        guard isConnectionLine || isReinitLine else { return nil }

        if isReinitLine {
            // Deliberately scoped to the *message* rather than the whole raw
            // line. In the JSON encoding `ditto_init` shows up inside `path`
            // values of unrelated records (19 such lines in one 3.5k-line
            // capture, none of them an actual re-init), and a whole-line match
            // would close every open session on each of them.
            return LogConnectionEvent(
                kind: .reinit, timestamp: entry.timestamp,
                remotePeer: unknown, transport: unknown, role: unknown, connectionId: nil
            )
        }

        // "physical connection ended (extended info)" is a separate DEBUG record
        // that duplicates the INFO one; counting both would double every close.
        let lower = message.lowercased()
        guard !lower.contains("(extended info)") else { return nil }

        let kind: Kind
        if lower.contains("started") {
            kind = .started
        } else if lower.contains("ended") {
            kind = .ended
        } else {
            // e.g. "Physical connection shutting down" — not a lifecycle edge we
            // pair on; the matching "ended" record carries the fields we need.
            return nil
        }

        if let fields = StructuredFields(rawLine: entry.rawLine) {
            return LogConnectionEvent(
                kind: kind, timestamp: entry.timestamp,
                remotePeer: fields.remote, transport: fields.transport,
                role: fields.role, connectionId: fields.connectionId
            )
        }

        return LogConnectionEvent(
            kind: kind, timestamp: entry.timestamp,
            remotePeer: capture(RE.remote, in: message) ?? unknown,
            transport: capture(RE.transport, in: message) ?? unknown,
            role: capture(RE.role, in: message) ?? unknown,
            connectionId: capture(RE.connectionId, in: message)
        )
    }

    /// Connection fields as carried by the JSON Lines encoding.
    private struct StructuredFields {
        let remote: String
        let transport: String
        let role: String
        let connectionId: String?

        /// Fails for the flattened text encoding, so the caller falls back to
        /// regex over the message body.
        init?(rawLine: String) {
            guard rawLine.hasPrefix("{"),
                  let data = rawLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            remote = json["remote"] as? String ?? LogConnectionEvent.unknown
            transport = json["transport_type"] as? String ?? LogConnectionEvent.unknown
            role = json["role"] as? String ?? LogConnectionEvent.unknown
            // `connection_id` is a string in every capture inspected, but read
            // it permissively — a numeric encoding would otherwise silently
            // drop the best available match key.
            connectionId = (json["connection_id"] as? String)
                ?? (json["connection_id"] as? NSNumber).map(\.stringValue)
        }
    }

    private static func capture(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}

/// Pairs `physical connection started` / `ended` events into
/// `ConnectionSession`s, which feed the Connection Durations histogram.
///
/// Port of the VS Code extension's `ConnectionTracker`, including the bounds
/// that file records as having been bugs — every history array is capped, the
/// open-session array included (a `started` whose `ended` never arrives, from a
/// killed process or a truncated log, would otherwise leak for the life of the
/// view).
struct LogConnectionTracker {
    /// Upper bound on retained sessions per bucket. Trimmed in chunks so the
    /// per-event cost stays amortized O(1).
    static let sessionHistoryCap = 1000

    private var open: [ConnectionSession] = []
    private var closed: [ConnectionSession] = []
    private(set) var reinits: [Date] = []
    /// `ended` events with no matching open session — a truncated log tail, or
    /// a connection opened before capture started. Surfaced for diagnostics
    /// rather than silently dropped.
    private(set) var unmatchedEnds = 0

    init() {}

    /// All sessions seen, closed ones first. Open sessions have `end == nil`.
    var sessions: [ConnectionSession] {
        closed + open
    }

    /// Sessions that actually closed — the only ones with a duration, and so
    /// the only ones the durations histogram can bin.
    var closedSessions: [ConnectionSession] {
        closed
    }

    mutating func consume(_ entry: LogEntry) {
        guard let event = LogConnectionEvent.extract(from: entry) else { return }
        consume(event)
    }

    mutating func consume(_ event: LogConnectionEvent) {
        switch event.kind {
        case .reinit:
            // Ditto restarted: everything still open ended at this instant.
            for index in open.indices {
                open[index].end = event.timestamp
            }
            closed.append(contentsOf: open)
            open.removeAll()
            reinits.append(event.timestamp)
            reinits = Self.trimmed(reinits)
            closed = Self.trimmed(closed)

        case .started:
            open.append(ConnectionSession(
                start: event.timestamp, end: nil,
                remotePeer: event.remotePeer, transport: event.transport,
                role: event.role, connectionId: event.connectionId
            ))
            open = Self.trimmed(open)

        case .ended:
            // Match the most recently opened session with this key, not the
            // oldest: the SDK reuses `connection_id` values, so last-in-first-out
            // pairs a close with the connection it actually belongs to.
            guard let index = open.lastIndex(where: { matches($0, event) }) else {
                unmatchedEnds += 1
                return
            }
            var session = open.remove(at: index)
            session.end = event.timestamp
            closed.append(session)
            closed = Self.trimmed(closed)
        }
    }

    /// Prefer `connection_id` — it identifies one physical connection exactly.
    /// Fall back to `remote::role` (what the VS Code tracker keys on) when the
    /// id is absent, which happens for log lines that predate it.
    private func matches(_ session: ConnectionSession, _ event: LogConnectionEvent) -> Bool {
        if let sessionId = session.connectionId, let eventId = event.connectionId {
            return sessionId == eventId
        }
        return session.remotePeer == event.remotePeer && session.role == event.role
    }

    /// Static and by-value: an `inout` helper taking a stored property while
    /// `self` is already exclusively accessed is an exclusivity violation.
    private static func trimmed<T>(_ array: [T]) -> [T] {
        array.count > sessionHistoryCap * 2 ? Array(array.suffix(sessionHistoryCap)) : array
    }

    /// Drops all history. Without clearing every array, "Clear" appears to work
    /// and the next connection event resurrects the pre-Clear sessions, because
    /// `sessions` is rebuilt from these arrays rather than from what the view
    /// last displayed.
    mutating func reset() {
        open.removeAll()
        closed.removeAll()
        reinits.removeAll()
        unmatchedEnds = 0
    }

    /// Builds a tracker from a whole buffer in one pass.
    static func track(_ entries: [LogEntry]) -> LogConnectionTracker {
        var tracker = LogConnectionTracker()
        for entry in entries {
            tracker.consume(entry)
        }
        return tracker
    }
}
