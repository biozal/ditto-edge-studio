import Foundation
import SwiftUI
import Testing

@testable import Ditto_Edge_Studio

// MARK: - ProfileSyntaxHighlighter Tests
//
// The Profile viewer's query header and JSON attribute blocks depend on these
// highlighters to match the VS Code profile page's palette. SwiftUI `Color` is
// not `Equatable`, so tests compare `String(describing:)` of the run attribute —
// sufficient to assert "keyword color, not string color, not none". Runs are read
// from the `AttributedString` directly: the NSAttributedString bridge does not
// carry SwiftUI-scope attributes.

/// The foreground color of the run covering `substring`'s first occurrence.
private func runColor(
    of substring: String,
    in text: String,
    highlighted: AttributedString
) -> Color? {
    guard let range = text.range(of: substring),
          let lower = AttributedString.Index(range.lowerBound, within: highlighted)
    else { return nil }
    for run in highlighted.runs where run.range.contains(lower) {
        return run.foregroundColor
    }
    return nil
}

private func description(of color: Color?) -> String? {
    color.map { String(describing: $0) }
}

@Suite("DQLSyntaxHighlighter Tests")
struct DQLSyntaxHighlighterTests {
    @Test("Keywords are colored, case-insensitively")
    func keywordsColored() {
        let text = "select * FROM movies"
        let highlighted = DQLSyntaxHighlighter.highlight(text)
        let keyword = String(describing: ProfileSyntaxColors.keyword)

        #expect(description(of: runColor(of: "select", in: text, highlighted: highlighted)) == keyword)
        #expect(description(of: runColor(of: "FROM", in: text, highlighted: highlighted)) == keyword)
    }

    @Test("Non-keyword identifiers are not colored")
    func identifiersUncolored() {
        let text = "SELECT * FROM movies"
        let highlighted = DQLSyntaxHighlighter.highlight(text)

        #expect(runColor(of: "movies", in: text, highlighted: highlighted) == nil)
    }

    @Test("String literals get the string color")
    func stringsColored() {
        let text = "DELETE FROM movies WHERE plot = 'delete-stmt-test-benchmark-uuid'"
        let highlighted = DQLSyntaxHighlighter.highlight(text)

        #expect(
            description(of: runColor(of: "'delete-stmt-test-benchmark-uuid'", in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.string)
        )
    }

    @Test("Doubled-quote escape stays inside the string token")
    func escapedQuote() {
        let text = "WHERE name = 'it''s' AND x = 1"
        let highlighted = DQLSyntaxHighlighter.highlight(text)

        // The whole 'it''s' is one string token; AND is a keyword AFTER it.
        #expect(
            description(of: runColor(of: "'it''s'", in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.string)
        )
        #expect(
            description(of: runColor(of: "AND", in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.keyword)
        )
    }

    @Test("Round trip preserves the source text exactly")
    func roundTrip() {
        let text = "PROFILE SELECT * FROM t WHERE a = 'x' LIMIT 10"
        #expect(String(DQLSyntaxHighlighter.highlight(text).characters) == text)
    }
}

@Suite("JSONSyntaxHighlighter Tests")
struct JSONSyntaxHighlighterTests {
    @Test("Keys use the keyword color, string values the string color")
    func keysAndValues() {
        let text = """
        {
          "diff_scan_condition": "never"
        }
        """
        let highlighted = JSONSyntaxHighlighter.highlight(text)

        #expect(
            description(of: runColor(of: "\"diff_scan_condition\"", in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.keyword)
        )
        #expect(
            description(of: runColor(of: "\"never\"", in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.string)
        )
    }

    @Test("Escaped quotes inside strings do not end the token")
    func escapedQuote() {
        let text = #"{"a": "b\"c"}"#
        let highlighted = JSONSyntaxHighlighter.highlight(text)

        #expect(
            description(of: runColor(of: #""b\"c""#, in: text, highlighted: highlighted))
                == String(describing: ProfileSyntaxColors.string)
        )
    }

    @Test("Round trip preserves the source text exactly")
    func roundTrip() {
        let text = "{\n  \"a\": [1, true, null]\n}"
        #expect(String(JSONSyntaxHighlighter.highlight(text).characters) == text)
    }
}

@Suite("ProfileOperatorCard JSON detection Tests")
struct ProfileOperatorCardJSONTests {
    @Test("JSON objects pretty-print")
    func objectPrettyPrints() throws {
        let pretty = ProfileOperatorCard.prettyPrintedJSON(#"{"b":1,"a":"x"}"#)
        let prettyText = try #require(pretty)
        #expect(prettyText.contains("\n"))
        // Sorted keys: "a" before "b".
        let aRange = try #require(prettyText.range(of: "\"a\""))
        let bRange = try #require(prettyText.range(of: "\"b\""))
        #expect(aRange.lowerBound < bRange.lowerBound)
    }

    @Test("Non-JSON values return nil")
    func nonJSON() {
        #expect(ProfileOperatorCard.prettyPrintedJSON("movies") == nil)
        #expect(ProfileOperatorCard.prettyPrintedJSON("{not json") == nil)
        #expect(ProfileOperatorCard.prettyPrintedJSON("") == nil)
    }
}
