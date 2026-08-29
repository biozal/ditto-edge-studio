import Foundation

/// One index suggestion from an `ADVISE` run (SDK 5.1). All three fields are
/// required — a partial suggestion is noise the UI can't act on
/// (parity with the VS Code extension's `parseSuggestion`).
struct QueryIndexSuggestion: Equatable {
    let collection: String
    let reason: String
    /// Full `CREATE INDEX …` statement, executed verbatim after user confirmation.
    let statement: String
}

/// Result of an `ADVISE <SELECT …>` execution. `suggestedIndexes` may be empty
/// when there's nothing to advise on; `outcome` then carries the why
/// (e.g. "no keys to advise on").
struct QueryAdvice: Equatable {
    let statement: String
    let outcome: String?
    let suggestions: [QueryIndexSuggestion]
}

/// Extracts the query advice from an ADVISE result set, or nil when no row
/// carries an advice object (non-ADVISE queries; forward-incompatible rows).
///
/// Forward-compatible by design (parity with the extension's `advise.ts`):
/// emitters may add fields or split advice across several rows, so we scan every
/// row, merge, and drop suggestions missing the fields the UI needs.
enum QueryAdviceExtractor {
    /// Rows are per-document JSON strings (Swift's `jsonResults` shape).
    static func extract(from jsonRows: [String]) -> QueryAdvice? {
        var statement: String?
        var outcome: String?
        var suggestions: [QueryIndexSuggestion] = []
        var found = false

        for json in jsonRows {
            guard let data = json.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let advice = row["advice"] as? [String: Any] else { continue }
            found = true
            if let s = advice["statement"] as? String, statement == nil {
                statement = s
            }
            if let o = advice["outcome"] as? String, outcome == nil {
                outcome = o
            }
            if let rawSuggestions = advice["suggestedIndexes"] as? [[String: Any]] {
                for raw in rawSuggestions {
                    if let parsed = parseSuggestion(raw) {
                        suggestions.append(parsed)
                    }
                }
            }
        }

        guard found else { return nil }
        return QueryAdvice(statement: statement ?? "", outcome: outcome, suggestions: suggestions)
    }

    static func parseSuggestion(_ raw: [String: Any]) -> QueryIndexSuggestion? {
        guard let collection = raw["collection"] as? String,
              let statement = raw["statement"] as? String, !statement.isEmpty else { return nil }
        return QueryIndexSuggestion(
            collection: collection,
            reason: raw["reason"] as? String ?? "",
            statement: statement
        )
    }
}

enum DqlStatements {
    /// True when the statement starts with ADVISE (case-insensitive).
    /// `EXPLAIN ADVISE …` is not valid syntax (extension: EXPLAIN is skipped for ADVISE).
    /// SELECT detection is intentionally NOT duplicated here — use
    /// `QueryService.isSelectStatement(_:)`, the single source of truth.
    static func isAdviseStatement(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        let needle = "ADVISE"
        guard upper.hasPrefix(needle) else { return false }
        let afterIndex = upper.index(upper.startIndex, offsetBy: needle.count)
        if afterIndex == upper.endIndex {
            return true
        }
        let next = upper[afterIndex]
        return next.isWhitespace || next.isNewline
    }
}
