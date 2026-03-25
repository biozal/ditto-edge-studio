package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation

private val DQL_KEYWORDS = setOf(
    "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "EVICT", "EXECUTE",
    "AND", "OR", "NOT", "IN", "LIKE", "LIMIT", "OFFSET", "ORDER", "BY",
    "GROUP", "DISTINCT", "AS", "JOIN", "INTO", "VALUES", "SET", "EXPLAIN",
)

private val DQL_LITERALS = setOf("true", "false", "null")

private val FUNCTION_PATTERN = Regex("\\b(count|sum|avg|min|max)\\s*\\(", RegexOption.IGNORE_CASE)

private val KEYWORD_COLOR = Color(0xFF569CD6)     // blue
private val LITERAL_COLOR = Color(0xFF9CDCFE)     // light blue
private val FUNCTION_COLOR = Color(0xFFDCDCAA)    // yellow

class DqlSyntaxHighlighter : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val annotated = buildAnnotatedString {
            append(text)
            applyHighlights(text.text, this)
        }
        return TransformedText(annotated, OffsetMapping.Identity)
    }

    private fun applyHighlights(source: String, builder: AnnotatedString.Builder) {
        // Highlight DQL keywords (case-insensitive, whole word)
        val wordPattern = Regex("\\b(\\w+)\\b")
        for (match in wordPattern.findAll(source)) {
            val word = match.value
            when {
                DQL_KEYWORDS.contains(word.uppercase()) -> {
                    builder.addStyle(
                        SpanStyle(color = KEYWORD_COLOR, fontWeight = FontWeight.SemiBold),
                        match.range.first,
                        match.range.last + 1,
                    )
                }
                DQL_LITERALS.contains(word.lowercase()) -> {
                    builder.addStyle(
                        SpanStyle(color = LITERAL_COLOR),
                        match.range.first,
                        match.range.last + 1,
                    )
                }
            }
        }
        // Highlight functions
        for (match in FUNCTION_PATTERN.findAll(source)) {
            val nameEnd = match.range.first + match.groupValues[1].length
            builder.addStyle(
                SpanStyle(color = FUNCTION_COLOR),
                match.range.first,
                nameEnd,
            )
        }
    }
}
