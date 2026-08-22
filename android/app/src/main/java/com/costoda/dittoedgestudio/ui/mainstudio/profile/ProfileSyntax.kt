package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle

/**
 * Colors for the Profile viewer, matched to the VS Code extension's profile page:
 * yellow-olive keywords, light-blue string literals, and solid stat chips (blue `in`,
 * green `out`, red `exec`, dark `send`; `recv` is plain text there, not a chip).
 *
 * Syntax colors adapt for light mode; chip fills are fixed — white text on a
 * saturated fill reads correctly in both modes. Mirrors the SwiftUI
 * `ProfileSyntaxColors` / `DQLSyntaxHighlighter` / `JSONSyntaxHighlighter` trio.
 */
object ProfileSyntaxColors {
    /** DQL keywords / JSON keys — yellow-olive. */
    val keywordDark = Color(0xFFD8DC6A)
    val keywordLight = Color(0xFF7A7A12)

    /** String literals / JSON string values — light blue. */
    val stringDark = Color(0xFF9ECBFF)
    val stringLight = Color(0xFF0B5CAD)

    /** Solid chip fills (white text in both modes). */
    val chipIn = Color(0xFF2563EB)
    val chipOut = Color(0xFF2E7D32)
    val chipExec = Color(0xFFC62828)
    val chipSend = Color(0xFF424242)

    val keyword: Color
        @Composable get() = if (isSystemInDarkTheme()) keywordDark else keywordLight

    val string: Color
        @Composable get() = if (isSystemInDarkTheme()) stringDark else stringLight
}

/** Syntax-highlighted DQL for read-only display (the Profile header's query text). */
object DqlProfileHighlighter {

    private val keywords = setOf(
        "select", "from", "where", "insert", "update", "delete", "evict", "into",
        "set", "documents", "values", "and", "or", "not", "null", "true", "false",
        "limit", "offset", "order", "by", "asc", "desc", "group", "having", "join",
        "left", "inner", "outer", "on", "as", "distinct", "like", "in", "is",
        "between", "exists", "case", "when", "then", "else", "end", "profile",
        "explain", "alter", "system", "show", "create", "index", "drop", "with",
        "union", "all", "reset",
    )

    fun highlight(
        text: String,
        keywordColor: Color = ProfileSyntaxColors.keywordDark,
        stringColor: Color = ProfileSyntaxColors.stringDark,
    ): AnnotatedString = buildAnnotatedString {
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                c == '\'' -> {
                    // String literal — '' is the DQL escape for a quote inside one.
                    var end = i + 1
                    while (end < text.length) {
                        if (text[end] == '\'') {
                            if (end + 1 < text.length && text[end + 1] == '\'') {
                                end += 2
                            } else {
                                end += 1
                                break
                            }
                        } else {
                            end += 1
                        }
                    }
                    withStyle(SpanStyle(color = stringColor)) { append(text.substring(i, end)) }
                    i = end
                }
                c.isLetter() || c == '_' -> {
                    var end = i
                    while (end < text.length &&
                        (text[end].isLetterOrDigit() || text[end] == '_')
                    ) {
                        end += 1
                    }
                    val word = text.substring(i, end)
                    if (word.lowercase() in keywords) {
                        withStyle(SpanStyle(color = keywordColor)) { append(word) }
                    } else {
                        append(word)
                    }
                    i = end
                }
                else -> {
                    append(c)
                    i += 1
                }
            }
        }
    }
}

/**
 * Highlights a JSON document (the `descriptor`-style attribute values in a plan):
 * keys in the keyword color, string values in the string color, everything else
 * default. Anything unexpected is emitted uncolored rather than dropping characters.
 */
object JsonProfileHighlighter {

    fun highlight(
        text: String,
        keywordColor: Color = ProfileSyntaxColors.keywordDark,
        stringColor: Color = ProfileSyntaxColors.stringDark,
    ): AnnotatedString = buildAnnotatedString {
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (c == '"') {
                // JSON escapes use backslash, not quote doubling.
                var end = i + 1
                while (end < text.length) {
                    if (text[end] == '\\' && end + 1 < text.length) {
                        end += 2
                    } else if (text[end] == '"') {
                        end += 1
                        break
                    } else {
                        end += 1
                    }
                }
                // A string is a key when the next non-whitespace character is ':'.
                var lookahead = end
                while (lookahead < text.length && text[lookahead].isWhitespace()) lookahead += 1
                val isKey = lookahead < text.length && text[lookahead] == ':'
                withStyle(SpanStyle(color = if (isKey) keywordColor else stringColor)) {
                    append(text.substring(i, end))
                }
                i = end
            } else {
                append(c)
                i += 1
            }
        }
    }
}

/** Pretty-prints [value] when it is a JSON object or array; null otherwise. */
fun prettyPrintedJson(value: String): String? {
    val trimmed = value.trim()
    if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return null
    // kotlinx.serialization (not org.json) so this stays unit-testable on the JVM.
    val json = kotlinx.serialization.json.Json { prettyPrint = true }
    return runCatching {
        val element = json.parseToJsonElement(trimmed)
        json.encodeToString(kotlinx.serialization.json.JsonElement.serializer(), element)
    }.getOrNull()
}
