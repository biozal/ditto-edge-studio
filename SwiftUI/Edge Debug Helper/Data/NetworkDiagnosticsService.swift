import CoreLocation
import Darwin
import Foundation
import Network
import SystemConfiguration

#if os(macOS)
import CoreWLAN
#endif

/// Actor singleton that discovers active network interfaces and returns diagnostic snapshots.
///
/// **Interface discovery**: `NWPathMonitor` (type-safe WiFi / wiredEthernet filter)
/// **WiFi data**: `CWWiFiClient` (CoreWLAN, macOS only)
/// **MAC + IP addresses**: `getifaddrs()`
/// **Gateway**: `SCDynamicStore`
/// **MTU**: `ioctl(SIOCGIFMTU)`
/// **Ethernet link speed/duplex**: `ioctl(SIOCGIFMEDIA)` — graceful nil fallback if unavailable
actor NetworkDiagnosticsService {
    static let shared = NetworkDiagnosticsService()

    private var monitorTask: Task<Void, Never>?
    private var awdlActiveFromMonitor = false

    private init() {}

    // MARK: - Public API

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            let monitor = NWPathMonitor()
            let stream = AsyncStream<NWPath> { cont in
                monitor.pathUpdateHandler = { path in cont.yield(path) }
                monitor.start(queue: DispatchQueue(label: "NetworkDiagnosticsMonitor"))
                cont.onTermination = { _ in monitor.cancel() }
            }
            for await path in stream {
                awdlActiveFromMonitor = path.availableInterfaces.contains { $0.name == "awdl0" }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Returns a snapshot of all active WiFi and Ethernet interfaces with diagnostic data.
    func fetchAllInterfaces() async -> [NetworkInterfaceInfo] {
        let (nwInterfaces, snapshotAwdl) = await snapshotInterfaces()
        let awdlActive = awdlActiveFromMonitor || snapshotAwdl

        let addrsMap = buildAddressMap()
        let gatewayMap = buildGatewayMap()
        let locationGranted = await checkLocationPermission()

        var results: [NetworkInterfaceInfo] = []

        for iface in nwInterfaces {
            switch iface.type {
            case .wifi:
                await results.append(buildWiFiInfo(
                    name: iface.name,
                    addrsMap: addrsMap,
                    gatewayMap: gatewayMap,
                    awdlActive: awdlActive,
                    locationGranted: locationGranted
                ))
            case .wiredEthernet:
                results.append(buildEthernetInfo(
                    name: iface.name,
                    addrsMap: addrsMap,
                    gatewayMap: gatewayMap
                ))
            default:
                break
            }
        }

        // WiFi first, then Ethernet; alphabetical within each group
        return results.sorted {
            if $0.kind == .wifi, $1.kind != .wifi { return true }
            if $0.kind != .wifi, $1.kind == .wifi { return false }
            return $0.interfaceName < $1.interfaceName
        }
    }

    /// Requests location permission when not yet determined.
    /// Required for CoreWLAN to expose SSID and BSSID.
    func requestLocationPermissionIfNeeded() async {
        #if os(macOS)
        await MainActor.run {
            let manager = CLLocationManager()
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
        }
        // Brief pause so the authorization dialog has time to appear
        try? await Task.sleep(for: .milliseconds(500))
        #endif
    }

    // MARK: - Private: NWPathMonitor one-shot snapshot

    private func snapshotInterfaces() async -> ([NWInterface], Bool) {
        // NWPathMonitor fires immediately with current path on start; cancel after first result.
        // Using nonisolated(unsafe) for the once-flag since monitor.cancel() prevents re-entry
        // after the first callback and the flag is only mutated inside the serial monitor queue.
        nonisolated(unsafe) var fired = false
        return await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                guard !fired else { return }
                fired = true
                monitor.cancel()
                let filtered = path.availableInterfaces.filter {
                    $0.type == .wifi || $0.type == .wiredEthernet
                }
                let awdl = path.availableInterfaces.contains { $0.name == "awdl0" }
                cont.resume(returning: (filtered, awdl))
            }
            monitor.start(queue: DispatchQueue(label: "DiagnosticsSnapshot-\(UUID().uuidString)"))
        }
    }

    // MARK: - Private: getifaddrs

    private struct AddrEntry {
        var mac: String?
        var ipv4: String?
        var ipv6: String?
        var isUp = false
    }

    private func buildAddressMap() -> [String: AddrEntry] {
        var result: [String: AddrEntry] = [:]

        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return result }
        defer { freeifaddrs(head) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = head
        while let node = ptr {
            defer { ptr = node.pointee.ifa_next }
            let name = String(cString: node.pointee.ifa_name)
            guard let sa = node.pointee.ifa_addr else { continue }

            // Track up+running status
            let flags = Int32(node.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 {
                result[name, default: AddrEntry()].isUp = true
            }

            switch Int32(sa.pointee.sa_family) {
            case AF_LINK:
                // Extract hardware (MAC) address from sockaddr_dl.
                // sdl_data is declared char[12] in the struct definition, but getifaddrs allocates
                // the full sdl_len bytes. Use raw pointer arithmetic to avoid the 12-byte bound.
                // Layout: 8-byte fixed header, then sdl_data[sdl_nlen + sdl_alen + sdl_slen].
                let mac = sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl -> String? in
                    let nlen = Int(dl.pointee.sdl_nlen)
                    let alen = Int(dl.pointee.sdl_alen)
                    guard alen == 6 else { return nil }
                    let macOffset = 8 + nlen // 8-byte header before sdl_data
                    guard macOffset + alen <= Int(dl.pointee.sdl_len) else { return nil }
                    let raw = UnsafeRawPointer(dl)
                    return (0 ..< alen)
                        .map { String(format: "%02x", raw.load(fromByteOffset: macOffset + $0, as: UInt8.self)) }
                        .joined(separator: ":")
                }
                if let mac { result[name, default: AddrEntry()].mac = mac }

            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                result[name, default: AddrEntry()].ipv4 = String(cString: host)

            case AF_INET6:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in6>.size),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                let v6 = String(cString: host)
                // Prefer link-local (fe80::) for display; keep first seen if none recorded
                let existing = result[name]?.ipv6
                if existing == nil || v6.lowercased().hasPrefix("fe80") {
                    result[name, default: AddrEntry()].ipv6 = v6
                }

            default:
                break
            }
        }
        return result
    }

    // MARK: - Private: SCDynamicStore gateway

    private func buildGatewayMap() -> [String: String] {
        var result: [String: String] = [:]
        #if os(macOS)
        guard let store = SCDynamicStoreCreate(nil, "EdgeStudio" as CFString, nil, nil) else {
            return result
        }
        // Enumerate all State:/Network/Interface/<name>/IPv4 keys
        let pattern = "State:/Network/Interface/.*/IPv4" as CFString
        guard let keys = SCDynamicStoreCopyKeyList(store, pattern) as? [String] else {
            return result
        }
        for key in keys {
            // key format: State:/Network/Interface/<name>/IPv4
            let parts = key.components(separatedBy: "/")
            guard parts.count >= 5 else { continue }
            let ifName = parts[4]
            guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let router = dict["Router"] as? String else { continue }
            result[ifName] = router
        }
        #endif
        return result
    }

    // MARK: - Private: ioctl helpers

    /// Reads the MTU for `name` using `SIOCGIFMTU`.
    /// Returns nil on any failure (sandbox restriction, missing entitlement, unknown interface).
    private func readMTU(for name: String) -> Int? {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        // ifreq layout: 16-byte name, then the union at offset 16.
        // SIOCGIFMTU writes the MTU as Int32 at the start of the union (offset 16).
        var buf = [UInt8](repeating: 0, count: 40)
        for (i, c) in name.utf8.prefix(15).enumerated() {
            buf[i] = c
        }

        // SIOCGIFMTU = _IOWR('i', 51, ifreq) = 0xC0206933 on 64-bit macOS
        let SIOCGIFMTU_VALUE: UInt = 0xC020_6933
        let ok = buf.withUnsafeMutableBytes {
            Darwin.ioctl(sock, SIOCGIFMTU_VALUE, $0.baseAddress!) == 0
        }
        guard ok else { return nil }

        let mtu = Int32(buf[16]) | (Int32(buf[17]) << 8) |
            (Int32(buf[18]) << 16) | (Int32(buf[19]) << 24)
        return mtu > 0 ? Int(mtu) : nil
    }

    /// Reads Ethernet link speed and duplex using `SIOCGIFMEDIA`.
    ///
    /// Requires `com.apple.security.iokit-user-client` entitlement.
    /// Returns `(nil, nil)` gracefully on any failure so callers simply omit those rows.
    ///
    /// `ifmediareq` layout (64-bit macOS):
    ///   [0..15]  char ifm_name[IFNAMSIZ]
    ///   [16..19] int  ifm_current
    ///   [20..23] int  ifm_mask
    ///   [24..27] int  ifm_status
    ///   [28..31] int  ifm_active   ← IFM_SUBTYPE | IFM_OPTIONS
    ///   [32..39] int* ifm_ulist    (8-byte pointer on 64-bit)
    ///   [40..43] int  ifm_count
    private func readEthernetLinkInfo(for name: String) -> (speedMbps: Int?, duplexLabel: String?) {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return (nil, nil) }
        defer { Darwin.close(sock) }

        var buf = [UInt8](repeating: 0, count: 48)
        for (i, c) in name.utf8.prefix(15).enumerated() {
            buf[i] = c
        }

        // SIOCGIFMEDIA = _IOWR('i', 56, ifmediareq) ≈ 0xC0306938 on 64-bit macOS
        let SIOCGIFMEDIA_VALUE: UInt = 0xC030_6938
        let ok = buf.withUnsafeMutableBytes {
            Darwin.ioctl(sock, SIOCGIFMEDIA_VALUE, $0.baseAddress!) == 0
        }
        guard ok else { return (nil, nil) }

        let active = UInt32(buf[28]) | (UInt32(buf[29]) << 8) |
            (UInt32(buf[30]) << 16) | (UInt32(buf[31]) << 24)

        // IFM_TMASK = 0x1f — bottom 5 bits encode the media subtype (speed)
        let subtype = Int(active & 0x1F)
        let speedMbps: Int? = switch subtype {
        case 3: 10 // IFM_10_T
        case 6: 100 // IFM_100_TX
        case 15: 1000 // IFM_1000_SX
        case 16: 1000 // IFM_1000_T
        case 22: 10000 // IFM_10G_T
        case 24: 2500 // IFM_2500_T
        case 25: 5000 // IFM_5000_T
        default: nil
        }

        // IFM_FDX = 0x00100000, IFM_HDX = 0x00200000
        let duplexLabel: String? = if (active & 0x0010_0000) != 0 {
            "Full Duplex"
        } else if (active & 0x0020_0000) != 0 {
            "Half Duplex"
        } else {
            nil
        }

        return (speedMbps, duplexLabel)
    }

    // MARK: - Private: location permission

    private func checkLocationPermission() async -> Bool {
        #if os(macOS)
        return await MainActor.run {
            CLLocationManager().authorizationStatus == .authorizedAlways
        }
        #else
        return false
        #endif
    }

    // MARK: - Private: interface builders

    #if os(macOS)
    private func buildWiFiInfo(
        name: String,
        addrsMap: [String: AddrEntry],
        gatewayMap: [String: String],
        awdlActive: Bool,
        locationGranted: Bool
    ) async -> NetworkInterfaceInfo {
        let entry = addrsMap[name]
        let cwInterface = CWWiFiClient.shared().interface(withName: name)

        let ssid: String? = locationGranted ? cwInterface.flatMap { $0.ssid() } : nil
        let bssid: String? = locationGranted ? cwInterface.flatMap { $0.bssid() } : nil
        let rssiRaw = cwInterface?.rssiValue() ?? 0
        let noiseRaw = cwInterface?.noiseMeasurement() ?? 0
        let txRate = cwInterface?.transmitRate() ?? 0
        let channel: CWChannel? = cwInterface.flatMap { $0.wlanChannel() }
        let phyMode: CWPHYMode? = cwInterface?.activePHYMode()
        let security: CWSecurity? = cwInterface?.security()
        let country: String? = cwInterface.flatMap { $0.countryCode() }

        return NetworkInterfaceInfo(
            id: name,
            interfaceName: name,
            kind: .wifi,
            isActive: entry?.isUp ?? false,
            hardwareAddress: entry?.mac,
            ipv4Address: entry?.ipv4,
            ipv6Address: entry?.ipv6,
            gatewayAddress: gatewayMap[name],
            ssid: ssid,
            bssid: bssid,
            rssi: rssiRaw != 0 ? rssiRaw : nil,
            noise: noiseRaw != 0 ? noiseRaw : nil,
            transmitRate: txRate > 0 ? txRate : nil,
            channelNumber: channel.map { Int($0.channelNumber) },
            channelBandLabel: channelBandString(channel?.channelBand),
            channelWidthLabel: channelWidthString(channel?.channelWidth),
            phyModeLabel: phyModeString(phyMode),
            securityLabel: securityString(security),
            countryCode: country,
            awdlActive: awdlActive,
            locationPermissionGranted: locationGranted,
            linkSpeedMbps: nil,
            linkDuplexLabel: nil,
            mtu: nil
        )
    }

    private func buildEthernetInfo(
        name: String,
        addrsMap: [String: AddrEntry],
        gatewayMap: [String: String]
    ) -> NetworkInterfaceInfo {
        let entry = addrsMap[name]
        let (speed, duplex) = readEthernetLinkInfo(for: name)
        let mtu = readMTU(for: name)

        return NetworkInterfaceInfo(
            id: name,
            interfaceName: name,
            kind: .ethernet,
            isActive: entry?.isUp ?? false,
            hardwareAddress: entry?.mac,
            ipv4Address: entry?.ipv4,
            ipv6Address: entry?.ipv6,
            gatewayAddress: gatewayMap[name],
            ssid: nil, bssid: nil, rssi: nil, noise: nil, transmitRate: nil,
            channelNumber: nil, channelBandLabel: nil, channelWidthLabel: nil,
            phyModeLabel: nil, securityLabel: nil, countryCode: nil,
            awdlActive: false,
            locationPermissionGranted: false,
            linkSpeedMbps: speed,
            linkDuplexLabel: duplex,
            mtu: mtu
        )
    }

    // MARK: - CoreWLAN enum helpers

    private func channelBandString(_ band: CWChannelBand?) -> String? {
        guard let band else { return nil }
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return nil
        }
    }

    private func channelWidthString(_ width: CWChannelWidth?) -> String? {
        guard let width else { return nil }
        switch width {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        default: return nil
        }
    }

    private func phyModeString(_ mode: CWPHYMode?) -> String? {
        switch mode {
        case .mode11ax: return "802.11ax"
        case .mode11ac: return "802.11ac"
        case .mode11n: return "802.11n"
        case .mode11g: return "802.11g"
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        default: return nil
        }
    }

    private func securityString(_ security: CWSecurity?) -> String? {
        guard let security else { return nil }
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpaPersonalMixed: return "WPA/WPA2 Personal"
        case .wpa2Personal: return "WPA2 Personal"
        case .wpaEnterprise: return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA/WPA2 Enterprise"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .wpa3Transition: return "WPA2/WPA3"
        default: return nil
        }
    }

    #else
    /// iPadOS stubs — CoreWLAN is macOS-only
    private func buildWiFiInfo(
        name: String, addrsMap: [String: AddrEntry], gatewayMap: [String: String],
        awdlActive: Bool, locationGranted: Bool
    ) async -> NetworkInterfaceInfo {
        let entry = addrsMap[name]
        return NetworkInterfaceInfo(
            id: name, interfaceName: name, kind: .wifi, isActive: entry?.isUp ?? false,
            hardwareAddress: entry?.mac, ipv4Address: entry?.ipv4, ipv6Address: entry?.ipv6,
            gatewayAddress: gatewayMap[name],
            ssid: nil, bssid: nil, rssi: nil, noise: nil, transmitRate: nil,
            channelNumber: nil, channelBandLabel: nil, channelWidthLabel: nil,
            phyModeLabel: nil, securityLabel: nil, countryCode: nil,
            awdlActive: awdlActive, locationPermissionGranted: locationGranted,
            linkSpeedMbps: nil, linkDuplexLabel: nil, mtu: nil
        )
    }

    private func buildEthernetInfo(
        name: String, addrsMap: [String: AddrEntry], gatewayMap: [String: String]
    ) -> NetworkInterfaceInfo {
        let entry = addrsMap[name]
        return NetworkInterfaceInfo(
            id: name, interfaceName: name, kind: .ethernet, isActive: entry?.isUp ?? false,
            hardwareAddress: entry?.mac, ipv4Address: entry?.ipv4, ipv6Address: entry?.ipv6,
            gatewayAddress: gatewayMap[name],
            ssid: nil, bssid: nil, rssi: nil, noise: nil, transmitRate: nil,
            channelNumber: nil, channelBandLabel: nil, channelWidthLabel: nil,
            phyModeLabel: nil, securityLabel: nil, countryCode: nil,
            awdlActive: false, locationPermissionGranted: false,
            linkSpeedMbps: nil, linkDuplexLabel: nil, mtu: nil
        )
    }
    #endif
}
