import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Validation rules for the multicast (beta) transport config, mirrored from the
/// Android `MulticastConfigTest` (itself ported from the Zava Retail demo, where
/// they were verified on-device against Ditto SDK 5.1.0).
///
/// The port-0 rejection is load-bearing: the SDK treats 0 as "pick any port",
/// which silently breaks group rendezvous between peers.
@Suite("MulticastConfig")
struct MulticastConfigTests {
    @Test(.tags(.model, .fast))
    func `Defaults match the SDK defaults and stay disabled`() {
        // ARRANGE & ACT
        let config = MulticastConfig()

        // ASSERT
        #expect(config.isEnabled == false)
        #expect(config.groupAddress == "224.1.2.3")
        #expect(config.port == 6003)
        #expect(config.interfaceName == nil)
    }

    @Test(.tags(.model, .fast), arguments: ["224.0.0.1", "224.1.2.3", "239.255.255.255"])
    func `Valid class-D group addresses are accepted`(address: String) {
        #expect(MulticastConfig.isValidGroupAddress(address))
    }

    @Test(
        .tags(.model, .fast),
        arguments: ["223.255.255.255", "240.0.0.1", "192.168.1.1"]
    )
    func `Addresses outside the class-D range are rejected`(address: String) {
        #expect(MulticastConfig.isValidGroupAddress(address) == false)
    }

    @Test(
        .tags(.model, .fast),
        arguments: ["", "1.2.3", "1.2.3.4.5", "a.b.c.d", "256.1.1.1", "224.-1.2.3"]
    )
    func `Malformed group addresses are rejected`(address: String) {
        #expect(MulticastConfig.isValidGroupAddress(address) == false)
    }

    @Test(
        .tags(.model, .fast),
        arguments: [
            "224..1.2.3", // empty octet must not collapse away
            "224.1..3",
            "224.1.2.",
            "224.01.2.3", // leading zeros
            "0224.1.2.3",
            "224.1.2.03",
            "+224.1.2.3", // explicit sign
            "224. 1.2.3", // inner whitespace
            "224.1.2.٣", // non-ASCII digit (Arabic-Indic 3) — Int() accepts it
        ]
    )
    func `Lenient-parse group addresses are rejected by strict octet parsing`(address: String) {
        #expect(MulticastConfig.isValidGroupAddress(address) == false)
    }

    @Test(.tags(.model, .fast), arguments: ["224.0.0.0", "239.0.0.0", "224.10.20.30"])
    func `Boundary class-D group addresses are accepted`(address: String) {
        #expect(MulticastConfig.isValidGroupAddress(address))
    }

    @Test(.tags(.model, .fast))
    func `Group address validation trims surrounding whitespace`() {
        #expect(MulticastConfig.isValidGroupAddress("  224.1.2.3  "))
    }

    @Test(.tags(.model, .fast))
    func `Valid ports parse`() {
        #expect(MulticastConfig.parsePort("6003") == 6003)
        #expect(MulticastConfig.parsePort("1") == 1)
        #expect(MulticastConfig.parsePort("65535") == 65535)
        #expect(MulticastConfig.parsePort(" 6003 ") == 6003)
    }

    @Test(.tags(.model, .fast))
    func `Port 0 is rejected — SDK reads it as any port and rendezvous breaks`() {
        #expect(MulticastConfig.parsePort("0") == nil)
    }

    @Test(.tags(.model, .fast), arguments: ["65536", "-1", "abc", "", "6003.5"])
    func `Out-of-range and non-numeric ports are rejected`(text: String) {
        #expect(MulticastConfig.parsePort(text) == nil)
    }

    @Test(.tags(.model, .fast))
    func `sdkPort converts a validated port unchanged`() {
        // ARRANGE
        var config = MulticastConfig()
        config.port = 6003

        // ASSERT
        #expect(config.sdkPort == 6003)
    }

