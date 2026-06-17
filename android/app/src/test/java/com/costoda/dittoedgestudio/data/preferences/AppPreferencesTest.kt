package com.costoda.dittoedgestudio.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
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
}
