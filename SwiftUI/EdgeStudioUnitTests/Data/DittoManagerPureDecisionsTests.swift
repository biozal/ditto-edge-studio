import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers the two *decisions* inside `DittoManager` that do not need a live `Ditto`.
///
/// `hydrateDittoSelectedDatabase` itself is an SDK-boundary sequence and is exempt from
/// the coverage gate (see `docs/TESTING.md`), but that exemption is only honest if the
/// policy it contains is extracted and covered. These are those policies: which
/// peer-to-peer transports to enable, and whether a configuration is openable at all.
///
/// Both are tested at the **feature** level — the rule a user experiences — not at the
/// level of the refactor that made them reachable.
/// Local builder. `DatabaseConfigFixtures` lives in the integration-test target and is
/// not visible here, so this mirrors the convention already used by
/// `DatabaseEditorAdvancedViewModelTests`.
private func makeConfig(
    name: String = "Test DB",
    mode: AuthMode = .development,
    url: String = "https://test.cloud.dittolive.app",
    secretKey: String = "",
    bluetoothLE: Bool = true,
    lan: Bool = true,
    awdl: Bool = true
) -> DittoConfigForDatabase {
    let config = DittoConfigForDatabase(
        UUID().uuidString,
        name: name,
        databaseId: "db-\(UUID().uuidString)",
        developmentToken: "token",
        url: url,
        httpApiUrl: "",
        httpApiKey: "",
        collectionSyncScopes: [],
        startupSettings: []
    )
    config.mode = mode
    config.secretKey = secretKey
    config.isBluetoothLeEnabled = bluetoothLE
    config.isLanEnabled = lan
    config.isAwdlEnabled = awdl
    return config
}

@Suite("DittoManager — transport gating")
struct DittoManagerTransportFlagsTests {
    /// The whole point of the gate: under UI tests no peer-to-peer transport may come up,
    /// regardless of what the stored config says, because BLE/LAN raise OS permission
    /// dialogs that block the harness on a fresh machine.
    @Test(.tags(.service, .fast))
    func `UI testing forces every peer-to-peer transport off regardless of config`() {
        // ARRANGE — a config with everything enabled.
        let config = makeConfig(bluetoothLE: true, lan: true, awdl: true)

        // ACT
        let flags = DittoManager.transportFlags(for: config, isUITesting: true)

        // ASSERT
        #expect(flags.bluetoothLE == false)
        #expect(flags.lan == false)
        #expect(flags.awdl == false)
    }

    /// Outside UI tests the user's choices must pass through untouched — the gate must not
    /// become a silent global "transports off".
    @Test(.tags(.service, .fast))
    func `outside UI testing the stored config passes through unchanged`() {
        // ARRANGE
        let config = makeConfig(bluetoothLE: true, lan: false, awdl: true)

        // ACT
        let flags = DittoManager.transportFlags(for: config, isUITesting: false)

        // ASSERT — each flag is the config's own value, not a blanket answer.
        #expect(flags.bluetoothLE)
        #expect(flags.lan == false)
        #expect(flags.awdl)
    }

    /// A disabled transport stays disabled in production. Guards against a future
    /// "default it on" regression.
    @Test(.tags(.service, .fast))
    func `all transports disabled stays disabled outside UI testing`() {
        // ARRANGE
        let config = makeConfig(bluetoothLE: false, lan: false, awdl: false)

        // ACT
        let flags = DittoManager.transportFlags(for: config, isUITesting: false)

        // ASSERT
        #expect(flags.bluetoothLE == false)
        #expect(flags.lan == false)
        #expect(flags.awdl == false)
    }
}

@Suite("DittoManager — database config construction")
struct DittoManagerCreateDatabaseConfigTests {
    private static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("edgestudio-config-tests")
    }

    /// A bare string with no scheme still yields a non-nil relative URL from
    /// `URL(string:)`, which then fails opaquely inside `Ditto.open()`. The guard exists so
    /// bad config data fails loudly here with a message naming the database.
    @Test(.tags(.service, .fast))
    func `a URL with no scheme is rejected with a message naming the database`() throws {
        // ARRANGE — the classic mistake: pasting a database ID into the URL field.
        let config = makeConfig(url: "8A9B0C1D-2E3F-4A5B-6C7D-8E9F0A1B2C3D")

        // ACT / ASSERT
        let error = #expect(throws: AppError.self) {
            _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
        }
        guard case let .error(message) = try #require(error) else { return }
        #expect(message.contains(config.name), "the error must name the offending database")
        #expect(message.contains(config.url), "the error must quote the rejected value")
    }

    @Test(.tags(.service, .fast))
    func `an empty URL is rejected in development mode`() {
        // ARRANGE
        let config = makeConfig(url: "")

        // ACT / ASSERT
        #expect(throws: AppError.self) {
            _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
        }
    }

    /// A scheme we cannot connect over must not reach `Ditto.open()`.
    @Test(.tags(.service, .fast), arguments: ["ftp://example.com", "https://", "notaurl"])
    func `unsupported or hostless URLs are rejected`(url: String) {
        // ARRANGE
        let config = makeConfig(url: url)

        // ACT / ASSERT
        #expect(throws: AppError.self) {
            _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
        }
    }

    @Test(.tags(.service, .fast), arguments: [
        "https://test.cloud.dittolive.app",
        "http://localhost:8080",
        "wss://test.cloud.dittolive.app",
        "ws://localhost:8080"
    ])
    func `absolute http and websocket URLs are accepted`(url: String) throws {
        // ARRANGE
        let config = makeConfig(url: url)

        // ACT / ASSERT — construction succeeds; no Ditto instance is created.
        _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
    }

    /// Small-peer-only mode never consults `url`, so a config that would be rejected in
    /// development mode must still open offline.
    @Test(.tags(.service, .fast))
    func `small peer only mode ignores the URL entirely`() throws {
        // ARRANGE
        let config = makeConfig(mode: .smallPeerOnly, url: "not-a-url-at-all", secretKey: "")

        // ACT / ASSERT
        _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
    }

    @Test(.tags(.service, .fast))
    func `small peer only mode accepts a shared secret key`() throws {
        // ARRANGE
        let config = makeConfig(mode: .smallPeerOnly, secretKey: "shared-secret")

        // ACT / ASSERT
        _ = try DittoManager.createDatabaseConfig(from: config, withDirectory: Self.directory())
    }

    /// S6: with no database open, `selectedDatabaseStartSync` used to `return` from a
    /// `throws` function — success-shaped, so the caller reported nothing and the user's tap
    /// vanished. Every caller treats "did not throw" as "sync is running"
    /// (`SyncStatusViewModel.toggleSync:157`, `TransportConfigView:300`, the MCP `set_sync`
    /// tool at `MCPToolHandlers.swift:631`).
    ///
    /// Reachable without a live `Ditto`: the guard runs before anything touches the SDK,
    /// which is exactly why this decision is testable while the rest of the path is not.
    @Test(.tags(.service, .fast))
    func `starting sync with no database open throws instead of reporting success`() async throws {
        // ARRANGE — the unit-test target never opens a database; assert that rather than
        // assume it, so a future test that does cannot make this one pass vacuously.
        let hasOpenDatabase = await DittoManager.shared.dittoSelectedApp != nil
        try #require(hasOpenDatabase == false, "precondition: no database may be open")

        // ACT / ASSERT
        await #expect(throws: AppError.self) {
            try await DittoManager.shared.selectedDatabaseStartSync()
        }
    }
}
