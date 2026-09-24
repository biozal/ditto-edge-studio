import Foundation

/// Settings for the reliable UDP multicast transport (beta, Ditto SDK 5.1.0 —
/// `DittoPeerToPeer.multicastBeta`).
///
/// Persisted per database (four `databaseConfigs` columns, SQLCipher schema v6).
/// Defaults match the SDK defaults, so a config equal to `MulticastConfig()` is a
/// no-op. Default is **disabled** — unlike the other p2p transports, multicast
/// requires all peers on the same L2 segment.
///
/// Field-proven rule (from the Zava Retail demo, verified on-device): port 0 is
/// rejected because the SDK treats it as "pick any port", which silently breaks
/// group rendezvous between peers.
struct MulticastConfig: Equatable, Codable, Sendable {
    var isEnabled = false
    var groupAddress: String = MulticastConfig.defaultGroupAddress
    var port: Int = MulticastConfig.defaultPort
    var interfaceName: String?

    static let defaultGroupAddress = "224.1.2.3"
    static let defaultPort = 6003

    /// IPv4 class-D dotted-quad: four octets 0...255, the first in 224...239.
    ///
    /// Strict parsing on purpose: `Int()` alone accepts `+224`, leading zeros,
    /// and non-ASCII digits, and `split(separator:)` omits empty fields so
    /// `224..1.2.3` would collapse to three parts and could slip through. Each
    /// octet must be plain ASCII digits, no leading zeros beyond "0" itself.
    static func isValidGroupAddress(_ address: String) -> Bool {
        let parts = address
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || !part.hasPrefix("0") else { return nil }
            return Int(part)
        }
        guard octets.count == 4, octets.allSatisfy({ (0 ... 255).contains($0) }) else {
            return false
        }
        return (224 ... 239).contains(octets[0])
    }

    /// Parses `text` as a UDP port; nil unless a whole number in 1...65535.
    static func parsePort(_ text: String) -> Int? {
        guard let port = Int(text.trimmingCharacters(in: .whitespaces)),
              (1 ... 65535).contains(port) else { return nil }
        return port
    }

    /// The port in the SDK's `UInt16` shape. Clamping is unreachable once input has
    /// passed `parsePort`, so this never silently changes a validated value.
    var sdkPort: UInt16 {
        UInt16(clamping: port)
    }
}
