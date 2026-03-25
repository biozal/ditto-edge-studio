# Network Diagnostics — Android

Edge Studio displays network interface information in the Peers List tab under a "Local Network" section. This document explains the API sources, permissions, and platform differences.

---

## Data Sources by Field

### `java.net.NetworkInterface` (Primary — no permissions required)

Available on all Android API levels without any runtime permissions:

| Field | Source |
|-------|--------|
| Interface name | `NetworkInterface.getName()` |
| Hardware/MAC address | `NetworkInterface.getHardwareAddress()` → format as `%02x:` |
| MTU | `NetworkInterface.getMTU()` |
| Is up | `NetworkInterface.isUp()` |
| Is loopback | `NetworkInterface.isLoopback()` |
| Is virtual | `NetworkInterface.isVirtual()` |
| IPv4 address | `getInetAddresses()` → first `Inet4Address` |
| IPv6 address | `getInetAddresses()` → first link-local `Inet6Address` |

### `WifiManager.getConnectionInfo()` — `WifiInfo` (WiFi-specific)

| Field | Permission Required |
|-------|-------------------|
| RSSI (`getRssi()`) | **None** |
| Link speed (`getLinkSpeed()`) | **None** |
| Frequency (`getFrequency()`) | **None** |
| WiFi standard (`getWifiStandard()`) | **None** — API 30+ |
| TX link speed (`getTxLinkSpeedMbps()`) | **None** — API 31+ |
| RX link speed (`getRxLinkSpeedMbps()`) | **None** — API 31+ |
| SSID | `ACCESS_FINE_LOCATION` (API ≤ 32) or `NEARBY_WIFI_DEVICES` (API 33+) |
| BSSID | Same as SSID |

> **Note:** `WifiManager.getConnectionInfo()` is deprecated in API 31. A future update will migrate to `NetworkCapabilities.getTransportInfo()` on API 31+.

### `ConnectivityManager` (Gateway / transport type)

| Field | Source |
|-------|--------|
| Gateway address | `getLinkProperties().getRoutes()` → first default route gateway |
| Transport type (WiFi vs Ethernet) | `getNetworkCapabilities().hasTransport(TRANSPORT_WIFI / TRANSPORT_ETHERNET)` |
| Ethernet downstream bandwidth | `getNetworkCapabilities().linkDownstreamBandwidthKbps` — API 29+ |

---

## Permission Requirements

| Feature | API ≤ 32 | API 33+ |
|---------|----------|---------|
| SSID / BSSID | `ACCESS_FINE_LOCATION` | `NEARBY_WIFI_DEVICES` (with `neverForLocation`) |
| All other WiFi fields | None | None |
| Network interface enumeration | None | None |
| MAC / MTU / IP addresses | None | None |

The app shows a yellow warning row in the WiFi card when SSID/BSSID cannot be shown due to missing permissions.

---

## Android vs iOS Capability Comparison

| Field | iOS (macOS) | iOS (iPadOS) | Android |
|-------|------------|--------------|---------|
| SSID | ✅ CoreWLAN | ❌ | ✅ WifiInfo (needs permission) |
| BSSID | ✅ CoreWLAN | ❌ | ✅ WifiInfo (needs permission) |
| RSSI | ✅ CoreWLAN | ❌ | ✅ WifiInfo (no permission) |
| Noise floor | ✅ CoreWLAN | ❌ | ❌ Not available |
| SNR | ✅ Computed | ❌ | ❌ Cannot compute (no noise floor) |
| TX rate / link speed | ✅ CoreWLAN | ❌ | ✅ WifiInfo (no permission) |
| TX/RX speeds separate | — | — | ✅ API 31+ |
| Channel number | ✅ CoreWLAN | ❌ | ❌ Frequency only |
| Frequency band | ✅ | ❌ | ✅ Derived from frequency |
| WiFi PHY mode | ✅ CoreWLAN (802.11n/ac/ax) | ❌ | ✅ WifiInfo API 30+ |
| Security type | ✅ CoreWLAN | ❌ | ❌ ScanResult only, not on active connection |
| MTU | ✅ ioctl | ❌ | ✅ NetworkInterface.getMTU() |
| MAC address | ✅ getifaddrs | ✅ | ✅ (may be randomized — see below) |
| IPv4 / IPv6 | ✅ getifaddrs | ✅ | ✅ NetworkInterface.getInetAddresses() |
| Gateway | ✅ SCDynamicStore | ✅ | ✅ LinkProperties.getRoutes() |
| AWDL / WiFi Aware | AWDL (Apple-only) | AWDL | WiFi Aware (NAN) — separate card |
| WiFi Direct | ❌ N/A | ❌ N/A | ✅ Status card |

---

## MAC Address Randomization (Android 8+)

Starting with Android 8.0 (API 26), Android randomizes the MAC address for WiFi connections to improve privacy. `NetworkInterface.getHardwareAddress()` returns `02:00:00:00:00:00` (the randomized placeholder) for WiFi interfaces.

- The value is still displayed to the user
- The app notes internally that this may not reflect the physical hardware address
- This is a privacy feature, not a bug

For Ethernet interfaces, the real MAC address is returned.

---

## No Noise Floor / SNR on Android

`WifiInfo` does not expose a noise floor measurement. This is by design — Android does not expose raw noise measurements to apps. As a result:

- SNR (Signal-to-Noise Ratio) **cannot be computed** on Android
- Only RSSI in dBm is shown, with a derived signal bar (0..4 levels)
- This is different from iOS/macOS which provides noise via CoreWLAN

---

## WiFi Aware vs AWDL

| Feature | iOS AWDL | Android WiFi Aware (NAN) |
|---------|----------|--------------------------|
| Protocol | Apple Wireless Direct Link (proprietary) | Wi-Fi Aware / NAN (IEEE 802.11ah-based) |
| Range | ~30m (same as WiFi Direct) | ~10m typical |
| Ditto role | P2P transport | P2P transport |
| Card shown | P2P WiFi transport stats (iOS) | WiFi Aware status card (Android) |

Both serve the same role in Ditto: direct device-to-device sync without infrastructure WiFi.

---

## WiFi Standard Label Mapping

From `WifiInfo.getWifiStandard()` (API 30+):

| Constant | Value | Label |
|----------|-------|-------|
| `WIFI_STANDARD_UNKNOWN` | 0 | (not shown) |
| `WIFI_STANDARD_11A` | 1 | WiFi (802.11a) |
| `WIFI_STANDARD_11B` | 2 | WiFi (802.11b) |
| `WIFI_STANDARD_11G` | 3 | WiFi (802.11g) |
| `WIFI_STANDARD_11N` | 4 | WiFi 4 (802.11n) |
| `WIFI_STANDARD_11AC` | 5 | WiFi 5 (802.11ac) |
| `WIFI_STANDARD_11AX` | 6 | WiFi 6 (802.11ax) |
| `WIFI_STANDARD_11BE` | 7 | WiFi 7 (802.11be) |

---

## P2P Transport Status Cards

### WiFi Aware Card
- Shown only if `PackageManager.hasSystemFeature(FEATURE_WIFI_AWARE)` returns `true`
- Requires API 26+
- Uses `WifiAwareManager.isAvailable()` for availability status

### WiFi Direct Card
- Shown only if `PackageManager.hasSystemFeature(FEATURE_WIFI_DIRECT)` returns `true`
- Uses `WifiManager.isP2pSupported` for enabled status
- Does **not** trigger active peer discovery (that would require `WifiP2pManager.discoverPeers()`)
