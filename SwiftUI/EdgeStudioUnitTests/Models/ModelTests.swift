import Foundation
import Testing
@testable import Ditto_Edge_Studio

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
        @Test(.tags(.model, .fast))
        func `Default mode is development`() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
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

            // ASSERT
            #expect(config.mode == .development)
        }

        @Test(.tags(.model, .fast))
        func `Default transport flags are all enabled`() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
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

            // ASSERT
            #expect(config.isBluetoothLeEnabled)
            #expect(config.isLanEnabled)
            #expect(config.isAwdlEnabled)
            #expect(config.isCloudSyncEnabled)
        }

        @Test(.tags(.model, .fast))
        func `Default allowUntrustedCerts is false`() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
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

            // ASSERT
            #expect(config.allowUntrustedCerts == false)
        }

        @Test(.tags(.model, .fast))
        func `All-fields initializer stores every field`() {
            // ARRANGE
            let id = UUID().uuidString
            let name = "My Database"
            let dbId = "db-full-fields"

            // ACT
            let config = DittoConfigForDatabase(
                id,
                name: name,
                databaseId: dbId,
                developmentToken: "tok",
                url: "https://auth.example.com",
                httpApiUrl: "https://api.example.com",
                httpApiKey: "key-123",
                mode: .smallPeerOnly,
                allowUntrustedCerts: true,
                secretKey: "secret",
                isBluetoothLeEnabled: false,
                isLanEnabled: false,
                isAwdlEnabled: false,
                isCloudSyncEnabled: false,
                isStrictModeEnabled: false,
                collectionSyncScopes: [],
                startupSettings: []
            )

            // ASSERT
            #expect(config._id == id)
            #expect(config.name == name)
            #expect(config.databaseId == dbId)
            #expect(config.developmentToken == "tok")
            #expect(config.url == "https://auth.example.com")
            #expect(config.httpApiUrl == "https://api.example.com")
            #expect(config.httpApiKey == "key-123")
            #expect(config.mode == .smallPeerOnly)
            #expect(config.allowUntrustedCerts == true)
            #expect(config.secretKey == "secret")
            #expect(config.isBluetoothLeEnabled == false)
            #expect(config.isLanEnabled == false)
            #expect(config.isAwdlEnabled == false)
            #expect(config.isCloudSyncEnabled == false)
            #expect(config.isStrictModeEnabled == false)
        }

        @Test(.tags(.model, .fast))
        func `Default isStrictModeEnabled is false`() {
            // ARRANGE & ACT
            let config = DittoConfigForDatabase(
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

            // ASSERT
            #expect(config.isStrictModeEnabled == false)
        }

        @Test(.tags(.model, .fast))
        func `All-fields init preserves isStrictModeEnabled true`() {
            // ACT
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Strict DB",
                databaseId: "db-strict",
                developmentToken: "",
                url: "",
                httpApiUrl: "",
                httpApiKey: "",
                isStrictModeEnabled: true,
                collectionSyncScopes: [],
                startupSettings: []
            )

            // ASSERT
            #expect(config.isStrictModeEnabled == true)
        }

        @Test(.tags(.model, .fast))
        func `Decodable defaults missing isStrictModeEnabled to false`() throws {
            // ARRANGE — JSON without isStrictModeEnabled (backward compat)
            let json = """
            {
                "_id": "compat-strict-id",
                "name": "Compat DB",
                "databaseId": "db-compat-strict",
                "token": "",
                "authUrl": "",
                "httpApiUrl": "",
                "httpApiKey": "",
                "mode": "development"
            }
            """

            // ACT
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT — missing field defaults to false
            #expect(decoded.isStrictModeEnabled == false)
        }

        @Test(.tags(.model, .fast))
        func `Decodable round-trip preserves isStrictModeEnabled true`() throws {
            // ARRANGE
            let json = """
            {
                "_id": "strict-id",
                "name": "Strict DB",
                "databaseId": "db-strict",
                "token": "",
                "authUrl": "",
                "httpApiUrl": "",
                "httpApiKey": "",
                "mode": "development",
                "isStrictModeEnabled": true
            }
            """

            // ACT
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT
            #expect(decoded.isStrictModeEnabled == true)
        }

        @Test(.tags(.model, .fast))
        func `new() factory defaults isStrictModeEnabled to false`() {
            // ACT
            let config = DittoConfigForDatabase.new()

            // ASSERT
            #expect(config.isStrictModeEnabled == false)
        }

        @Test(.tags(.model, .fast))
        func `new() factory creates config with unique ID and empty fields`() {
            // ACT
            let config1 = DittoConfigForDatabase.new()
            let config2 = DittoConfigForDatabase.new()

            // ASSERT: IDs are unique
            #expect(config1._id != config2._id)
            #expect(!config1._id.isEmpty)

            // ASSERT: fields are empty
            #expect(config1.name == "")
            #expect(config1.databaseId == "")
            #expect(config1.developmentToken == "")
            #expect(config1.secretKey == "")
        }

        @Test(.tags(.model, .fast))
        func `new() factory defaults to development mode`() {
            // ACT
            let config = DittoConfigForDatabase.new()

            // ASSERT
            #expect(config.mode == .development)
        }

        @Test(.tags(.model, .fast))
        func `Decodable round-trip preserves all fields`() throws {
            // ARRANGE
            let json = """
            {
                "_id": "decode-id-1",
                "name": "Decoded DB",
                "databaseId": "db-decoded",
                "token": "my-token",
                "authUrl": "https://auth.example.com",
                "httpApiUrl": "https://api.example.com",
                "httpApiKey": "api-key",
                "mode": "development",
                "allowUntrustedCerts": false,
                "secretKey": "",
                "isBluetoothLeEnabled": true,
                "isLanEnabled": true,
                "isAwdlEnabled": false,
                "isCloudSyncEnabled": true
            }
            """

            // ACT
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT
            #expect(decoded._id == "decode-id-1")
            #expect(decoded.name == "Decoded DB")
            #expect(decoded.databaseId == "db-decoded")
            #expect(decoded.developmentToken == "my-token")
            #expect(decoded.mode == .development)
            #expect(decoded.allowUntrustedCerts == false)
            #expect(decoded.isBluetoothLeEnabled == true)
            #expect(decoded.isAwdlEnabled == false)
        }

        @Test(.tags(.model, .fast))
        func `Decodable defaults missing transport fields to true`() throws {
            // ARRANGE — JSON without transport fields (backward compat test)
            let json = """
            {
                "_id": "compat-id",
                "name": "Compat DB",
                "databaseId": "db-compat",
                "token": "",
                "authUrl": "",
                "httpApiUrl": "",
                "httpApiKey": "",
                "mode": "development"
            }
            """

            // ACT
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            // ASSERT — all transport flags default to true
            #expect(decoded.isBluetoothLeEnabled == true)
            #expect(decoded.isLanEnabled == true)
            #expect(decoded.isAwdlEnabled == true)
            #expect(decoded.isCloudSyncEnabled == true)
        }

        @Test(.tags(.model, .fast))
        func `Config fields can be mutated`() {
            // ARRANGE
            let config = DittoConfigForDatabase.new()

            // ACT
            config.name = "Updated Name"
            config.mode = .smallPeerOnly
            config.isBluetoothLeEnabled = false

            // ASSERT
            #expect(config.name == "Updated Name")
            #expect(config.mode == .smallPeerOnly)
            #expect(config.isBluetoothLeEnabled == false)
        }
    }

    // MARK: - DittoQueryHistory Tests

    @Suite("DittoQueryHistory")
    struct DittoQueryHistoryTests {
        @Test(.tags(.model, .fast))
        func `Initializer stores all fields`() {
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

        @Test(.tags(.model, .fast))
        func `Initializer defaults selectedAppId to empty string`() {
            // ACT
            let history = DittoQueryHistory(
                id: "hist-2",
                query: "SELECT 1",
                createdDate: "2026-01-01T00:00:00Z"
            )

            // ASSERT
            #expect(history.selectedAppId == "")
        }

        @Test(.tags(.model, .fast))
        func `Codable round-trip preserves fields`() throws {
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

        @Test(.tags(.model, .fast))
        func `Decodable from JSON with coding keys`() throws {
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
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(DittoQueryHistory.self, from: data)

            // ASSERT
            #expect(decoded.id == "hist-json-1")
            #expect(decoded.query == "SELECT * FROM orders")
            #expect(decoded.selectedAppId == "app-abc")
        }

        @Test(.tags(.model, .fast))
        func `Two history items with same query have different IDs`() {
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
        @Test(.tags(.model, .fast))
        func `Minimal init creates subscription with empty fields`() {
            // ACT
            let sub = DittoSubscription(id: "sub-1")

            // ASSERT
            #expect(sub.id == "sub-1")
            #expect(sub.name == "")
            #expect(sub.query == "")
            #expect(sub.syncSubscription == nil)
        }

        @Test(.tags(.model, .fast))
        func `Dictionary init extracts all fields`() {
            // ARRANGE
            let dict: [String: Any?] = [
                "_id": "sub-dict-1",
                "name": "My Subscription",
                "query": "SELECT * FROM cars"
            ]

            // ACT
            let sub = DittoSubscription(dict)

            // ASSERT
            #expect(sub.id == "sub-dict-1")
            #expect(sub.name == "My Subscription")
            #expect(sub.query == "SELECT * FROM cars")
        }

        @Test(.tags(.model, .fast))
        func `Dictionary init generates UUID when id is missing`() {
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

        @Test(.tags(.model, .fast))
        func `Dictionary init defaults missing name to Unnamed Subscription`() {
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

        @Test(.tags(.model, .fast))
        func `new() factory creates subscription with unique ID and nil syncSubscription`() {
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
        @Test(.tags(.model, .fast))
        func `Minimal init creates observable with default values`() {
            // ACT
            let obs = DittoObservable(id: "obs-1")

            // ASSERT
            #expect(obs.id == "obs-1")
            #expect(obs.name == "")
            #expect(obs.query == "")
            #expect(obs.isActive == false)
            #expect(obs.lastUpdated == nil)
            #expect(obs.storeObserver == nil)
        }

        @Test(.tags(.model, .fast))
        func `dictionary init`() {
            // ARRANGE
            let dict: [String: Any?] = [
                "_id": "obs-dict-1",
                "name": "My Observer",
                "query": "SELECT * FROM items",
                "isActive": true,
                "lastUpdated": "2026-01-01T00:00:00Z"
            ]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.id == "obs-dict-1")
            #expect(obs.name == "My Observer")
            #expect(obs.query == "SELECT * FROM items")
            #expect(obs.isActive == true)
            #expect(obs.lastUpdated == "2026-01-01T00:00:00Z")
        }

        @Test(.tags(.model, .fast))
        func `dictionary init missing id`() {
            // ARRANGE
            let dict: [String: Any?] = ["name": "No ID Obs", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(!obs.id.isEmpty)
        }

        @Test(.tags(.model, .fast))
        func `Dictionary init defaults missing name to Unnamed Observable`() {
            // ARRANGE
            let dict: [String: Any?] = ["_id": "obs-no-name", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.name == "Unnamed Observable")
        }

        @Test(.tags(.model, .fast))
        func `Dictionary init defaults isActive to false when missing`() {
            // ARRANGE — no isActive key
            let dict: [String: Any?] = ["_id": "obs-active", "name": "A", "query": "SELECT 1"]

            // ACT
            let obs = DittoObservable(dict)

            // ASSERT
            #expect(obs.isActive == false)
        }

        @Test(.tags(.model, .fast))
        func `new() factory creates observable with unique ID and nil storeObserver`() {
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
        @Test(.tags(.model, .fast))
        func `AuthMode has exactly two cases`() {
            #expect(AuthMode.allCases.count == 2)
        }

        @Test(.tags(.model, .fast))
        func `development raw value is 'development'`() {
            #expect(AuthMode.development.rawValue == "development")
        }

        @Test(.tags(.model, .fast))
        func `smallPeerOnly raw value is 'smallPeerOnly'`() {
            #expect(AuthMode.smallPeerOnly.rawValue == "smallPeerOnly")
        }

        @Test(.tags(.model, .fast))
        func `Raw value round-trip works for development`() {
            let mode = AuthMode(rawValue: "development")
            #expect(mode == .development)
        }

        @Test(.tags(.model, .fast))
        func `Raw value round-trip works for smallPeerOnly`() {
            let mode = AuthMode(rawValue: "smallPeerOnly")
            #expect(mode == .smallPeerOnly)
        }

        @Test(.tags(.model, .fast))
        func `Invalid raw value returns nil`() {
            let mode = AuthMode(rawValue: "invalid-mode")
            #expect(mode == nil)
        }

        @Test(.tags(.model, .fast))
        func `development displayName is Development`() {
            #expect(AuthMode.development.displayName == "Development")
        }

        @Test(.tags(.model, .fast))
        func `smallPeerOnly displayName is Small Peer Only`() {
            #expect(AuthMode.smallPeerOnly.displayName == "Small Peer Only")
        }

        @Test(.tags(.model, .fast))
        func `default mode`() {
            #expect(AuthMode.default == .development)
        }

        @Test(.tags(.model, .fast))
        func `Codable encode and decode round-trip`() throws {
            // ARRANGE
            struct Wrapper: Codable {
                let mode: AuthMode
            }
            let wrapper = Wrapper(mode: .smallPeerOnly)

            // ACT
            let data = try JSONEncoder().encode(wrapper)
            let decoded = try JSONDecoder().decode(Wrapper.self, from: data)

            // ASSERT
            #expect(decoded.mode == .smallPeerOnly)
        }
    }
}
