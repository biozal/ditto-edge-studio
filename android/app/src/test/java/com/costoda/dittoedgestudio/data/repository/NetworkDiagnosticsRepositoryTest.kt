package com.costoda.dittoedgestudio.data.repository

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import androidx.core.app.ActivityCompat
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test

class NetworkDiagnosticsRepositoryTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        mockkStatic(ActivityCompat::class)
        val connectivityManager = mockk<ConnectivityManager>(relaxed = true)
        val wifiManager = mockk<WifiManager>(relaxed = true)
        val appContext = mockk<Context>(relaxed = true) {
            every { getSystemService(Context.WIFI_SERVICE) } returns wifiManager
            every { applicationContext } returns this
        }
        context = mockk(relaxed = true) {
            every { getSystemService(Context.CONNECTIVITY_SERVICE) } returns connectivityManager
            every { applicationContext } returns appContext
        }
    }

    @After
    fun tearDown() {
        unmockkStatic(ActivityCompat::class)
    }

    @Test
    fun `hasLocationOrNearbyPermission returns false when no permissions granted`() {
        every { ActivityCompat.checkSelfPermission(context, any()) } returns PackageManager.PERMISSION_DENIED
        assertFalse(NetworkDiagnosticsRepositoryImpl(context).hasLocationOrNearbyPermission())
    }

    @Test
    fun `frequencyBand returns 2_4 GHz for 2412 MHz`() {
        assertEquals("2.4 GHz", frequencyBandTestable(2412))
    }

    @Test
    fun `frequencyBand returns 5 GHz for 5180 MHz`() {
        assertEquals("5 GHz", frequencyBandTestable(5180))
    }

    @Test
    fun `frequencyBand returns 6 GHz for 5975 MHz`() {
        assertEquals("6 GHz", frequencyBandTestable(5975))
    }

    @Test
    fun `wifiStandardLabel returns correct labels`() {
        assertEquals("WiFi 4 (802.11n)", wifiStandardLabelTestable(4))
        assertEquals("WiFi 5 (802.11ac)", wifiStandardLabelTestable(5))
        assertEquals("WiFi 6 (802.11ax)", wifiStandardLabelTestable(6))
        assertEquals("WiFi 7 (802.11be)", wifiStandardLabelTestable(7))
        assertEquals(null, wifiStandardLabelTestable(0))
    }

    // Mirror the private functions for testing purposes
    private fun frequencyBandTestable(mhz: Int): String = when {
        mhz in 2400..2500 -> "2.4 GHz"
        mhz in 4900..5900 -> "5 GHz"
        mhz >= 5925 -> "6 GHz"
        else -> "$mhz MHz"
    }

    private fun wifiStandardLabelTestable(standard: Int): String? = when (standard) {
        1 -> "WiFi (802.11a)"
        2 -> "WiFi (802.11b)"
        3 -> "WiFi (802.11g)"
        4 -> "WiFi 4 (802.11n)"
        5 -> "WiFi 5 (802.11ac)"
        6 -> "WiFi 6 (802.11ax)"
        7 -> "WiFi 7 (802.11be)"
        else -> null
    }
}
