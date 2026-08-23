import Foundation
import Testing
@testable import Ditto_Edge_Studio

// MARK: - Sync Scopes

@Suite("SyncScope — DQL wire format")
struct SyncScopeTests {
    /// These raw values go straight into `ALTER SYSTEM SET
    /// USER_COLLECTION_SYNC_SCOPES`. A rename would silently mis-scope every
    /// collection — the SDK would reject or ignore the value — so pin them.
    @Test(.tags(.model, .fast))
    func `raw values match the DQL strings exactly`() {
        #expect(SyncScope.allPeers.rawValue == "AllPeers")
        #expect(SyncScope.bigPeerOnly.rawValue == "BigPeerOnly")
        #expect(SyncScope.smallPeersOnly.rawValue == "SmallPeersOnly") // plural
        #expect(SyncScope.localPeerOnly.rawValue == "LocalPeerOnly")
    }

    @Test(.tags(.model, .fast))
    func `an unknown scope value fails to decode rather than defaulting`() throws {
        // ARRANGE — a scope value this build doesn't know.
        let json = #"[{"collection":"orders","scope":"SomeFutureScope"}]"#

        // ACT / ASSERT — decoding must throw. Coercing to a default could turn a
        // containment setting into "sync everywhere".
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([CollectionSyncScope].self, from: Data(json.utf8))
        }
    }

    @Test(.tags(.model, .fast))
    func `equality survives a decode despite a fresh synthetic identity`() throws {
        // ARRANGE
        let original = [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)]

        // ACT
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([CollectionSyncScope].self, from: data)

        // ASSERT — `id` is a synthetic UUID excluded from `==`, so a decoded row still
        // equals the row it was encoded from (and every row has a distinct identity).
        #expect(decoded == original)
        #expect(decoded[0].syncKey == "orders")
        #expect(decoded[0].id != original[0].id)
    }
}

// MARK: - Startup Setting Coercion

@Suite("StartupSetting — value coercion")
struct StartupSettingCoercionTests {
    private func setting(_ type: StartupSettingType, _ value: String) -> StartupSetting {
        StartupSetting(parameter: "example_parameter", type: type, value: value)
    }

    @Test(.tags(.model, .fast))
    func `integers coerce and reject non-integers`() {
        #expect(setting(.integer, "12").typedValue == .int(12))
        #expect(setting(.integer, "-3").typedValue == .int(-3))
        #expect(setting(.integer, "1.5").typedValue == nil)
        #expect(setting(.integer, "abc").typedValue == nil)
    }

    /// Regression guard: `dql_request_history_log_dump_limit` and
    /// `metrics_exporter_onfile_max_files` both ship as UInt64.max, which `Int(_:)`
    /// cannot parse — without the UInt64 fallback those values are un-enterable.
    @Test(.tags(.model, .fast))
    func `integers above Int64 max fall back to UInt64`() {
        #expect(Int("18446744073709551615") == nil, "premise: Int cannot hold UInt64.max")
        #expect(setting(.integer, "18446744073709551615").typedValue == .uint(18_446_744_073_709_551_615))
    }

    @Test(.tags(.model, .fast))
    func `doubles accept decimals and scientific notation`() {
        #expect(setting(.double, "0.75").typedValue == .double(0.75))
        #expect(setting(.double, "1.0000000000000001e-09").typedValue == .double(1.0000000000000001e-09))
        #expect(setting(.double, "0.59999999999999998").typedValue == .double(0.59999999999999998))
        #expect(setting(.double, "not-a-number").typedValue == nil)
    }

    /// `Bool.init?(String)` is case-sensitive, so the picker's "True" would coerce to
    /// nil and permanently disable Save if it were used directly.
    @Test(.tags(.model, .fast))
    func `booleans accept the pickers capitalised values`() {
        #expect(Bool("True") == nil, "premise: Bool(String) is case-sensitive")
        #expect(setting(.boolean, "True").typedValue == .bool(true))
        #expect(setting(.boolean, "False").typedValue == .bool(false))
        #expect(setting(.boolean, "true").typedValue == .bool(true))
        #expect(setting(.boolean, "yes").typedValue == nil)
    }

    @Test(.tags(.model, .fast))
    func `json accepts objects and arrays and rejects malformed text`() {
        #expect(setting(.json, #"{"a":1}"#).typedValue != nil)
        // Arrays ride in through the JSON type — that's why no array editor is needed.
        #expect(setting(.json, #"["a","b"]"#).typedValue != nil)
        #expect(setting(.json, #"{"a":}"#).typedValue == nil)
        #expect(setting(.json, "").typedValue == nil)
    }

    /// `transports_ble_adapter_mac` ships as "", so an empty string is a real value.
    @Test(.tags(.model, .fast))
    func `an empty string is a valid string value`() {
        #expect(setting(.string, "").typedValue == .string(""))
    }

