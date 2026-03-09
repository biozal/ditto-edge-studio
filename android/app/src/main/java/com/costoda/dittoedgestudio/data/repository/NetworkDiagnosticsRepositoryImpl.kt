package com.costoda.dittoedgestudio.data.repository

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.aware.WifiAwareManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.Inet6Address

class NetworkDiagnosticsRepositoryImpl(
    private val context: Context,
) : NetworkDiagnosticsRepository {

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    @Suppress("DEPRECATION")
    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    override fun hasLocationOrNearbyPermission(): Boolean {
        val hasLocation = ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val hasNearby = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            false
        }
        return hasLocation || hasNearby
    }

    override suspend fun fetchInterfaces(): List<NetworkInterfaceInfo> =
        withContext(Dispatchers.IO) {
            val javaInterfaces = buildJavaInterfaceMap()
            val transportMap = buildTransportMap()
            @Suppress("DEPRECATION")
            val wifiInfo = runCatching { wifiManager.connectionInfo }.getOrNull()
            val permGranted = hasLocationOrNearbyPermission()

            val results = mutableListOf<NetworkInterfaceInfo>()

            for ((name, entry) in javaInterfaces) {
                if (entry.isLoopback || entry.isVirtual || !entry.isUp) continue
                if (name.startsWith("lo") || name.startsWith("dummy")) continue
                // Skip cellular, VPN, P2P, Aware interfaces
                if (name.startsWith("rmnet") || name.startsWith("tun") ||
                    name.startsWith("ppp") || name.startsWith("p2p") ||
                    name.startsWith("aware")
                ) continue

                val transport = transportMap[name]
                when {
                    transport == NetworkCapabilities.TRANSPORT_WIFI ||
                        name.startsWith("wlan") -> {
                        results.add(buildWifiInfo(name, entry, wifiInfo, permGranted))
                    }
                    transport == NetworkCapabilities.TRANSPORT_ETHERNET ||
                        name.startsWith("eth") || name.startsWith("usb") -> {
                        results.add(buildEthernetInfo(name, entry))
                    }
                }
            }

            // Sort WiFi first, then Ethernet
            results.sortedWith(
                compareBy(
                    { if (it.kind == NetworkInterfaceInfo.InterfaceKind.Wifi) 0 else 1 },
                    { it.interfaceName },
                ),
            )
        }

    private data class InterfaceEntry(
        val isLoopback: Boolean,
        val isVirtual: Boolean,
        val isUp: Boolean,
        val macAddress: String?,
        val mtu: Int?,
        val ipv4: String?,
        val ipv6: String?,
    )

    private fun buildJavaInterfaceMap(): Map<String, InterfaceEntry> {
        return java.net.NetworkInterface.getNetworkInterfaces()
            ?.toList()
            ?.associate { iface ->
                val mac = iface.hardwareAddress?.takeIf { it.size == 6 }
                    ?.joinToString(":") { "%02x".format(it) }
                val addrs = iface.inetAddresses.toList()
                val ipv4 = addrs.filterIsInstance<Inet4Address>()
                    .firstOrNull { !it.isLoopbackAddress }?.hostAddress
                val ipv6 = addrs.filterIsInstance<Inet6Address>()
                    .firstOrNull { it.isLinkLocalAddress }?.hostAddress
                    ?: addrs.filterIsInstance<Inet6Address>().firstOrNull()?.hostAddress

                iface.name to InterfaceEntry(
                    isLoopback = iface.isLoopback,
                    isVirtual = iface.isVirtual,
                    isUp = iface.isUp,
                    macAddress = mac,
                    mtu = runCatching { iface.mtu }.getOrNull(),
                    ipv4 = ipv4,
                    ipv6 = ipv6,
                )
            } ?: emptyMap()
    }

    private fun buildTransportMap(): Map<String, Int> {
        val map = mutableMapOf<String, Int>()
        @Suppress("DEPRECATION")
        for (network in connectivityManager.allNetworks) {
            val props = connectivityManager.getLinkProperties(network) ?: continue
            val caps = connectivityManager.getNetworkCapabilities(network) ?: continue
            val name = props.interfaceName ?: continue
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                    map[name] = NetworkCapabilities.TRANSPORT_WIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                    map[name] = NetworkCapabilities.TRANSPORT_ETHERNET
            }
        }
        return map
    }

    private fun gatewayFor(interfaceName: String): String? {
        @Suppress("DEPRECATION")
        for (network in connectivityManager.allNetworks) {
            val props = connectivityManager.getLinkProperties(network) ?: continue
            if (props.interfaceName != interfaceName) continue
            return props.routes
                .firstOrNull { it.isDefaultRoute && it.gateway != null }
                ?.gateway?.hostAddress
        }
        return null
    }

    private fun buildWifiInfo(
        name: String,
        entry: InterfaceEntry,
        wifiInfo: WifiInfo?,
        permGranted: Boolean,
    ): NetworkInterfaceInfo {
        val rssi = wifiInfo?.rssi?.takeIf { it > Int.MIN_VALUE }
        val signalLevel = rssi?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                wifiManager.calculateSignalLevel(it)
            } else {
                @Suppress("DEPRECATION")
                WifiManager.calculateSignalLevel(it, 5)
            }
        }
        val freq = wifiInfo?.frequency?.takeIf { it > 0 }
        val standard = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wifiInfo?.wifiStandard?.let { wifiStandardLabel(it) }
        } else {
            null
        }
        val txSpeed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            wifiInfo?.txLinkSpeedMbps?.takeIf { it > 0 }
        } else {
            null
        }
        val rxSpeed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            wifiInfo?.rxLinkSpeedMbps?.takeIf { it > 0 }
        } else {
            null
        }

        @Suppress("DEPRECATION")
        val ssid = if (permGranted) wifiInfo?.ssid?.removeSurrounding("\"") else null
        @Suppress("DEPRECATION")
        val bssid = if (permGranted) wifiInfo?.bssid else null

        return NetworkInterfaceInfo(
            id = name,
            interfaceName = name,
            kind = NetworkInterfaceInfo.InterfaceKind.Wifi,
            isActive = entry.isUp,
            hardwareAddress = entry.macAddress,
            mtu = entry.mtu,
            ipv4Address = entry.ipv4,
            ipv6Address = entry.ipv6,
            gatewayAddress = gatewayFor(name),
            ssid = ssid,
            bssid = bssid,
            rssi = rssi,
            signalLevel = signalLevel,
            linkSpeedMbps = wifiInfo?.linkSpeed?.takeIf { it > 0 },
            txLinkSpeedMbps = txSpeed,
            rxLinkSpeedMbps = rxSpeed,
            frequencyMhz = freq,
            frequencyBandLabel = freq?.let { frequencyBand(it) },
            wifiStandardLabel = standard,
            ethernetBandwidthKbps = null,
            locationPermissionGranted = permGranted,
        )
    }

    private fun buildEthernetInfo(
        name: String,
        entry: InterfaceEntry,
    ): NetworkInterfaceInfo {
        val bandwidth = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            connectivityManager.allNetworks
                .firstOrNull {
                    connectivityManager.getLinkProperties(it)?.interfaceName == name
                }
                ?.let { connectivityManager.getNetworkCapabilities(it)?.linkDownstreamBandwidthKbps }
                ?.takeIf { it > 0 }
        } else {
            null
        }

        return NetworkInterfaceInfo(
            id = name,
            interfaceName = name,
            kind = NetworkInterfaceInfo.InterfaceKind.Ethernet,
            isActive = entry.isUp,
            hardwareAddress = entry.macAddress,
            mtu = entry.mtu,
            ipv4Address = entry.ipv4,
            ipv6Address = entry.ipv6,
            gatewayAddress = gatewayFor(name),
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
            ethernetBandwidthKbps = bandwidth,
            locationPermissionGranted = false,
        )
    }

    override suspend fun fetchP2PTransports(): List<P2PTransportInfo> =
        withContext(Dispatchers.IO) {
            val result = mutableListOf<P2PTransportInfo>()

            // WiFi Aware (requires API 26+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val hasAwareHardware = context.packageManager
                    .hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)
                if (hasAwareHardware) {
                    val awareManager = context.getSystemService(WifiAwareManager::class.java)
                    val isAvailable = awareManager?.isAvailable ?: false
                    result.add(
                        P2PTransportInfo(
                            kind = P2PTransportInfo.Kind.WifiAware,
                            isHardwareAvailable = true,
                            isEnabled = isAvailable,
                            statusDetail = if (isAvailable) {
                                "Hardware ready — Ditto uses this for P2P sync"
                            } else {
                                "Hardware present but not available"
                            },
                        ),
                    )
                }
            }

            // WiFi Direct
            val hasDirectHardware = context.packageManager
                .hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
            if (hasDirectHardware) {
                @Suppress("DEPRECATION")
                val p2pSupported = wifiManager.isP2pSupported
                result.add(
                    P2PTransportInfo(
                        kind = P2PTransportInfo.Kind.WifiDirect,
                        isHardwareAvailable = true,
                        isEnabled = p2pSupported,
                        statusDetail = "Hardware ready — Ditto uses this for P2P WiFi sync",
                    ),
                )
            }

            result
        }

    private fun frequencyBand(mhz: Int): String = when {
        mhz in 2400..2500 -> "2.4 GHz"
        mhz in 4900..5900 -> "5 GHz"
        mhz >= 5925 -> "6 GHz"
        else -> "$mhz MHz"
    }

    private fun wifiStandardLabel(standard: Int): String? = when (standard) {
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
