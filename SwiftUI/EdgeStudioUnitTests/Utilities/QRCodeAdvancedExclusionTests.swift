import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Guards the decision that advanced settings are **never** shared by QR code.
///
/// This was specified, documented, stated in the editor UI — and not implemented: the
/// model happily encoded both arrays and the decoder imported them, so scanning a peer's
/// code silently changed what synced on the scanning device, and could set a startup
/// parameter that opens a network listener without any prompt.
@Suite("QRCodeGenerator — advanced settings are excluded")
struct QRCodeAdvancedExclusionTests {
    private func makeConfig() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "Quickstart",
            databaseId: "db-1",
            developmentToken: "token",
            url: "https://example.ditto.live",
            httpApiUrl: "https://api.example.ditto.live",
            httpApiKey: "key",
            collectionSyncScopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
            startupSettings: [
                StartupSetting(
                    parameter: "metrics_exporter_prometheus_http_listener_addr",
                    type: .string,
                    value: "0.0.0.0:9000",
                    isAcknowledged: true
                )
            ]
        )
    }

    /// Round-trips through the real encoder and decoder.
    private func roundTrip(_ config: DittoConfigForDatabase) throws -> DittoConfigForDatabase {
        let payload = try #require(QRCodeGenerator.testPayloadString(config: config, favorites: []))
        let decoded = try #require(QRCodeGenerator.decode(from: payload))
        return decoded.config
    }

    /// Asserts on the PAYLOAD BYTES, not a round trip.
    ///
    /// `decode` sanitizes independently, so a round-trip test launders the result:
    /// removing `sanitizedForSharing()` from `encodePayload` kept every round-trip test
    /// green while the rendered QR image physically carried the user's scopes and a
    /// listener address — readable by anyone who photographs the code.
    @Test(.tags(.utility, .fast))
    func `the encoded payload bytes contain no advanced settings`() throws {
        // ARRANGE
        let config = makeConfig()

        // ACT — inflate the real envelope and inspect the JSON directly.
        let payload = try #require(QRCodeGenerator.testPayloadString(config: config, favorites: []))
        let base64 = String(payload.dropFirst("EDS2:".count))
        let compressed = try #require(Data(base64Encoded: base64))
        let json = try #require(try? (compressed as NSData).decompressed(using: .zlib) as Data)
        let text = try #require(String(data: json, encoding: .utf8))

        // ASSERT — neither the values nor even the keys are present.
        #expect(text.contains("orders") == false, "a sync scope leaked into the QR payload")
        #expect(text.contains("metrics_exporter") == false, "a startup setting leaked into the QR payload")
        #expect(text.contains("LocalPeerOnly") == false)
        // Sanity: the payload really is this config, so the assertions above mean something.
        #expect(text.contains(config.databaseId))
    }

    @Test(.tags(.utility, .fast))
    func `an encoded payload carries no sync scopes or startup settings`() throws {
        // ARRANGE
        let config = makeConfig()

        // ACT
        let decoded = try roundTrip(config)

        // ASSERT
        #expect(decoded.collectionSyncScopes.isEmpty)
        #expect(decoded.startupSettings.isEmpty)
    }

    /// The legacy v1 branch (raw JSON, no `EDS2:` prefix) sanitizes too — it was
    /// unexercised, so removing the call there leaked scopes from older codes.
    @Test(.tags(.utility, .fast))
    func `a legacy v1 payload cannot import advanced settings`() throws {
        // ARRANGE — v1 is the bare config JSON with no prefix.
        let json = """
        {"_id":"1","name":"Legacy","databaseId":"db-legacy","developmentToken":"t",
         "url":"","httpApiUrl":"","httpApiKey":"",
         "collectionSyncScopes":[{"collection":"orders","scope":"AllPeers"}],
         "startupSettings":[{"parameter":"sqlite3_synchronous","type":"integer","value":"0"}]}
        """

        // ACT
        let decoded = try #require(QRCodeGenerator.decode(from: json))

        // ASSERT
        #expect(decoded.config.collectionSyncScopes.isEmpty)
        #expect(decoded.config.startupSettings.isEmpty)
        #expect(decoded.config.databaseId == "db-legacy")
    }

    @Test(.tags(.utility, .fast))
    func `every other field still travels`() throws {
        // ARRANGE
        let config = makeConfig()

        // ACT
        let decoded = try roundTrip(config)

        // ASSERT
        #expect(decoded.databaseId == config.databaseId)
        #expect(decoded.developmentToken == config.developmentToken)
        #expect(decoded.url == config.url)
        #expect(decoded.httpApiUrl == config.httpApiUrl)
        #expect(decoded.httpApiKey == config.httpApiKey)
        #expect(decoded.name == config.name)
    }

    /// Displaying a QR code is a read-only action. Clearing the arrays in place — the
    /// obvious implementation for a reference type — would delete the user's real sync
    /// scopes from the object the list and editor are rendering.
    @Test(.tags(.utility, .fast))
    func `encoding does not mutate the source config`() throws {
        // ARRANGE
        let config = makeConfig()

        // ACT
        _ = try roundTrip(config)

        // ASSERT
        #expect(config.collectionSyncScopes.count == 1)
        #expect(config.startupSettings.count == 1)
    }

    /// Defence in depth: even a payload built elsewhere that *does* carry advanced
    /// settings must not import them.
    @Test(.tags(.utility, .fast))
    func `a payload that carries advanced settings still decodes to empty lists`() throws {
        // ARRANGE — hand-build a payload with the arrays present.
        let json = """
        {"version":2,"favorites":[],"config":{
          "_id":"1","name":"Hostile","databaseId":"db","developmentToken":"t",
          "url":"","httpApiUrl":"","httpApiKey":"",
          "collectionSyncScopes":[{"collection":"orders","scope":"AllPeers"}],
          "startupSettings":[{"parameter":"additional_p2p_trusted_ca_certs","type":"json","value":"[]"}]
        }}
        """
        let payload = try #require(QRCodeGenerator.testPayloadString(rawJSON: json))

        // ACT
        let decoded = try #require(QRCodeGenerator.decode(from: payload))

        // ASSERT
        #expect(decoded.config.collectionSyncScopes.isEmpty)
        #expect(decoded.config.startupSettings.isEmpty)
        #expect(decoded.config.databaseId == "db", "the rest of the config still imports")
    }
}
