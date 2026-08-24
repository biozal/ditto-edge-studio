package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.ditto.kotlin.DittoLogLevel
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class LogPatternStoreTest {

    private lateinit var tempDir: File
    private lateinit var userFile: File

    private val bundledJson = """
        {
          "deadlock_critical": {
            "pattern": "(?:deadlock|write transaction).*elapsed",
            "level_filter": "error",
            "severity": 5,
            "recommendation": "Possible deadlock."
          },
          "memory_oom": {
            "pattern": "out of memory|OOMKiller",
            "severity": 4,
            "recommendation": "Memory pressure detected."
          }
        }
    """.trimIndent()

    @Before
    fun setUp() {
        tempDir = Files.createTempDirectory("pattern-store-test").toFile()
        userFile = File(tempDir, "log-analyzer/user_patterns.json")
    }

    @After
    fun tearDown() {
        tempDir.deleteRecursively()
    }

    private fun store(bundled: String? = bundledJson) =
        LogPatternStore(userPatternsFile = userFile, bundledJsonLoader = { bundled })

    private fun userPattern(name: String = "boom") =
        LogPatternBody(pattern = name, severity = 2, recommendation = "deal with $name")

    @Test
    fun `bundled patterns load with parsed level filter and source`() {
        val s = store()
        val p = s.patterns.value.getValue("deadlock_critical")
        assertEquals(PatternSource.BUNDLED, p.source)
        assertEquals(DittoLogLevel.Error, p.levelFilter)
        assertEquals(5, p.severity)
        assertTrue(s.patternErrors.value.isEmpty())
    }

    @Test
    fun `missing bundled asset yields empty catalog without crashing`() {
        val s = store(bundled = null)
        assertTrue(s.patterns.value.isEmpty())
    }

    @Test
    fun `corrupt bundled json yields empty catalog`() {
        val s = store(bundled = "{ not json")
        assertTrue(s.patterns.value.isEmpty())
    }

    @Test
    fun `invalid bundled entries are dropped and reported`() {
        val s = store(
            bundled = """
                { "bad_severity": { "pattern": "x", "severity": 9, "recommendation": "r" } }
            """.trimIndent(),
        )
        assertTrue(s.patterns.value.isEmpty())
        assertEquals(listOf("bad_severity"), s.patternErrors.value.keys.toList())
    }

    @Test
    fun `missing user file is tolerated`() {
        val s = store()
        assertFalse(userFile.exists())
        assertEquals(2, s.patterns.value.size)
    }

    @Test
    fun `corrupt user file is tolerated and bundled still loads`() {
        userFile.parentFile!!.mkdirs()
        userFile.writeText("not json {")
        val s = store()
        assertEquals(2, s.patterns.value.size)
    }

    @Test
    fun `add persists user pattern and publishes it`() = runTest {
        val s = store()
        s.add("my_rule", userPattern())
        assertTrue(s.patterns.value.containsKey("my_rule"))
        assertEquals(PatternSource.USER, s.patterns.value.getValue("my_rule").source)
        assertTrue(userFile.exists())
        // Survives a fresh store instance (round-trip through the file).
        val reloaded = store()
        assertTrue(reloaded.patterns.value.containsKey("my_rule"))
    }

    @Test
    fun `add rejects bundled key collision`() = runTest {
        val s = store()
        var thrown = false
        try {
            s.add("deadlock_critical", userPattern())
        } catch (e: IllegalArgumentException) {
            thrown = true
            assertTrue(e.message!!.contains("bundled"))
        }
        assertTrue(thrown)
        assertFalse(userFile.exists())
    }

    @Test
    fun `add rejects duplicate user key`() = runTest {
        val s = store()
        s.add("my_rule", userPattern())
        var thrown = false
        try {
            s.add("my_rule", userPattern("other"))
        } catch (e: IllegalArgumentException) {
            thrown = true
        }
        assertTrue(thrown)
    }

    @Test
    fun `update changes an existing user pattern only`() = runTest {
        val s = store()
        s.add("my_rule", userPattern())
        s.update("my_rule", userPattern("kaboom"))
        assertEquals("kaboom", s.patterns.value.getValue("my_rule").body.pattern)

        var thrown = false
        try {
            s.update("deadlock_critical", userPattern())
        } catch (e: IllegalArgumentException) {
            thrown = true
            assertTrue(e.message!!.contains("not a user pattern"))
        }
        assertTrue(thrown)
    }

    @Test
    fun `delete removes only user patterns`() = runTest {
        val s = store()
        s.add("my_rule", userPattern())
        s.delete("my_rule")
        assertFalse(s.patterns.value.containsKey("my_rule"))

        var thrown = false
        try {
            s.delete("deadlock_critical")
        } catch (e: IllegalArgumentException) {
            thrown = true
        }
        assertTrue(thrown)
        assertTrue(s.patterns.value.containsKey("deadlock_critical"))
    }

    @Test
    fun `reload picks up externally edited user file`() = runTest {
        val s = store()
        userFile.parentFile!!.mkdirs()
        userFile.writeText(
            """{ "external": { "pattern": "e", "severity": 1, "recommendation": "r" } }""",
        )
        s.reload()
        assertTrue(s.patterns.value.containsKey("external"))
    }
}
