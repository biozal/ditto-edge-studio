package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the profile syntax highlighters. Mirrors the SwiftUI
 * `ProfileSyntaxHighlighterTests` — span colors are read from the
 * [androidx.compose.ui.text.AnnotatedString] directly.
 */
class ProfileSyntaxTest {

    /** The color of the span covering [substring]'s first occurrence, or null. */
    private fun spanColor(
        text: String,
        substring: String,
        highlighted: androidx.compose.ui.text.AnnotatedString,
    ): Color? {
        val start = text.indexOf(substring)
        if (start < 0) return null
        return highlighted.spanStyles.firstOrNull { start >= it.start && start < it.end }?.item?.color
    }

    // --- DQL ---

    @Test
    fun `dql keywords are colored case-insensitively`() {
        val text = "select * FROM movies"
        val highlighted = DqlProfileHighlighter.highlight(text)

        assertEquals(ProfileSyntaxColors.keywordDark, spanColor(text, "select", highlighted))
        assertEquals(ProfileSyntaxColors.keywordDark, spanColor(text, "FROM", highlighted))
    }

    @Test
    fun `dql non-keyword identifiers are not colored`() {
        val text = "SELECT * FROM movies"
        val highlighted = DqlProfileHighlighter.highlight(text)

        assertNull(spanColor(text, "movies", highlighted))
    }

    @Test
    fun `dql string literals get the string color`() {
        val text = "DELETE FROM movies WHERE plot = 'delete-stmt-test-benchmark-uuid'"
        val highlighted = DqlProfileHighlighter.highlight(text)

        assertEquals(
            ProfileSyntaxColors.stringDark,
            spanColor(text, "'delete-stmt-test-benchmark-uuid'", highlighted),
        )
    }

    @Test
    fun `dql doubled-quote escape stays inside the string token`() {
        val text = "WHERE name = 'it''s' AND x = 1"
        val highlighted = DqlProfileHighlighter.highlight(text)

        assertEquals(ProfileSyntaxColors.stringDark, spanColor(text, "'it''s'", highlighted))
        assertEquals(ProfileSyntaxColors.keywordDark, spanColor(text, "AND", highlighted))
    }

    @Test
    fun `dql round trip preserves the source text exactly`() {
        val text = "PROFILE SELECT * FROM t WHERE a = 'x' LIMIT 10"
        assertEquals(text, DqlProfileHighlighter.highlight(text).text)
    }

    // --- JSON ---

    @Test
    fun `json keys use keyword color and string values use string color`() {
        val text = "{\n  \"diff_scan_condition\": \"never\"\n}"
        val highlighted = JsonProfileHighlighter.highlight(text)

        assertEquals(
            ProfileSyntaxColors.keywordDark,
            spanColor(text, "\"diff_scan_condition\"", highlighted),
        )
        assertEquals(ProfileSyntaxColors.stringDark, spanColor(text, "\"never\"", highlighted))
    }

    @Test
    fun `json escaped quotes do not end the token`() {
        val text = "{\"a\": \"b\\\"c\"}"
        val highlighted = JsonProfileHighlighter.highlight(text)

        assertEquals(ProfileSyntaxColors.stringDark, spanColor(text, "\"b\\\"c\"", highlighted))
    }

    @Test
    fun `json round trip preserves the source text exactly`() {
        val text = "{\n  \"a\": [1, true, null]\n}"
        assertEquals(text, JsonProfileHighlighter.highlight(text).text)
    }

    // --- prettyPrintedJson ---

    @Test
    fun `prettyPrintedJson pretty-prints objects`() {
        val pretty = prettyPrintedJson("{\"b\":1,\"a\":\"x\"}")
        assertTrue(pretty != null)
        assertTrue(pretty!!.contains("\n"))
    }

    @Test
    fun `prettyPrintedJson returns null for non-json`() {
        assertNull(prettyPrintedJson("movies"))
        assertNull(prettyPrintedJson("{not json"))
        assertNull(prettyPrintedJson(""))
    }
}
