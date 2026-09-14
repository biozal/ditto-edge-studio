import DittoSwift
import Foundation

/// A user- or bundled-defined log-analysis pattern (parity with the VS Code
/// extension's `problem_patterns.json` schema). Patterns scan the message body
/// of each log entry, case-insensitively.
///
/// On-disk JSON is a map of key → body; this struct carries the key alongside.
struct LogPatternBody: Codable, Equatable {
    var pattern: String
    var severity: Int
    var recommendation: String
    var levelFilter: String?
    var tagFilter: String?
    var userTag: String?

    init(
        pattern: String,
        severity: Int,
        recommendation: String,
        levelFilter: String? = nil,
        tagFilter: String? = nil,
        userTag: String? = nil
    ) {
        self.pattern = pattern
        self.severity = severity
        self.recommendation = recommendation
        self.levelFilter = levelFilter
        self.tagFilter = tagFilter
        self.userTag = userTag
    }

    enum CodingKeys: String, CodingKey {
        case pattern, severity, recommendation
        case levelFilter = "level_filter"
        case tagFilter = "tag_filter"
        case userTag = "user_tag"
    }
}

/// Where a pattern came from. Bundled patterns are read-only.
enum PatternSource: Equatable {
    case bundled
    case user
}

/// A validated pattern ready for compilation by `LogPatternEngine`.
struct LogPattern {
    let key: String
    let body: LogPatternBody
    let severity: Int
    /// Exact-match level filter (`nil` = no level scoping).
    let levelFilter: DittoLogLevel?
    let source: PatternSource

    init(key: String, body: LogPatternBody, levelFilter: DittoLogLevel?, source: PatternSource) {
        self.key = key
        self.body = body
        severity = body.severity
        self.levelFilter = levelFilter
        self.source = source
    }
}

/// Maps the VS Code `level_filter` tokens onto `DittoLogLevel`. Accepts both the
/// extension spellings (`warn`, `trace`) and SDK spellings (`warning`, `verbose`).
func parseLogLevelFilter(_ token: String?) -> DittoLogLevel? {
    switch token?.trimmingCharacters(in: .whitespaces).lowercased() {
    case "error": return .error
    case "warn", "warning": return .warning
    case "info": return .info
    case "debug": return .debug
    case "trace", "verbose": return .verbose
    default: return nil
    }
}

/// Severity 5 (critical) down to 1 (info), parity with the VS Code extension.
func severityLabel(_ severity: Int) -> String {
    switch severity {
    case 5: return "CRITICAL"
    case 4: return "HIGH"
    case 3: return "MEDIUM"
    case 2: return "LOW"
    default: return "INFO"
    }
}
