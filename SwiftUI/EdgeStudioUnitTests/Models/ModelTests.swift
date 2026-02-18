import Foundation
import Testing
@testable import Edge_Debug_Helper

/// Comprehensive test suite for all model types
///
/// Tests cover:
/// - DittoConfigForDatabase: initialization, factory method, Decodable round-trip
/// - DittoQueryHistory: initialization, Codable encode/decode
/// - DittoSubscription: minimal init, dictionary init, factory method
/// - DittoObservable: minimal init, dictionary init, factory method
/// - AuthMode: enum cases, raw-value round-trip, display names
///
/// All tests are pure in-memory — no SQLCipher or Ditto dependency.
/// Target: 90% code coverage for model types.
@Suite("Model Tests")
struct ModelTests {

    // MARK: - DittoConfigForDatabase Tests

    @Suite("DittoConfigForDatabase")
    struct DittoConfigForDatabaseTests {

        @Test("Default mode is server", .tags(.model, .fast))
        func testDefaultMode() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Test",
                databaseId: "db-1",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: ""
            )

            // ASSERT
            #expect(config.mode == .server)
        }

        @Test("Default transport flags are all enabled", .tags(.model, .fast))
        func testDefaultTransportFlags() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Test",
                databaseId: "db-1",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: ""
            )

            // ASSERT
            #expect(config.isBluetoothLeEnabled)
            #expect(config.isLanEnabled)
            #expect(config.isAwdlEnabled)
            #expect(config.isCloudSyncEnabled)
        }

        @Test("Default allowUntrustedCerts is false", .tags(.model, .fast))
        func testDefaultAllowUntrustedCerts() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Test",
                databaseId: "db-1",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: ""
            )

            // ASSERT
            #expect(config.allowUntrustedCerts == false)
        }

        @Test("All-fields initializer stores every field", .tags(.model, .fast))
        func testAllFieldsInit() {
            // ARRANGE
            let id = UUID().uuidString
            let name = "My Database"
            let dbId = "db-full-fields"

            // ACT
            let config = DittoConfigForDatabase(
                id,
                name: name,
                databaseId: dbId,
                token: "tok",
                authUrl: "https://auth.example.com",
                websocketUrl: "wss://ws.example.com",
                httpApiUrl: "https://api.example.com",
                httpApiKey: "key-123",
                mode: .smallPeersOnly,
                allowUntrustedCerts: true,
                secretKey: "secret",
                isBluetoothLeEnabled: false,
                isLanEnabled: false,
                isAwdlEnabled: false,
                isCloudSyncEnabled: false
            )

            // ASSERT
            #expect(config._id == id)
            #expect(config.name == name)
            #expect(config.databaseId == dbId)
            #expect(config.token == "tok")
            #expect(config.authUrl == "https://auth.example.com")
            #expect(config.websocketUrl == "wss://ws.example.com")
            #expect(config.httpApiUrl == "https://api.example.com")
            #expect(config.httpApiKey == "key-123")
            #expect(config.mode == .smallPeersOnly)
            #expect(config.allowUntrustedCerts == true)
            #expect(config.secretKey == "secret")
            #expect(config.isBluetoothLeEnabled == false)
            #expect(config.isLanEnabled == false)
            #expect(config.isAwdlEnabled == false)
            #expect(config.isCloudSyncEnabled == false)
        }

        @Test("new() factory creates config with unique ID and empty fields", .tags(.model, .fast))
        func testNewFactory() {
            // ACT
            let config1 = DittoConfigForDatabase.new()
            let config2 = DittoConfigForDatabase.new()

            // ASSERT: IDs are unique
            #expect(config1._id != config2._id)
            #expect(!config1._id.isEmpty)

            // ASSERT: fields are empty
            #expect(config1.name == "")
            #expect(config1.databaseId == "")
            #expect(config1.token == "")
            #expect(config1.secretKey == "")
        }

        @Test("new() factory defaults to server mode", .tags(.model, .fast))
        func testNewFactoryDefaultMode() {
            // ACT
            let config = DittoConfigForDatabase.new()

            // ASSERT
            #expect(config.mode == .server)
        }

        @Test("Decodable round-trip preserves all fields", .tags(.model, .fast))
        func testDecodableRoundTrip() throws {
            // ARRANGE
            let json = """
            {
                "_id": "decode-id-1",
                "name": "Decoded DB",
                "databaseId": "db-decoded",
                "token": "my-token",
                "authUrl": "https://auth.example.com",
                "websocketUrl": "wss://ws.example.com",
                "httpApiUrl": "https://api.example.com",
                "httpApiKey": "api-key",
                "mode": "server",
                "allowUntrustedCerts": false,
                "secretKey": "",
                "isBluetoothLeEnabled": true,
                "isLanEnabled": true,
                "isAwdlEnabled": false,
                "isCloudSyncEnabled": true
            }
            """

            // ACT
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT
            #expect(decoded._id == "decode-id-1")
            #expect(decoded.name == "Decoded DB")
            #expect(decoded.databaseId == "db-decoded")
            #expect(decoded.token == "my-token")
            #expect(decoded.mode == .server)
            #expect(decoded.allowUntrustedCerts == false)
            #expect(decoded.isBluetoothLeEnabled == true)
            #expect(decoded.isAwdlEnabled == false)
        }

        @Test("Decodable defaults missing transport fields to true", .tags(.model, .fast))
        func testDecodableDefaultsTransportFieldsToTrue() throws {
            // ARRANGE — JSON without transport fields (backward compat test)
            let json = """
            {
                "_id": "compat-id",
                "name": "Compat DB",
                "databaseId": "db-compat",
                "token": "",
                "authUrl": "",
                "websocketUrl": "",
                "httpApiUrl": "",
                "httpApiKey": "",
                "mode": "server"
            }
            """

            // ACT
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT — all transport flags default to true
            #expect(decoded.isBluetoothLeEnabled == true)
            #expect(decoded.isLanEnabled == true)
            #expect(decoded.isAwdlEnabled == true)
            #expect(decoded.isCloudSyncEnabled == true)
        }

        @Test("Config fields can be mutated", .tags(.model, .fast))
        func testFieldMutation() {
            // ARRANGE
            let config = DittoConfigForDatabase.new()

            // ACT
            config.name = "Updated Name"
            config.mode = .smallPeersOnly
            config.isBluetoothLeEnabled = false

            // ASSERT
            #expect(config.name == "Updated Name")
            #expect(config.mode == .smallPeersOnly)
            #expect(config.isBluetoothLeEnabled == false)
        }
    }

    // MARK: - DittoQueryHistory Tests

    @Suite("DittoQueryHistory")
    struct DittoQueryHistoryTests {

        @Test("Initializer stores all fields", .tags(.model, .fast))
        func testInitializer() {
            // ARRANGE & ACT
            let history = DittoQueryHistory(
                id: "hist-1",
                query: "SELECT * FROM cars",
                createdDate: "2026-01-01T00:00:00Z"
            )

            // ASSERT
            #expect(history.id == "hist-1")
            #expect(history.query == "SELECT * FROM cars")
            #expect(history.createdDate == "2026-01-01T00:00:00Z")
        }

        @Test("Initializer defaults selectedAppId to empty string", .tags(.model, .fast))
        func testDefaultSelectedAppId() {
            // ACT
            let history = DittoQueryHistory(
                id: "hist-2",
                query: "SELECT 1",
                createdDate: "2026-01-01T00:00:00Z"
            )

            // ASSERT
            #expect(history.selectedAppId == "")
        }

        @Test("Codable round-trip preserves fields", .tags(.model, .fast))
        func testCodableRoundTrip() throws {
            // ARRANGE
            let original = DittoQueryHistory(
                id: "hist-codable",
                query: "SELECT * FROM users LIMIT 10",
                createdDate: "2026-02-17T12:00:00Z"
            )

            // ACT
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(DittoQueryHistory.self, from: data)

            // ASSERT
            #expect(decoded.id == original.id)
            #expect(decoded.query == original.query)
            #expect(decoded.createdDate == original.createdDate)
        }

        @Test("Decodable from JSON with coding keys", .tags(.model, .fast))
        func testDecodableFromJson() throws {
            // ARRANGE — uses the actual CodingKeys: _id, selectedApp_id
            let json = """
            {
                "_id": "hist-json-1",
                "query": "SELECT * FROM orders",
                "createdDate": "2026-03-01T00:00:00Z",
                "selectedApp_id": "app-abc"
            }
            """

            // ACT
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(DittoQueryHistory.self, from: data)

            // ASSERT
            #expect(decoded.id == "hist-json-1")
            #expect(decoded.query == "SELECT * FROM orders")
            #expect(decoded.selectedAppId == "app-abc")
        }

        @Test("Two history items with same query have different IDs", .tags(.model, .fast))
        func testDistinctItemsWithSameQuery() {
            // ARRANGE & ACT
            let h1 = DittoQueryHistory(id: "id-1", query: "SELECT 1", createdDate: "2026-01-01T00:00:00Z")
            let h2 = DittoQueryHistory(id: "id-2", query: "SELECT 1", createdDate: "2026-02-01T00:00:00Z")

            // ASSERT
            #expect(h1.id != h2.id)
            #expect(h1.query == h2.query)
        }
    }

    // MARK: - DittoSubscription Tests

    @Suite("DittoSubscription")
    struct DittoSubscriptionTests {

        @Test("Minimal init creates subscription with empty fields", .tags(.model, .fast))
        func testMinimalInit() {
            // ACT
            let sub = DittoSubscription(id: "sub-1")

            // ASSERT
            #expect(sub.id == "sub-1")
            #expect(sub.name == "")
            #expect(sub.query == "")
            #expect(sub.args == nil)
            #expect(sub.syncSubscription == nil)
        }

        @Test("Dictionary init extracts all fields", .tags(.model, .fast))
        func testDictionaryInit() {
            // ARRANGE
            let dict: [String: Any?] = [
                "_id": "sub-dict-1",
                "name": "My Subscription",
                "query": "SELECT * FROM cars",
                "args": "{\"color\": \"red\"}"
            ]

            // ACT
            let sub = DittoSubscription(dict)

            // ASSERT
            #expect(sub.id == "sub-dict-1")
            #expect(sub.name == "My Subscription")
            #expect(sub.query == "SELECT * FROM cars")
            #expect(sub.args == "{\"color\": \"red\"}")
        }

        @Test("Dictionary init generates UUID when id is missing", .tags(.model, .fast))
        func testDictionaryInitMissingId() {
            // ARRANGE — no _id key
            let dict: [String: Any?] = [
                "name": "No ID Sub",
                "query": "SELECT 1"
            ]

            // ACT
            let sub = DittoSubscription(dict)

            // ASSERT — id was generated (non-empty)
            #expect(!sub.id.isEmpty)
        }

        @Test("Dictionary init defaults missing name to Unnamed Subscription", .tags(.model, .fast))
        func testDictionaryInitMissingName() {
            // ARRANGE
            let dict: [String: Any?] = [
                "_id": "sub-no-name",
                "query": "SELECT 2"
            ]

            // ACT
            let sub = DittoSubscription(dict)

            // ASSERT
            #expect(sub.name == "Unnamed Subscription")
        }

        @Test("Dictionary init sets nil args when args key absent", .tags(.model, .fast))
        func testDictionaryInitArgsAbsent() {
            // ARRANGE — no args key
            let dict: [String: Any?] = [
                "_id": "sub-no-args",
                "name": "No Args",
                "query": "SELECT 3"
            ]

            // ACT
            let sub = DittoSubscription(dict)

            // ASSERT
            #expect(sub.args == nil)
        }

        @Test("new() factory creates subscription with unique ID and nil syncSubscription", .tags(.model, .fast))
        func testNewFactory() {
            // ACT
            let sub1 = DittoSubscription.new()
            let sub2 = DittoSubscription.new()

            // ASSERT
            #expect(sub1.id != sub2.id)
            #expect(!sub1.id.isEmpty)
            #expect(sub1.syncSubscription == nil)
        }
    }

    // MARK: - DittoObservable Tests

    @Suite("DittoObservable")
    struct DittoObservableTests {

        @Test("Minimal init creates observable with default values", .tags(.model, .fast))
        func testMinimalInit() {
            // ACT
            let obs = DittoObservable(id: "obs-1")

            // ASSERT
            #expect(obs.id == "obs-1")
            #expect(obs.name == "")
            #expect(obs.query == "")
            #expect(obs.args == nil)
            #expect(obs.isActive == false)
            #expect(obs.lastUpdated == nil)
            #expect(obs.storeObserver == nil)
        }

        @Test("Dictionary init extracts all fields", .tags(.model, .fast))
        func testDictionaryInit() {
            // ARRANGE
            let dict: [String: Any?] = [
                "_id": "obs-dict-1",
                "name": "My Observer",
                "query": "SELECT * FROM items",
                "isActive": true,
                "lastUpdated": "2026-01-01T00:00:00Z",
                "args": "{\"type\": \"premium\"}"
            ]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.id == "obs-dict-1")
            #expect(obs.name == "My Observer")
            #expect(obs.query == "SELECT * FROM items")
            #expect(obs.isActive == true)
            #expect(obs.lastUpdated == "2026-01-01T00:00:00Z")
            #expect(obs.args == "{\"type\": \"premium\"}")
        }

        @Test("Dictionary init generates UUID when id is missing", .tags(.model, .fast))
        func testDictionaryInitMissingId() {
            // ARRANGE
            let dict: [String: Any?] = ["name": "No ID Obs", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(!obs.id.isEmpty)
        }

        @Test("Dictionary init defaults missing name to Unnamed Observable", .tags(.model, .fast))
        func testDictionaryInitMissingName() {
            // ARRANGE
            let dict: [String: Any?] = ["_id": "obs-no-name", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.name == "Unnamed Observable")
        }

        @Test("Dictionary init defaults isActive to false when missing", .tags(.model, .fast))
        func testDictionaryInitIsActiveDefault() {
            // ARRANGE — no isActive key
            let dict: [String: Any?] = ["_id": "obs-active", "name": "A", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.isActive == false)
        }

        @Test("new() factory creates observable with unique ID and nil storeObserver", .tags(.model, .fast))
        func testNewFactory() {
            // ACT
            let obs1 = DittoObservable.new()
            let obs2 = DittoObservable.new()

            // ASSERT
            #expect(obs1.id != obs2.id)
            #expect(!obs1.id.isEmpty)
            #expect(obs1.storeObserver == nil)
        }
    }

    // MARK: - AuthMode Tests

    @Suite("AuthMode")
    struct AuthModeTests {

        @Test("AuthMode has exactly two cases", .tags(.model, .fast))
        func testCasesCount() {
            #expect(AuthMode.allCases.count == 2)
        }

        @Test("server raw value is 'server'", .tags(.model, .fast))
        func testServerRawValue() {
            #expect(AuthMode.server.rawValue == "server")
        }

        @Test("smallPeersOnly raw value is 'smallpeersonly'", .tags(.model, .fast))
        func testSmallPeersOnlyRawValue() {
            #expect(AuthMode.smallPeersOnly.rawValue == "smallpeersonly")
        }

        @Test("Raw value round-trip works for server", .tags(.model, .fast))
        func testRawValueRoundTripServer() {
            let mode = AuthMode(rawValue: "server")
            #expect(mode == .server)
        }

        @Test("Raw value round-trip works for smallPeersOnly", .tags(.model, .fast))
        func testRawValueRoundTripSmallPeers() {
            let mode = AuthMode(rawValue: "smallpeersonly")
            #expect(mode == .smallPeersOnly)
        }

        @Test("Invalid raw value returns nil", .tags(.model, .fast))
        func testInvalidRawValue() {
            let mode = AuthMode(rawValue: "invalid-mode")
            #expect(mode == nil)
        }

        @Test("server displayName is Server", .tags(.model, .fast))
        func testServerDisplayName() {
            #expect(AuthMode.server.displayName == "Server")
        }

        @Test("smallPeersOnly displayName is Small Peers Only", .tags(.model, .fast))
        func testSmallPeersOnlyDisplayName() {
            #expect(AuthMode.smallPeersOnly.displayName == "Small Peers Only")
        }

        @Test("Default mode is server", .tags(.model, .fast))
        func testDefaultMode() {
            #expect(AuthMode.default == .server)
        }

        @Test("Codable encode and decode round-trip", .tags(.model, .fast))
        func testCodableRoundTrip() throws {
            // ARRANGE
            struct Wrapper: Codable {
                let mode: AuthMode
            }
            let wrapper = Wrapper(mode: .smallPeersOnly)

            // ACT
            let data = try JSONEncoder().encode(wrapper)
            let decoded = try JSONDecoder().decode(Wrapper.self, from: data)

            // ASSERT
            #expect(decoded.mode == .smallPeersOnly)
        }
    }
}