    @Test(.tags(.model, .fast))
    func `json values reach the SDK as parsed structures, not text`() throws {
        // ACT
        let argument = try #require(setting(.json, #"{"a":1}"#).typedValue).argumentValue

        // ASSERT
        #expect(argument is [String: Any])
    }
}

// MARK: - Validation

@Suite("AdvancedSettingsValidator")
struct AdvancedSettingsValidatorTests {
    @Test(.tags(.model, .fast))
    func `collection names are trimmed before the empty check`() {
        // "   " and "orders " both pass a naive non-empty test but would produce a
        // scope key matching no collection — an inert LocalPeerOnly.
        #expect(AdvancedSettingsValidator.validateCollection("   ", others: []) == .empty)
        #expect(AdvancedSettingsValidator.validateCollection("orders ", others: []) == nil)
        #expect(AdvancedSettingsValidator.validateCollection("orders ", others: ["orders"]) == .duplicate)
    }

    @Test(.tags(.model, .fast))
    func `system collections are rejected in both spellings`() {
        #expect(AdvancedSettingsValidator.validateCollection("__system", others: []) == .systemCollection)
        #expect(AdvancedSettingsValidator.validateCollection("system:peers", others: []) == .systemCollection)
    }

    @Test(.tags(.model, .fast))
    func `collection names needing quoting are rejected`() {
        #expect(AdvancedSettingsValidator.validateCollection("my orders", others: []) == .needsQuoting)
        #expect(AdvancedSettingsValidator.validateCollection("my\"orders", others: []) == .needsQuoting)
    }

    /// The parameter name is interpolated into DQL, so this is the injection guard.
    /// It must match the WHOLE string — a partial match would admit a trailing
    /// statement, and ICU's `$` also matches before a final newline.
    @Test(.tags(.model, .fast))
    func `parameter names are matched whole, blocking injection`() {
        #expect(AdvancedSettingsValidator.isValidParameterName("dql_strict_mode"))
        #expect(AdvancedSettingsValidator.isValidParameterName("_leading_underscore"))
        #expect(AdvancedSettingsValidator.isValidParameterName("1_leading_digit") == false)
        #expect(AdvancedSettingsValidator.isValidParameterName("dql_strict_mode\n") == false)
        #expect(
            AdvancedSettingsValidator
                .isValidParameterName("ok; ALTER SYSTEM SET data_sync_enabled = false --") == false
        )
        #expect(AdvancedSettingsValidator.isValidParameterName("has space") == false)
    }

    @Test(.tags(.model, .fast))
    func `app managed parameters are reserved`() {
        // Two controls writing one parameter would have order-dependent precedence.
        #expect(AdvancedSettingsValidator.isReservedParameter("dql_strict_mode"))
        #expect(AdvancedSettingsValidator.isReservedParameter("DQL_STRICT_MODE"))
        #expect(AdvancedSettingsValidator.isReservedParameter("user_collection_sync_scopes"))
        #expect(AdvancedSettingsValidator.isReservedParameter("mesh_chooser_max_wlan_clients"))
        #expect(AdvancedSettingsValidator.isReservedParameter("transports_ble_server_is_enabled"))
        #expect(AdvancedSettingsValidator.isReservedParameter("udp_server_enabled"))
        #expect(AdvancedSettingsValidator.isReservedParameter("example_parameter") == false)
    }

    @Test(.tags(.model, .fast))
    func `network exposing and durability parameters are flagged sensitive`() {
        #expect(AdvancedSettingsValidator.isSensitiveParameter("metrics_exporter_prometheus_http_listener_addr"))
        #expect(AdvancedSettingsValidator.isSensitiveParameter("additional_p2p_trusted_ca_certs"))
        #expect(AdvancedSettingsValidator.isSensitiveParameter("sqlite3_synchronous"))
        #expect(AdvancedSettingsValidator.isSensitiveParameter("example_parameter") == false)
    }

    @Test(.tags(.model, .fast))
    func `duplicate parameters are detected case insensitively`() {
        // Writes are case-insensitive, so these are one setting, not two.
        let setting = StartupSetting(parameter: "Example_Parameter", type: .integer, value: "1")
        #expect(
            AdvancedSettingsValidator.validateSetting(setting, others: ["example_parameter"]) == .duplicate
        )
    }

    @Test(.tags(.model, .fast))
    func `oversized values are rejected`() {
        let long = String(repeating: "x", count: AdvancedSettingsValidator.maxValueLength + 1)
        let setting = StartupSetting(parameter: "example_string_parameter", type: .string, value: long)
        #expect(AdvancedSettingsValidator.validateSetting(setting, others: []) == .valueTooLong)
    }

    @Test(.tags(.model, .fast))
    func `a valid setting passes`() {
        let setting = StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
        #expect(AdvancedSettingsValidator.validateSetting(setting, others: []) == nil)
    }
}

// MARK: - DQL Construction

