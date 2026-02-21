import Foundation

/// Unified model for a single network interface (WiFi or Ethernet).
/// WiFi-specific fields are `nil` for Ethernet cards and vice versa.
struct NetworkInterfaceInfo: Identifiable {
    enum InterfaceKind { case wifi, ethernet, other }

    let id: String // interface name ("en0")
    let interfaceName: String // "en0", "en1"
    let kind: InterfaceKind
    let isActive: Bool // IFF_UP & IFF_RUNNING from getifaddrs

    // Common
    let hardwareAddress: String? // MAC — getifaddrs sockaddr_dl
    let ipv4Address: String? // getifaddrs AF_INET
    let ipv6Address: String? // getifaddrs AF_INET6 (link-local preferred)
    let gatewayAddress: String? // SCDynamicStore State:/Network/Interface/{name}/IPv4

    // WiFi-only (nil for Ethernet)
    let ssid: String? // CoreWLAN CWInterface.ssid — requires Location
    let bssid: String? // CoreWLAN — requires Location
    let rssi: Int? // CoreWLAN rssiValue — dBm, no Location needed
    let noise: Int? // CoreWLAN noiseMeasurement — dBm
    let transmitRate: Double? // CoreWLAN transmitRate — Mbps
    let channelNumber: Int? // CoreWLAN wlanChannel.channelNumber
    let channelBandLabel: String? // "2.4 GHz" / "5 GHz" / "6 GHz"
    let channelWidthLabel: String? // "20 MHz" / "40 MHz" / "80 MHz" / "160 MHz"
    let phyModeLabel: String? // "802.11ax" / "802.11ac" / "802.11n" etc.
    let securityLabel: String? // "WPA3 Personal" / "WPA2 Personal" / "Open"
    let countryCode: String? // CoreWLAN countryCode
    let awdlActive: Bool // awdl0 present in NWPathMonitor path
    let locationPermissionGranted: Bool

    // Ethernet-only (nil for WiFi)
    let linkSpeedMbps: Int? // ioctl(SIOCGIFMEDIA) — nil if unavailable
    let linkDuplexLabel: String? // "Full Duplex" / "Half Duplex"
    let mtu: Int? // ioctl(SIOCGIFMTU)

    /// Signal-to-noise ratio in dB (WiFi only)
    var snr: Int? {
        guard let r = rssi, let n = noise else { return nil }
        return r - n
    }
}
