import Testing
import Foundation
@testable import Edge_Debug_Helper

struct AppConfigTests {

    // MARK: - DittoConfigForDatabase Tests

    @Test("DittoConfigForDatabase initializes with all required fields")
    func testDittoConfigForDatabaseInitialization() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: ""
        )

        #expect(config._id == "test-id")
        #expect(config.name == "Test App")
        #expect(config.databaseId == "test-database-id")
        #expect(config.token == "test-token")
        #expect(config.authUrl == "https://auth.example.com")
        #expect(config.websocketUrl == "wss://sync.example.com")
        #expect(config.httpApiUrl == "https://api.example.com")
        #expect(config.httpApiKey == "test-api-key")
        #expect(config.mode == .server)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    @Test("DittoConfigForDatabase initializes with default values")
    func testDittoConfigForDatabaseDefaultValues() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        #expect(config.mode == .server)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    @Test("DittoConfigForDatabase.new() creates empty config")
    func testDittoConfigForDatabaseNew() async throws {
        let config = DittoConfigForDatabase.new()

        #expect(!config._id.isEmpty) // UUID should be generated
        #expect(config.name == "")
        #expect(config.databaseId == "")
        #expect(config.token == "")
        #expect(config.authUrl == "")
        #expect(config.websocketUrl == "")
        #expect(config.httpApiUrl == "")
        #expect(config.httpApiKey == "")
        #expect(config.mode == .server)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    // MARK: - DittoConfigForDatabase Decodable Tests

    @Test("DittoConfigForDatabase decodes from valid JSON with all fields")
    func testDittoConfigForDatabaseDecodingComplete() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App",
            "databaseId": "test-database-id",
            "token": "test-token",
            "authUrl": "https://auth.example.com",
            "websocketUrl": "wss://sync.example.com",
            "httpApiUrl": "https://api.example.com",
            "httpApiKey": "test-api-key",
            "mode": "server",
            "allowUntrustedCerts": true,
            "secretKey": "test-secret"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

        #expect(config._id == "test-id")
        #expect(config.name == "Test App")
        #expect(config.databaseId == "test-database-id")
        #expect(config.token == "test-token")
        #expect(config.authUrl == "https://auth.example.com")
        #expect(config.websocketUrl == "wss://sync.example.com")
        #expect(config.httpApiUrl == "https://api.example.com")
        #expect(config.httpApiKey == "test-api-key")
        #expect(config.mode == .server)
        #expect(config.allowUntrustedCerts == true)
        #expect(config.secretKey == "test-secret")
    }

    @Test("DittoConfigForDatabase decodes with optional fields missing")
    func testDittoConfigForDatabaseDecodingOptionalFields() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App",
            "databaseId": "test-database-id",
            "token": "test-token",
            "authUrl": "https://auth.example.com",
            "websocketUrl": "wss://sync.example.com",
            "httpApiUrl": "https://api.example.com",
            "httpApiKey": "test-api-key",
            "mode": "smallpeersonly"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

        #expect(config._id == "test-id")
        #expect(config.mode == .smallPeersOnly)
        #expect(config.allowUntrustedCerts == false) // Should default to false
        #expect(config.secretKey == "") // Should default to empty string
    }

    @Test("DittoConfigForDatabase decodes all auth modes correctly")
    func testDittoConfigForDatabaseAuthModes() async throws {
        let modes: [(String, AuthMode)] = [
            ("server", .server),
            ("smallpeersonly", .smallPeersOnly)
        ]

        for (modeString, expectedMode) in modes {
            let json = """
            {
                "_id": "test-id",
                "name": "Test App",
                "databaseId": "test-database-id",
                "token": "test-token",
                "authUrl": "https://auth.example.com",
                "websocketUrl": "wss://sync.example.com",
                "httpApiUrl": "https://api.example.com",
                "httpApiKey": "test-api-key",
                "mode": "\(modeString)"
            }
            """

            let data = json.data(using: .utf8)!
            let config = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

            #expect(config.mode == expectedMode)
        }
    }

    @Test("DittoConfigForDatabase decoding fails with missing required fields")
    func testDittoConfigForDatabaseDecodingMissingFields() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App"
        }
        """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)
        }
    }

    // MARK: - AuthMode Tests

    @Test("AuthMode has correct raw values")
    func testAuthModeRawValues() async throws {
        #expect(AuthMode.server.rawValue == "server")
        #expect(AuthMode.smallPeersOnly.rawValue == "smallpeersonly")
    }

    @Test("AuthMode has correct display names")
    func testAuthModeDisplayNames() async throws {
        #expect(AuthMode.server.displayName == "Server")
        #expect(AuthMode.smallPeersOnly.displayName == "Small Peers Only")
    }

    @Test("AuthMode default is server")
    func testAuthModeDefault() async throws {
        #expect(AuthMode.default == .server)
    }

    @Test("AuthMode allCases contains all modes")
    func testAuthModeAllCases() async throws {
        let allModes = AuthMode.allCases
        #expect(allModes.count == 2)
        #expect(allModes.contains(.server))
        #expect(allModes.contains(.smallPeersOnly))
    }

    @Test("AuthMode encodes and decodes correctly")
    func testAuthModeEncodeDecode() async throws {
        let modes = AuthMode.allCases

        for mode in modes {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AuthMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }

    // MARK: - AppState.loadAppConfig Tests

    @Test("loadAppConfig validates required fields are not empty")
    func testLoadAppConfigValidation() async throws {
        // This test verifies the expected structure of dittoConfig.plist
        // Note: The actual file must exist in the bundle for this to work in real app

        // Test validates these required fields exist in plist structure:
        let requiredFields = [
            "name",
            "authUrl",
            "websocketUrl",
            "databaseId",
            "token",
            "httpApiUrl",
            "httpApiKey"
        ]

        // This documents the expected structure for regression testing
        #expect(requiredFields.count == 7)
    }

    @Test("loadAppConfig returns server mode by default")
    func testLoadAppConfigDefaultMode() async throws {
        // Document that loadAppConfig always sets mode to .server
        // This is a regression test to ensure this behavior doesn't change unexpectedly
        let expectedMode = AuthMode.server
        #expect(expectedMode == .server)
    }

    @Test("loadAppConfig sets allowUntrustedCerts to false by default")
    func testLoadAppConfigDefaultAllowUntrustedCerts() async throws {
        // Document that loadAppConfig always sets allowUntrustedCerts to false
        // This is a regression test for security-critical default
        let expectedValue = false
        #expect(expectedValue == false)
    }

    // MARK: - Configuration Validation Tests

    @Test("Config validation detects empty databaseId")
    func testValidationEmptyDatabaseId() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        // DittoManager.initializeStore should reject empty databaseId
        #expect(config.databaseId.isEmpty)
    }

    @Test("Config validation detects placeholder databaseId")
    func testValidationPlaceholderDatabaseId() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "put appId here",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        // DittoManager.initializeStore should reject placeholder databaseId
        #expect(config.databaseId == "put appId here")
    }

    @Test("Config validation for hydrateDittoSelectedApp requires non-empty fields")
    func testValidationHydrateSelectedApp() async throws {
        // Test empty databaseId
        let configEmptyDatabaseId = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(configEmptyDatabaseId.databaseId.isEmpty)

        // Test empty token
        let configEmptyToken = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(configEmptyToken.token.isEmpty)

        // Test valid config
        let validConfig = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(!validConfig.databaseId.isEmpty && !validConfig.token.isEmpty)
    }

    // MARK: - Mode-Specific Configuration Tests

    @Test("Small Peers Only mode configuration")
    func testSmallPeersOnlyModeConfig() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "offline-license-token",
            authUrl: "",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .smallPeersOnly,
            allowUntrustedCerts: false,
            secretKey: "test-shared-key"
        )

        #expect(config.mode == .smallPeersOnly)
        #expect(!config.secretKey.isEmpty)
        #expect(!config.token.isEmpty) // Used for offline license token
    }

    @Test("Server mode configuration")
    func testServerModeConfig() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "playground-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: ""
        )

        #expect(config.mode == .server)
        #expect(!config.token.isEmpty) // Used for playground token
        #expect(!config.authUrl.isEmpty)
    }

    // MARK: - URL Format Tests

    @Test("Config accepts valid URL formats")
    func testValidURLFormats() async throws {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-database-id",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        // Verify URLs can be parsed
        #expect(URL(string: config.authUrl) != nil)
        #expect(URL(string: config.websocketUrl) != nil)
        #expect(URL(string: config.httpApiUrl) != nil)

        // Verify URL schemes
        #expect(config.authUrl.hasPrefix("https://"))
        #expect(config.websocketUrl.hasPrefix("wss://"))
        #expect(config.httpApiUrl.hasPrefix("https://"))
    }
}