@Suite("AdvancedSettingsDQL")
struct AdvancedSettingsDQLTests {
    @Test(.tags(.model, .fast))
    func `scope map emits DQL raw values, not display names`() throws {
        // ARRANGE
        let scopes = [
            CollectionSyncScope(collection: "orders", scope: .smallPeersOnly),
            CollectionSyncScope(collection: "audit", scope: .localPeerOnly)
        ]

        // ACT
        let map = try AdvancedSettingsDQL.scopeMap(from: scopes)

        // ASSERT — "SmallPeersOnly", never "Small Peers Only".
        #expect(map == ["orders": "SmallPeersOnly", "audit": "LocalPeerOnly"])
    }

    @Test(.tags(.model, .fast))
    func `scope map trims names and rejects blanks and system collections`() {
        #expect(throws: AdvancedSettingsDQL.ScopeMapError.invalidCollection("  ")) {
            try AdvancedSettingsDQL.scopeMap(from: [CollectionSyncScope(collection: "  ", scope: .allPeers)])
        }
        #expect(throws: AdvancedSettingsDQL.ScopeMapError.invalidCollection("__system")) {
            try AdvancedSettingsDQL.scopeMap(from: [
                CollectionSyncScope(collection: "__system", scope: .allPeers)
            ])
        }
        let trimmed = try? AdvancedSettingsDQL.scopeMap(from: [
            CollectionSyncScope(collection: " orders ", scope: .allPeers)
        ])
        #expect(trimmed == ["orders": "AllPeers"])
    }

    /// Last-wins would silently pick a scope; for LocalPeerOnly that means data
    /// leaving the device. A duplicate is an error instead.
    @Test(.tags(.model, .fast))
    func `duplicate collections are an error, never silently resolved`() {
        let scopes = [
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
            CollectionSyncScope(collection: "orders", scope: .allPeers)
        ]
        #expect(throws: AdvancedSettingsDQL.ScopeMapError.duplicateCollection("orders")) {
            try AdvancedSettingsDQL.scopeMap(from: scopes)
        }
    }

    @Test(.tags(.model, .fast))
    func `setting statements parameterize the value but not the identifier`() {
        // ARRANGE
        let setting = StartupSetting(parameter: " example_parameter ", type: .integer, value: "42")

        // ACT
        let statement = AdvancedSettingsDQL.settingStatement(for: setting)

        // ASSERT — name trimmed and interpolated (DQL can't parameterize identifiers),
        // value bound.
        #expect(statement == "ALTER SYSTEM SET example_parameter = :value")
    }
}

// MARK: - Config Round-Trip

@Suite("DittoConfigForDatabase — advanced settings")
struct AdvancedConfigCodableTests {
    private func makeConfig(
        scopes: [CollectionSyncScope],
        settings: [StartupSetting]
    ) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "Test",
            databaseId: "db-1",
            developmentToken: "token",
            url: "https://example.ditto.live",
            httpApiUrl: "",
            httpApiKey: "",
            collectionSyncScopes: scopes,
            startupSettings: settings
        )
    }

    @Test(.tags(.model, .fast))
    func `advanced settings survive an encode decode round trip`() throws {
        // ARRANGE
        let config = makeConfig(
            scopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
            settings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "42")]
        )

        // ACT
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

        // ASSERT
        #expect(decoded.collectionSyncScopes == config.collectionSyncScopes)
        #expect(decoded.startupSettings == config.startupSettings)
    }

    @Test(.tags(.model, .fast))
    func `older payloads without the keys decode to empty lists`() throws {
        // ARRANGE — a pre-feature payload.
        let json = """
        {"_id":"1","name":"Legacy","databaseId":"db","developmentToken":"t",
         "url":"","httpApiUrl":"","httpApiKey":""}
        """

        // ACT
        let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: Data(json.utf8))

        // ASSERT
        #expect(decoded.collectionSyncScopes.isEmpty)
        #expect(decoded.startupSettings.isEmpty)
    }

    /// The QR sanitizer must not mutate the object it was handed: that object is the
    /// shared `@Observable` instance the list and editor render, so clearing in place
    /// would delete the user's real scopes just by showing a QR code.
    @Test(.tags(.model, .fast))
    func `sanitizedForSharing strips advanced settings without touching the source`() {
        // ARRANGE
        let config = makeConfig(
            scopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
            settings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "42")]
        )

        // ACT
        let shared = config.sanitizedForSharing()

        // ASSERT
        #expect(shared.collectionSyncScopes.isEmpty)
        #expect(shared.startupSettings.isEmpty)
        #expect(config.collectionSyncScopes.count == 1, "source config must be untouched")
        #expect(config.startupSettings.count == 1, "source config must be untouched")
        // Everything else still travels.
        #expect(shared.databaseId == config.databaseId)
        #expect(shared.developmentToken == config.developmentToken)
        #expect(shared.url == config.url)
    }
}
