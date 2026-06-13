package com.costoda.dittoedgestudio.ui.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Graph-level safety test: [StudioScaffold] must be called exactly ONCE in [AppNavGraph].
 *
 * ## What bug this catches
 *
 * The shell-layout bug that prompted FU-6 was caused by [StudioScaffold] being composed
 * *per-scene-entry* inside the [NavDisplay]'s entry provider block, rather than hoisted above
 * it. That caused the [ListDetailSceneStrategy] to place TWO scaffolds side-by-side — the
 * Rail+Inspector chrome appeared in both the list pane and the detail pane simultaneously.
 *
 * The fix (chrome hoisting) moved the single [StudioScaffold] call to wrap the entire
 * [NavDisplay] outside the entryProvider lambda. This test asserts that contract at the
 * source-text level so a future accidental move back inside the entryProvider fails the unit
 * test suite before it ships.
 *
 * ## Why source-level grep, not a runtime test
 *
 * A Compose runtime test cannot easily assert "there is only one scaffold in the composition
 * tree" in a way that actually catches this bug: the bug manifested visually (two scaffolds
 * laid out side-by-side by adaptive layout), not as a crash or assertion failure. The source
 * grep is coarse but it directly encodes the architectural invariant: the word
 * `StudioScaffold(` must appear in AppNavGraph.kt exactly once. If it ever appears more than
 * once, someone composed multiple scaffolds — the bug class is back.
 *
 * ## Fragility acknowledgement
 *
 * This test reads the source file path from the expected project layout. If AppNavGraph.kt
 * moves to a different directory or is renamed, this test will fail with a clear file-not-found
 * message rather than silently pass. That is intentional: the test failing from a rename is
 * much better than it silently passing while the architectural constraint is violated.
 */
class StudioScaffoldHoistTest {

    @Test
    fun `AppNavGraph contains exactly one StudioScaffold call site`() {
        // Locate AppNavGraph.kt relative to the compiled test class file so the path works
        // regardless of which machine or CI agent runs the test.
        val testClassFile = File(
            StudioScaffoldHoistTest::class.java.protectionDomain?.codeSource?.location?.toURI()
                ?: error("Cannot determine test class location — code source is null."),
        )
        // Walk up from <module>/build/intermediates/... to the module root, then descend to src.
        // Use a robust search rather than a hard-coded relative path.
        val moduleRoot = generateSequence(testClassFile) { it.parentFile }
            .firstOrNull { it.resolve("src").exists() }
            ?: error(
                "Could not locate module root from test class location: $testClassFile. " +
                    "Ensure the test runs with the standard Android Gradle project layout.",
            )

        val navGraphFile = moduleRoot.resolve(
            "src/main/java/com/costoda/dittoedgestudio/ui/navigation/AppNavGraph.kt",
        )

        assertTrue(
            "AppNavGraph.kt not found at $navGraphFile — if the file was moved or renamed, " +
                "update this test to point at the new location.",
            navGraphFile.exists(),
        )

        val source = navGraphFile.readText()

        // Count call sites: `StudioScaffold(` at the start of a statement line (leading
        // whitespace, then the name). We look for lines where StudioScaffold( appears as a
        // call expression — i.e., the line (after stripping leading whitespace) starts with
        // "StudioScaffold(". This excludes comment lines ("// ... StudioScaffold (...)") and
        // KDoc references ("[StudioScaffold]"), which are not call sites.
        val callSites = source.lines()
            .filter { line ->
                val trimmed = line.trimStart()
                // Must start with "StudioScaffold(" — no leading comment marker.
                trimmed.startsWith("StudioScaffold(") &&
                    !trimmed.startsWith("//") &&
                    !trimmed.startsWith("*")
            }

        assertEquals(
            "AppNavGraph.kt must contain EXACTLY ONE StudioScaffold( call site. " +
                "Found ${callSites.size} match(es):\n" +
                callSites.joinToString("\n") { "  >> ${it.trim()}" } + "\n" +
                "The architectural invariant is: StudioScaffold wraps the entire NavDisplay " +
                "exactly once (chrome hoisting). Composing it per-scene-entry causes " +
                "ListDetailSceneStrategy to place two scaffolds side-by-side (FU-6 regression).",
            1,
            callSites.size,
        )
    }
}
