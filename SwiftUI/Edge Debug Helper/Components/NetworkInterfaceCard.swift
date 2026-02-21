import SwiftUI

/// Adaptive card that renders diagnostic information for a single network interface.
///
/// **WiFi** (green gradient): SSID, BSSID, signal/noise/SNR, channel, PHY mode,
/// security, country, IPv4/IPv6, gateway, AWDL status, Location permission prompt.
///
/// **Ethernet** (teal gradient): MAC, IPv4/IPv6, gateway, link speed, duplex, MTU.
///
/// Rows that have `nil` values are silently omitted — the card is always safe to render
/// even when optional diagnostics (location, iokit-user-client) are unavailable.
struct NetworkInterfaceCard: View {
    let info: NetworkInterfaceInfo

    private var cardStartColor: Color {
        switch info.kind {
        case .wifi: return Color(red: 0.05, green: 0.52, blue: 0.25)
        case .ethernet: return Color(red: 0.05, green: 0.45, blue: 0.50)
        case .other: return Color(red: 0.35, green: 0.35, blue: 0.40)
        }
    }

    private var cardEndColor: Color {
        switch info.kind {
        case .wifi: return Color(red: 0.02, green: 0.32, blue: 0.14)
        case .ethernet: return Color(red: 0.02, green: 0.28, blue: 0.32)
        case .other: return Color(red: 0.20, green: 0.20, blue: 0.25)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)

            if info.isActive {
                activeContentView
            } else {
                notConnectedView
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 280, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [cardStartColor, cardEndColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Sub-views

    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                FontAwesomeText(
                    icon: info.kind == .wifi ? ConnectivityIcon.wifi : ConnectivityIcon.ethernet,
                    size: 14,
                    color: .white
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.kind == .wifi ? "Wi-Fi" : "Ethernet")
                        .font(.headline).bold()
                        .foregroundColor(.white)
                    Text("(\(info.interfaceName))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.70))
                }
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(info.isActive ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text(info.isActive ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }

    private var activeContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // WiFi: SSID as prominent label
            if info.kind == .wifi, let ssid = info.ssid {
                Text(ssid)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
            }

            // BSSID (WiFi, requires Location)
            if info.kind == .wifi, let bssid = info.bssid {
                NetInfoRow(label: "BSSID", value: bssid)
            }

            // Hardware address
            if let mac = info.hardwareAddress {
                NetInfoRow(label: "Hardware", value: mac)
            }

            // WiFi signal metrics
            if info.kind == .wifi {
                if let rssi = info.rssi, let noise = info.noise {
                    HStack(spacing: 0) {
                        NetInfoRow(label: "Signal", value: "\(rssi) dBm")
                        Spacer()
                        NetInfoRow(label: "Noise", value: "\(noise) dBm")
                    }
                    if let snr = info.snr {
                        NetInfoRow(label: "SNR", value: "\(snr) dB")
                    }
                }
                if let txRate = info.transmitRate {
                    NetInfoRow(label: "Tx Rate", value: String(format: "%.0f Mbps", txRate))
                }
                if let ch = info.channelNumber {
                    let extras = [info.channelBandLabel, info.channelWidthLabel]
                        .compactMap(\.self).joined(separator: ", ")
                    NetInfoRow(label: "Channel", value: extras.isEmpty ? "\(ch)" : "\(ch) (\(extras))")
                }
                if let phy = info.phyModeLabel {
                    if let sec = info.securityLabel {
                        HStack(spacing: 0) {
                            NetInfoRow(label: "PHY", value: phy)
                            Spacer()
                            NetInfoRow(label: "Security", value: sec)
                        }
                    } else {
                        NetInfoRow(label: "PHY", value: phy)
                    }
                }
                if let cc = info.countryCode {
                    NetInfoRow(label: "Country", value: cc)
                }
            }

            // Common: IPv4, IPv6, gateway
            if let ipv4 = info.ipv4Address {
                NetInfoRow(label: "IPv4", value: ipv4)
            }
            if let ipv6 = info.ipv6Address {
                NetInfoRow(label: "IPv6", value: ipv6)
            }
            if let gw = info.gatewayAddress {
                NetInfoRow(label: "Gateway", value: gw)
            }

            // Ethernet-specific
            if info.kind == .ethernet {
                if let speed = info.linkSpeedMbps {
                    NetInfoRow(label: "Speed", value: "\(speed) Mbps")
                }
                if let duplex = info.linkDuplexLabel {
                    NetInfoRow(label: "Duplex", value: duplex)
                }
                if let mtu = info.mtu {
                    NetInfoRow(label: "MTU", value: "\(mtu)")
                }
            }

            // WiFi: AWDL status
            if info.kind == .wifi {
                HStack {
                    Text("AWDL")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(info.awdlActive ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(info.awdlActive ? "Active" : "Inactive")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.80))
                    }
                }
            }

            // WiFi: Location permission prompt (only shown when denied/undetermined)
            if info.kind == .wifi, !info.locationPermissionGranted {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Grant Location in System Settings")
                            .font(.caption).bold()
                            .foregroundColor(.white)
                        Text("to show SSID and BSSID")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.70))
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var notConnectedView: some View {
        Text("Not Connected")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}

/// Label–value row for use inside dark-gradient network cards.
/// Matches the layout of `InfoRow` from `LocalPeerInfoCard` but with white text.
private struct NetInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
