import SwiftUI

// MARK: - Profile Syntax Palette

/// Colors for the Profile viewer, matched to the VS Code extension's profile page
/// (`~/Desktop/profile-ui.png` reference): yellow-olive keywords, light-blue string
/// literals, and solid stat chips (blue `in`, green `out`, red `exec`, dark `send`;
/// `recv` is plain text there, not a chip).
///
/// Syntax colors adapt for light mode (the yellow/blue dark-mode values are
/// unreadable on Papyrus White); chip fills are fixed — white text on a saturated
/// fill reads correctly in both modes.
enum ProfileSyntaxColors {
    /// DQL keywords / JSON keys — yellow-olive.
    static let keyword = adaptive(
        light: Color(red: 0.478, green: 0.478, blue: 0.071), // #7A7A12
        dark: Color(red: 0.847, green: 0.863, blue: 0.416) // #D8DC6A
    )
    /// String literals / JSON string values — light blue.
    static let string = adaptive(
        light: Color(red: 0.043, green: 0.361, blue: 0.678), // #0B5CAD
        dark: Color(red: 0.620, green: 0.796, blue: 1.0) // #9ECBFF
    )

    /// Solid chip fills (white text in both modes).
    static let chipIn = Color(red: 0.145, green: 0.388, blue: 0.922) // #2563EB
    static let chipOut = Color(red: 0.180, green: 0.490, blue: 0.196) // #2E7D32
    static let chipExec = Color(red: 0.776, green: 0.157, blue: 0.157) // #C62828
    static let chipSend = Color(red: 0.259, green: 0.259, blue: 0.259) // #424242

    private static func adaptive(light: Color, dark: Color) -> Color {
        #if os(macOS)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
        #else
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }
}

// MARK: - DQL Highlighting

/// Produces a syntax-highlighted `AttributedString` for a DQL statement.
///
/// Hand-rolled rather than HighlightSwift for three reasons: the Profile header is a
/// read-only `Text` (needs `textSelection`, which `CodeText` doesn't support), the
/// palette must match the VS Code profile page exactly, and the same two-file approach
/// ports 1:1 to the Android `AnnotatedString` highlighter.
enum DQLSyntaxHighlighter {
    private static let keywords: Set = [
        "select", "from", "where", "insert", "update", "delete", "evict", "into",
        "set", "documents", "values", "and", "or", "not", "null", "true", "false",
        "limit", "offset", "order", "by", "asc", "desc", "group", "having", "join",
        "left", "inner", "outer", "on", "as", "distinct", "like", "in", "is",
        "between", "exists", "case", "when", "then", "else", "end", "profile",
        "explain", "alter", "system", "show", "create", "index", "drop", "with",
        "union", "all", "reset"
    ]

    static func highlight(_ text: String) -> AttributedString {
        var result = AttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "'" {
                // String literal — '' is the DQL escape for a quote inside one.
                var end = text.index(after: index)
                while end < text.endIndex {
                    if text[end] == "'" {
                        let next = text.index(after: end)
                        if next < text.endIndex && text[next] == "'" {
                            end = text.index(after: next)
                        } else {
                            end = next
                            break
                        }
                    } else {
                        end = text.index(after: end)
                    }
                }
                var piece = AttributedString(String(text[index ..< end]))
                piece.foregroundColor = ProfileSyntaxColors.string
                result.append(piece)
                index = end
            } else if char.isLetter || char == "_" {
                var end = index
                while end < text.endIndex,
                      text[end].isLetter || text[end].isNumber || text[end] == "_"
                {
                    end = text.index(after: end)
                }
                let word = String(text[index ..< end])
                var piece = AttributedString(word)
                if keywords.contains(word.lowercased()) {
                    piece.foregroundColor = ProfileSyntaxColors.keyword
                }
                result.append(piece)
                index = end
            } else {
                result.append(AttributedString(String(char)))
                index = text.index(after: index)
            }
        }
        return result
    }
}

// MARK: - JSON Highlighting

/// Highlights a JSON document (the `descriptor`-style attribute values in a plan):
/// keys in the keyword color, string values in the string color, everything else
/// default. Input is expected to be valid, pretty-printed JSON; anything unexpected
/// is emitted uncolored rather than dropping characters.
enum JSONSyntaxHighlighter {
    static func highlight(_ text: String) -> AttributedString {
        var result = AttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                // JSON escapes use backslash, not quote doubling.
                var end = text.index(after: index)
                while end < text.endIndex {
                    if text[end] == "\\", text.index(after: end) < text.endIndex {
                        end = text.index(end, offsetBy: 2)
                    } else if text[end] == "\"" {
                        end = text.index(after: end)
                        break
                    } else {
                        end = text.index(after: end)
                    }
                }
                let raw = String(text[index ..< end])
                // A string is a key when the next non-whitespace character is ':'.
                var lookahead = end
                while lookahead < text.endIndex && text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                let isKey = lookahead < text.endIndex && text[lookahead] == ":"
                var piece = AttributedString(raw)
                piece.foregroundColor = isKey ? ProfileSyntaxColors.keyword : ProfileSyntaxColors.string
                result.append(piece)
                index = end
            } else {
                result.append(AttributedString(String(char)))
                index = text.index(after: index)
            }
        }
        return result
    }
}
