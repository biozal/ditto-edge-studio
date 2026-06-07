import Foundation

/// Dictionary → `QueryProfile` parser for the `~request_profile`
/// envelope Ditto emits when a DQL statement is prefixed with the
/// `PROFILE` keyword.
///
/// Operates on the same `[String: Any]` shape that `QueryService`
/// already gets back from `ditto.store.execute(...)` items (via
/// `compactMapValues { $0 }`), so the call site stays cheap — no
/// secondary serialise/deserialise pass.
///
/// Designed to be forgiving:
///   - Returns `nil` if the input dictionary doesn't look like a
///     profile envelope (no `~request_profile` key, missing required
///     fields). Caller treats nil as "PROFILE didn't fire" rather
///     than throwing.
///   - Unknown operator attributes survive: anything in a `plan`
///     node that isn't `#operator` / `#stats` / `children` is
///     captured into `attributes` as a string-rendered pair, so the
///     card view can display it without the parser needing to know
///     the full operator catalogue.
enum QueryProfileParser {
    /// Profile envelope key Ditto emits as the trailing item.
    static let envelopeKey = "~request_profile"

    /// Attempts to interpret a single result-item dictionary as a
    /// profile envelope. Returns the parsed profile or nil if the
    /// item isn't a profile (e.g. a normal user document) or is
    /// missing required fields.
    static func parseItem(_ item: [String: Any]) -> QueryProfile? {
        // The envelope can be either:
        //   { "~request_profile": { … } }   ← typical
        // or the bare profile dict if the SDK already unwrapped it.
        let envelope: [String: Any]
        if let nested = item[envelopeKey] as? [String: Any] {
            envelope = nested
        } else if item["_id"] != nil, item["plan"] != nil {
            // Bare profile (defensive — covers SDK changes that
            // strip the outer ~request_profile wrapper).
            envelope = item
        } else {
            return nil
        }

        guard
            let id = envelope["_id"] as? String,
            let planDict = envelope["plan"] as? [String: Any],
            let plan = parseOperator(planDict) else
        {
            return nil
        }

        let times = parseTimes(envelope["times"] as? [String: Any])

        return QueryProfile(
            id: id,
            appId: stringValue(envelope["app_id"]) ?? "",
            featureFlags: stringValue(envelope["featureFlags"]) ?? "",
            queryType: stringValue(envelope["queryType"]) ?? "",
            requestType: stringValue(envelope["requestType"]) ?? "",
            resultCount: intValue(envelope["resultCount"]) ?? 0,
            state: stringValue(envelope["state"]) ?? "",
            text: stringValue(envelope["text"]) ?? "",
            times: times,
            plan: plan,
            capturedAt: Date.now
        )
    }

    // MARK: - Operator tree

    /// Parses a single plan-tree node. Recurses into `children`.
    ///
    /// Returns `nil` only if the node is missing the `#operator`
    /// key — that's the one truly required field for a node to be
    /// meaningful. Everything else (stats, children, attributes)
    /// is optional.
    private static func parseOperator(_ dict: [String: Any]) -> QueryProfileOperator? {
        guard let name = dict["#operator"] as? String else {
            return nil
        }

        let stats = parseStats(dict["#stats"] as? [String: Any])

        let children: [QueryProfileOperator] = {
            guard let raw = dict["children"] as? [[String: Any]] else { return [] }
            return raw.compactMap { parseOperator($0) }
        }()

        // Preserve attribute insertion order. Dictionaries are
        // unordered in Swift, so iterate by sorted key for
        // determinism — same node will render the same way every
        // time, which matters for snapshot tests and reduces
        // visual jitter when the same query is re-profiled.
        var attributes: [(key: String, value: String)] = []
        let reservedKeys: Set = ["#operator", "#stats", "children"]
        for key in dict.keys.sorted() where !reservedKeys.contains(key) {
            guard let raw = dict[key] else { continue }
            attributes.append((key: key, value: renderAttribute(raw)))
        }

        return QueryProfileOperator(
            id: UUID(),
            name: name,
            stats: stats,
            children: children,
            attributes: attributes
        )
    }

    /// Renders an arbitrary attribute value as a display string.
    /// Strings pass through unchanged; primitives use `String(describing:)`;
    /// nested objects re-encode as compact JSON so the value survives
    /// without expanding into the layout unpredictably.
    private static func renderAttribute(_ raw: Any) -> String {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        if let b = raw as? Bool { return b ? "true" : "false" }
        // Try compact JSON for objects/arrays so they're still readable
        // when the card view shows them on a single line.
        if let data = try? JSONSerialization.data(
            withJSONObject: raw,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return String(describing: raw)
    }

    // MARK: - Stats and times

    private static func parseStats(_ dict: [String: Any]?) -> QueryProfileStats? {
        guard let dict else { return nil }
        let phaseTimes = dict["phaseTimes"] as? [String: Any]
        return QueryProfileStats(
            documentsIn: intValue(dict["documentsIn"]),
            documentsOut: intValue(dict["documentsOut"]),
            execNs: int64Value(phaseTimes?["exec"]),
            recvNs: int64Value(phaseTimes?["recv"]),
            sendNs: int64Value(phaseTimes?["send"])
        )
    }

    /// Parses the top-level `times` object. Missing fields default to
    /// zero so the formatter still renders something sensible — a
    /// missing parse time as `0 ns` is more useful than crashing the
    /// whole profile view.
    private static func parseTimes(_ dict: [String: Any]?) -> QueryProfileTimes {
        guard let dict else {
            return QueryProfileTimes(elapsedNs: 0, parseNs: 0, planNs: 0, startISO: "")
        }
        return QueryProfileTimes(
            elapsedNs: int64Value(dict["elapsed"]) ?? 0,
            parseNs: int64Value(dict["parse"]) ?? 0,
            planNs: int64Value(dict["plan"]) ?? 0,
            startISO: stringValue(dict["start"]) ?? ""
        )
    }

    // MARK: - Value coercion helpers

    /// Accepts both `String` and `NSString` (and `NSNumber` via
    /// `stringValue` for IDs that may come back numeric). Returns
    /// nil for anything else.
    private static func stringValue(_ raw: Any?) -> String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let i = raw as? Int { return i }
        if let s = raw as? String, let i = Int(s) { return i }
        return nil
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let n = raw as? NSNumber { return n.int64Value }
        if let i = raw as? Int64 { return i }
        if let i = raw as? Int { return Int64(i) }
        if let s = raw as? String, let i = Int64(s) { return i }
        return nil
    }
}
