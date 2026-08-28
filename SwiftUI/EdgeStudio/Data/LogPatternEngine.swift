import DittoSwift
import Foundation

/// Compiles and scans `LogPattern`s against log entries (parity port of the VS
/// Code extension's `PatternEngine`).
///
/// Scan semantics (mirrors the extension exactly):
/// - The pattern regex matches the entry **message body only**, case-insensitive.
/// - `level_filter` is an **exact** equality, not "at least", so tiered patterns
///   (e.g. deadlock at error vs warning) stay mutually exclusive.
/// - `tag_filter` is a case-sensitive regex against the line's tag — here the
///   entry's component display name (e.g. "Sync").
/// - Matching patterns contribute their `user_tag` labels to the entry.
struct LogPatternEngine: Sendable {
    struct CompiledPattern {
        let key: String
        let severity: Int
        let recommendation: String
        let levelFilter: DittoLogLevel?
        let tagFilter: NSRegularExpression?
        let userTag: String?
        let source: PatternSource
        /// NSRegularExpression is thread-safe for matching; Sendable conformance
        /// is provided via the @unchecked extension below.
        let regex: NSRegularExpression

        func matches(message: String) -> Bool {
            regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) != nil
        }

        func matchesTag(_ tag: String) -> Bool {
            guard let tagFilter else { return true }
            return tagFilter.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil
        }
    }

    struct Match {
        let pattern: CompiledPattern
        let entry: LogEntry
    }

    let compiled: [CompiledPattern]

    init(patterns: [String: LogPattern]) {
        compiled = patterns.values.compactMap { Self.compile($0) }
    }

    /// Returns every pattern matching this entry (usually none).
    func scan(_ entry: LogEntry) -> [CompiledPattern] {
        let tag = entry.component.rawValue
        return compiled.filter { p in
            (p.levelFilter == nil || entry.level == p.levelFilter) &&
                p.matchesTag(tag) &&
                p.matches(message: entry.message)
        }
    }

    /// Scans the newest `maxEntries` of `entries`, returning matches in
    /// chronological order. Run off the main actor; the cap bounds worst-case
    /// cost on chatty logs.
    func scanAll(_ entries: [LogEntry], maxEntries: Int = Self.maxScanEntries) -> [Match] {
        let window = entries.count > maxEntries ? Array(entries.suffix(maxEntries)) : entries
        var out: [Match] = []
        for entry in window {
            for p in scan(entry) {
                out.append(Match(pattern: p, entry: entry))
            }
        }
        return out
    }

    /// True if this pattern body (as-yet unsaved) would match the given line —
    /// used by the pattern editor's live "test line" preview.
    static func testMatch(
        body: LogPatternBody,
        level: DittoLogLevel,
        tag: String,
        message: String
    ) -> Bool {
        let pattern = LogPattern(
            key: "",
            body: body,
            levelFilter: parseLogLevelFilter(body.levelFilter),
            source: .user
        )
        guard let compiled = compile(pattern) else { return false }
        return (compiled.levelFilter == nil || level == compiled.levelFilter) &&
            compiled.matchesTag(tag) &&
            compiled.matches(message: message)
    }

    // MARK: - Validation

    /// Upper bound on entries scanned per pass. The capture buffers hold up to
    /// 10k entries; scanning more than this per refresh would drop frames.
    static let maxScanEntries = 5000

    /// Parity with the extension's MAX_USER_PATTERN_LENGTH.
    static let maxUserPatternLength = 512

    /// Nested-quantifier shapes — `(a+)+`, `(\w+\s*)+`, `(a*){2,}` — whose
    /// backtracking cost is exponential in the input length (NSRegularExpression
    /// has no timeout). Parity with the extension's ReDoS guard.
    // Constant pattern validated by LogPatternEngineTests.
    // swiftlint:disable:next force_try
    private static let nestedQuantifier = try! NSRegularExpression(
        pattern: #"\([^)]*[+*][^)]*\)\s*[+*{]"#
    )

    /// Human-readable rejection reason, or nil if valid for `source`. Mirrors the
    /// extension: severity must be 1–5 and a recommendation is required; user
    /// patterns get extra safety checks (length, nested quantifiers, compile).
    static func rejectReason(key: String, body: LogPatternBody, source: PatternSource) -> String? {
        if key.trimmingCharacters(in: .whitespaces).isEmpty {
            return "key must not be blank"
        }
        if body.pattern.isEmpty {
            return "pattern must be a non-empty string"
        }
        if !(1 ... 5).contains(body.severity) {
            return "severity must be 1–5"
        }
        if body.recommendation.trimmingCharacters(in: .whitespaces).isEmpty {
            return "recommendation is required"
        }

        // Unknown level_filter tokens are rejected (VS Code parity: an unknown
        // token can never equal a line's level, so the pattern would silently
        // match nothing — surfacing the typo is friendlier).
        if let token = body.levelFilter, !token.trimmingCharacters(in: .whitespaces).isEmpty,
           parseLogLevelFilter(token) == nil
        {
            return "unknown level_filter '\(token)' (expected error|warning|info|debug|verbose)"
        }

        if source == .user {
            if body.pattern.count > maxUserPatternLength {
                return "pattern exceeds \(maxUserPatternLength) characters"
            }
            let range = NSRange(body.pattern.startIndex..., in: body.pattern)
            if nestedQuantifier.firstMatch(in: body.pattern, range: range) != nil {
                return "pattern nests a quantifier inside a quantified group, "
                    + "which can backtrack exponentially"
            }
        }
        do {
            _ = try NSRegularExpression(pattern: body.pattern, options: .caseInsensitive)
        } catch {
            return "pattern is not a valid regex: \(error.localizedDescription)"
        }

        // tag_filter gets the same treatment — an invalid one would otherwise
        // silently match every component (compile() turns it into nil).
        if let tag = body.tagFilter, !tag.trimmingCharacters(in: .whitespaces).isEmpty {
            if source == .user {
                let range = NSRange(tag.startIndex..., in: tag)
                if nestedQuantifier.firstMatch(in: tag, range: range) != nil {
                    return "tag_filter nests a quantifier inside a quantified group, "
                        + "which can backtrack exponentially"
                }
            }
            do {
                _ = try NSRegularExpression(pattern: tag)
            } catch {
                return "tag_filter is not a valid regex: \(error.localizedDescription)"
            }
        }

        return nil
    }

    /// Compiles a validated pattern; returns nil when the regex fails to compile
    /// (callers run `rejectReason` first and treat nil as a rejected entry).
    static func compile(_ pattern: LogPattern) -> CompiledPattern? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern.body.pattern,
            options: .caseInsensitive
        ) else { return nil }
        let trimmedTag = pattern.body.tagFilter?.trimmingCharacters(in: .whitespaces)
        let tagRegex = trimmedTag.flatMap { tag in
            tag.isEmpty ? nil : try? NSRegularExpression(pattern: tag)
        }
        let trimmedUserTag = pattern.body.userTag?.trimmingCharacters(in: .whitespaces)
        return CompiledPattern(
            key: pattern.key,
            severity: pattern.severity,
            recommendation: pattern.body.recommendation,
            levelFilter: pattern.levelFilter,
            tagFilter: tagRegex,
            userTag: trimmedUserTag?.isEmpty == false ? trimmedUserTag : nil,
            source: pattern.source,
            regex: regex
        )
    }
}

extension LogPatternEngine.CompiledPattern: @unchecked Sendable {}

extension LogPatternEngine.Match: @unchecked Sendable {}
