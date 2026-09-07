package com.costoda.dittoedgestudio.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.costoda.dittoedgestudio.domain.model.SystemMetricSeriesRef
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

class AppPreferencesTest {

    private lateinit var tmpDir: File
    private lateinit var prefs: AppPreferences

    @Before
    fun setUp() {
        tmpDir = File.createTempFile("appprefs", ".dir").apply { delete(); mkdirs() }
        val store = PreferenceDataStoreFactory.create { File(tmpDir, "prefs.preferences_pb") }
        prefs = AppPreferences(store)
    }

    @After
    fun tearDown() { tmpDir.deleteRecursively() }

    @Test
    fun `metricsEnabled defaults to true`() = runTest {
        assertTrue(prefs.metricsEnabled.first())
    }

    @Test
    fun `setMetricsEnabled persists across reads`() = runTest {
        prefs.setMetricsEnabled(false)
        assertEquals(false, prefs.metricsEnabled.first())
        prefs.setMetricsEnabled(true)
        assertEquals(true, prefs.metricsEnabled.first())
    }

    // ── Pinned system-metrics series ─────────────────────────────────────────

    private fun ref(key: String, labels: Map<String, String> = emptyMap()) =
        SystemMetricSeriesRef(key, labels)

    @Test
    fun `systemMetricPins defaults to empty`() = runTest {
        assertEquals(emptyList<SystemMetricSeriesRef>(), prefs.systemMetricPins(1L).first())
    }

    @Test
    fun `pins round-trip in pin order`() = runTest {
        val pins = listOf(ref("b.metric"), ref("a.metric", mapOf("transport" to "ble")))

        prefs.setSystemMetricPins(1L, pins)

        // Pin order is preserved, not sorted.
        assertEquals(pins, prefs.systemMetricPins(1L).first())
    }

    @Test
    fun `pins are scoped per database`() = runTest {
        prefs.setSystemMetricPins(1L, listOf(ref("a.metric")))

        assertEquals(emptyList<SystemMetricSeriesRef>(), prefs.systemMetricPins(2L).first())
    }

    @Test
    fun `duplicate series are collapsed, first occurrence wins`() = runTest {
        prefs.setSystemMetricPins(1L, listOf(ref("a.metric"), ref("b.metric"), ref("a.metric")))

        assertEquals(listOf(ref("a.metric"), ref("b.metric")), prefs.systemMetricPins(1L).first())
    }

    @Test
    fun `label order does not change series identity`() = runTest {
        val ordered = ref("a.metric", linkedMapOf("db" to "main", "op" to "fsync"))
        val reversed = ref("a.metric", linkedMapOf("op" to "fsync", "db" to "main"))

        prefs.setSystemMetricPins(1L, listOf(ordered, reversed))

        // Same series → deduped down to one row.
        assertEquals(1, prefs.systemMetricPins(1L).first().size)
    }

    @Test
    fun `clearing pins removes them`() = runTest {
        prefs.setSystemMetricPins(1L, listOf(ref("a.metric")))

        prefs.setSystemMetricPins(1L, emptyList())

        assertEquals(emptyList<SystemMetricSeriesRef>(), prefs.systemMetricPins(1L).first())
    }
}