    // MARK: - MCP multicast_port argument validation (pure half)

    // `configure_transport` receives `arguments["multicast_port"] as? NSNumber` —
    // JSONSerialization bridges JSON booleans to NSNumber too, and
    // `true.stringValue == "1"` would silently become port 1 without an explicit
    // CFBoolean rejection.

    @Test(.tags(.model, .fast))
    func `JSON booleans masquerading as NSNumber ports are detected`() {
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: true)))
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: false)))
        #expect(MCPToolHandlers.isBooleanNSNumber(true as NSNumber))
    }

    @Test(.tags(.model, .fast))
    func `Genuine NSNumber ports are not mistaken for booleans`() {
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: 6003)) == false)
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: 0)) == false)
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: 1)) == false)
        #expect(MCPToolHandlers.isBooleanNSNumber(NSNumber(value: 6003.5)) == false)
    }
}

/// Multicast persistence coding on the database config: the four fields must
/// default to disabled-with-SDK-defaults when older payloads (QR codes, exports)
/// lack the keys, and survive an encode/decode round trip when set.
@Suite("DittoConfigForDatabase multicast coding")
struct DittoConfigForDatabaseMulticastTests {
    private func makeConfig() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "Test",
            databaseId: "db-1",
            developmentToken: "",
            url: "",
            httpApiUrl: "",
            httpApiKey: "",
            collectionSyncScopes: [],
            startupSettings: []
        )
    }

    @Test(.tags(.model, .fast))
    func `Multicast defaults to disabled on new configs`() {
        // ARRANGE & ACT
        let config = makeConfig()

        // ASSERT — unlike the other p2p transports, default OFF.
        #expect(config.isMulticastEnabled == false)
        #expect(config.multicastGroupAddress == MulticastConfig.defaultGroupAddress)
        #expect(config.multicastPort == MulticastConfig.defaultPort)
        #expect(config.multicastInterfaceName == nil)
    }

    @Test(.tags(.model, .fast))
    func `Legacy payloads without multicast keys decode to disabled`() throws {
        // ARRANGE — a payload written before SDK 5.1.0 support exists.
        let legacy = """
            {
              "_id": "abc", "name": "Old", "databaseId": "db-old",
              "developmentToken": "", "url": "", "httpApiUrl": "", "httpApiKey": "",
              "mode": "development", "allowUntrustedCerts": false, "secretKey": "",
              "isBluetoothLeEnabled": true, "isLanEnabled": true,
              "isAwdlEnabled": true, "isCloudSyncEnabled": true,
              "logLevel": "info", "isStrictModeEnabled": false
            }
            """

        // ACT
        let config = try JSONDecoder().decode(
            DittoConfigForDatabase.self,
            from: Data(legacy.utf8)
        )

        // ASSERT
        #expect(config.isMulticastEnabled == false)
        #expect(config.multicastGroupAddress == "224.1.2.3")
        #expect(config.multicastPort == 6003)
        #expect(config.multicastInterfaceName == nil)
    }

    @Test(.tags(.model, .fast))
    func `Multicast fields survive an encode-decode round trip`() throws {
        // ARRANGE
        let config = makeConfig()
        config.isMulticastEnabled = true
        config.multicastGroupAddress = "239.1.2.3"
        config.multicastPort = 7000
        config.multicastInterfaceName = "en0"

        // ACT
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

        // ASSERT
        #expect(decoded.isMulticastEnabled)
        #expect(decoded.multicastGroupAddress == "239.1.2.3")
        #expect(decoded.multicastPort == 7000)
        #expect(decoded.multicastInterfaceName == "en0")
    }

    @Test(.tags(.model, .fast))
    func `sanitizedForSharing preserves the multicast settings`() {
        // ARRANGE
        let config = makeConfig()
        config.isMulticastEnabled = true
        config.multicastPort = 7000

        // ACT
        let shared = config.sanitizedForSharing()

        // ASSERT — the QR/shared copy keeps transport settings (only the advanced
        // configuration is stripped).
        #expect(shared.isMulticastEnabled)
        #expect(shared.multicastPort == 7000)
    }

    // MARK: Decode-boundary multicast validation
    //
    // `init(from:)` rejects an unusable multicast config from ANY JSON-decode
    // path (QR v1/v2, plist, exported JSON): port 0 is the SDK's broken
    // "any port" sentinel and UInt16(clamping:) silently truncates 70000, so an
    // invalid group/port resets to the SDK defaults — and flips an enabled
    // config off. Mirrors Android's QrCodeDecoder.

    private func decodeConfig(fromMulticastJSON multicast: String) throws -> DittoConfigForDatabase {
        let json = """
            {
              "_id": "abc", "name": "QR", "databaseId": "db-1",
              "developmentToken": "", "url": "", "httpApiUrl": "", "httpApiKey": "",
              \(multicast)
            }
            """
        return try JSONDecoder().decode(DittoConfigForDatabase.self, from: Data(json.utf8))
    }

    @Test(.tags(.model, .fast), arguments: [0, 70000])
    func `Decode with an out-of-range port disables multicast and resets to defaults`(port: Int) throws {
        // ACT — enabled config carrying an unusable port.
        let config = try decodeConfig(fromMulticastJSON: """
            "isMulticastEnabled": true, "multicastGroupAddress": "239.1.2.3",
            "multicastPort": \(port), "multicastInterfaceName": "en0"
            """)

        // ASSERT — off + SDK defaults (interface reset too).
        #expect(config.isMulticastEnabled == false)
        #expect(config.multicastGroupAddress == MulticastConfig.defaultGroupAddress)
        #expect(config.multicastPort == MulticastConfig.defaultPort)
        #expect(config.multicastInterfaceName == nil)
    }

    @Test(.tags(.model, .fast))
    func `Decode with an invalid group address disables multicast and resets to defaults`() throws {
        // ACT
        let config = try decodeConfig(fromMulticastJSON: """
            "isMulticastEnabled": true, "multicastGroupAddress": "300.1.2.3",
            "multicastPort": 7000, "multicastInterfaceName": "en0"
            """)

        // ASSERT
        #expect(config.isMulticastEnabled == false)
        #expect(config.multicastGroupAddress == MulticastConfig.defaultGroupAddress)
        #expect(config.multicastPort == MulticastConfig.defaultPort)
        #expect(config.multicastInterfaceName == nil)
    }

    @Test(.tags(.model, .fast))
    func `Decode sanitizes garbage multicast fields even when disabled`() throws {
        // ACT — disabled config carrying garbage: the garbage must not survive
        // to resurrect when the user later toggles multicast on.
        let config = try decodeConfig(fromMulticastJSON: """
            "isMulticastEnabled": false, "multicastGroupAddress": "not-an-ip",
            "multicastPort": 0, "multicastInterfaceName": "en0"
            """)

        // ASSERT — stays disabled, fields reset.
        #expect(config.isMulticastEnabled == false)
        #expect(config.multicastGroupAddress == MulticastConfig.defaultGroupAddress)
        #expect(config.multicastPort == MulticastConfig.defaultPort)
        #expect(config.multicastInterfaceName == nil)
    }

    @Test(.tags(.model, .fast))
    func `Decode preserves a valid enabled multicast config`() throws {
        // ACT
        let config = try decodeConfig(fromMulticastJSON: """
            "isMulticastEnabled": true, "multicastGroupAddress": "239.1.2.3",
            "multicastPort": 7000, "multicastInterfaceName": "en0"
            """)

        // ASSERT — untouched.
        #expect(config.isMulticastEnabled)
        #expect(config.multicastGroupAddress == "239.1.2.3")
        #expect(config.multicastPort == 7000)
        #expect(config.multicastInterfaceName == "en0")
    }
}
