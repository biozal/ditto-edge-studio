package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class NetworkInterfaceInfoTest {

    @Test
    fun `default WiFi info has correct kind`() {
        val info = makeWifiInfo()
        assertEquals(NetworkInterfaceInfo.InterfaceKind.Wifi, info.kind)
    }

    @Test
    fun `default Ethernet info has correct kind`() {
        val info = makeEthernetInfo()
        assertEquals(NetworkInterfaceInfo.InterfaceKind.Ethernet, info.kind)
    }

    @Test
    fun `WiFi fields default to null for Ethernet`() {
        val info = makeEthernetInfo()
        assertNull(info.ssid)
        assertNull(info.rssi)
        assertNull(info.frequencyMhz)
        assertFalse(info.locationPermissionGranted)
    }

    @Test
    fun `Ethernet bandwidth field is null for WiFi`() {
        val info = makeWifiInfo()
        assertNull(info.ethernetBandwidthKbps)
    }

    private fun makeWifiInfo() = NetworkInterfaceInfo(
        id = "wlan0",
        interfaceName = "wlan0",
        kind = NetworkInterfaceInfo.InterfaceKind.Wifi,
        isActive = true,
        hardwareAddress = "02:00:00:00:00:00",
        mtu = 1500,
        ipv4Address = "192.168.1.100",
        ipv6Address = null,
        gatewayAddress = "192.168.1.1",
        ssid = null,
        bssid = null,
        rssi = null,
        signalLevel = null,
        linkSpeedMbps = 144,
        txLinkSpeedMbps = null,
        rxLinkSpeedMbps = null,
        frequencyMhz = null,
        frequencyBandLabel = null,
        wifiStandardLabel = null,
        ethernetBandwidthKbps = null,
        locationPermissionGranted = false,
    )

    private fun makeEthernetInfo() = NetworkInterfaceInfo(
        id = "eth0",
        interfaceName = "eth0",
        kind = NetworkInterfaceInfo.InterfaceKind.Ethernet,
        isActive = true,
        hardwareAddress = "aa:bb:cc:dd:ee:ff",
        mtu = 1500,
        ipv4Address = "10.0.0.5",
        ipv6Address = null,
        gatewayAddress = "10.0.0.1",
        ssid = null,
        bssid = null,
        rssi = null,
        signalLevel = null,
        linkSpeedMbps = null,
        txLinkSpeedMbps = null,
        rxLinkSpeedMbps = null,
        frequencyMhz = null,
        frequencyBandLabel = null,
        wifiStandardLabel = null,
        ethernetBandwidthKbps = 1_000_000,
        locationPermissionGranted = false,
    )
}
