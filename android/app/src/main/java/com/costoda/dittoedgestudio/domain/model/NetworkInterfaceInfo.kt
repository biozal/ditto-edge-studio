package com.costoda.dittoedgestudio.domain.model

data class NetworkInterfaceInfo(
    val id: String,
    val interfaceName: String,
    val kind: InterfaceKind,
    val isActive: Boolean,

    // Common (all kinds) — source: java.net.NetworkInterface (no permissions required)
    val hardwareAddress: String?,   // MAC — may be "02:00:00:00:00:00" on Android 8+ (randomized)
    val mtu: Int?,
    val ipv4Address: String?,
    val ipv6Address: String?,
    // Source: ConnectivityManager.getLinkProperties().getRoutes()
    val gatewayAddress: String?,

    // WiFi-specific (null for Ethernet)
    val ssid: String?,              // Requires location or NEARBY_WIFI_DEVICES permission
    val bssid: String?,             // Requires location or NEARBY_WIFI_DEVICES permission
    val rssi: Int?,                 // dBm — no permission required
    val signalLevel: Int?,          // 0..4 from WifiManager.calculateSignalLevel
    val linkSpeedMbps: Int?,        // WifiInfo.getLinkSpeed() — no permission required
    val txLinkSpeedMbps: Int?,      // WifiInfo.getTxLinkSpeedMbps() — API 31+
    val rxLinkSpeedMbps: Int?,      // WifiInfo.getRxLinkSpeedMbps() — API 31+
    val frequencyMhz: Int?,
    val frequencyBandLabel: String?, // "2.4 GHz" / "5 GHz" / "6 GHz"
    val wifiStandardLabel: String?,  // "WiFi 6 (802.11ax)" — API 30+

    // Ethernet-specific (null for WiFi)
    val ethernetBandwidthKbps: Int?, // API 29+

    // Permission state
    val locationPermissionGranted: Boolean,
) {
    enum class InterfaceKind { Wifi, Ethernet, Other }
}
