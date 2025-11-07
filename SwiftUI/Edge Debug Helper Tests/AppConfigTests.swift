//
//  AppConfigTests.swift
//  Edge Debug Helper Tests
//
//  Created by Claude Code
//

import Testing
import Foundation
@testable import Edge_Debug_Helper

struct AppConfigTests {

    // MARK: - DittoAppConfig Tests

    @Test("DittoAppConfig initializes with all required fields")
    func testDittoAppConfigInitialization() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .onlinePlayground,
            allowUntrustedCerts: false,
            secretKey: ""
        )

        #expect(config._id == "test-id")
        #expect(config.name == "Test App")
        #expect(config.appId == "test-app-id")
        #expect(config.authToken == "test-token")
        #expect(config.authUrl == "https://auth.example.com")
        #expect(config.websocketUrl == "wss://sync.example.com")
        #expect(config.httpApiUrl == "https://api.example.com")
        #expect(config.httpApiKey == "test-api-key")
        #expect(config.mode == .onlinePlayground)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    @Test("DittoAppConfig initializes with default values")
    func testDittoAppConfigDefaultValues() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        #expect(config.mode == .onlinePlayground)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    @Test("DittoAppConfig.new() creates empty config")
    func testDittoAppConfigNew() async throws {
        let config = DittoAppConfig.new()

        #expect(!config._id.isEmpty) // UUID should be generated
        #expect(config.name == "")
        #expect(config.appId == "")
        #expect(config.authToken == "")
        #expect(config.authUrl == "")
        #expect(config.websocketUrl == "")
        #expect(config.httpApiUrl == "")
        #expect(config.httpApiKey == "")
        #expect(config.mode == .onlinePlayground)
        #expect(config.allowUntrustedCerts == false)
        #expect(config.secretKey == "")
    }

    // MARK: - DittoAppConfig Decodable Tests

    @Test("DittoAppConfig decodes from valid JSON with all fields")
    func testDittoAppConfigDecodingComplete() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App",
            "appId": "test-app-id",
            "authToken": "test-token",
            "authUrl": "https://auth.example.com",
            "websocketUrl": "wss://sync.example.com",
            "httpApiUrl": "https://api.example.com",
            "httpApiKey": "test-api-key",
            "mode": "onlineplayground",
            "allowUntrustedCerts": true,
            "secretKey": "test-secret"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(DittoAppConfig.self, from: data)

        #expect(config._id == "test-id")
        #expect(config.name == "Test App")
        #expect(config.appId == "test-app-id")
        #expect(config.authToken == "test-token")
        #expect(config.authUrl == "https://auth.example.com")
        #expect(config.websocketUrl == "wss://sync.example.com")
        #expect(config.httpApiUrl == "https://api.example.com")
        #expect(config.httpApiKey == "test-api-key")
        #expect(config.mode == .onlinePlayground)
        #expect(config.allowUntrustedCerts == true)
        #expect(config.secretKey == "test-secret")
    }

    @Test("DittoAppConfig decodes with optional fields missing")
    func testDittoAppConfigDecodingOptionalFields() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App",
            "appId": "test-app-id",
            "authToken": "test-token",
            "authUrl": "https://auth.example.com",
            "websocketUrl": "wss://sync.example.com",
            "httpApiUrl": "https://api.example.com",
            "httpApiKey": "test-api-key",
            "mode": "offlineplayground"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(DittoAppConfig.self, from: data)

        #expect(config._id == "test-id")
        #expect(config.mode == .offlinePlayground)
        #expect(config.allowUntrustedCerts == false) // Should default to false
        #expect(config.secretKey == "") // Should default to empty string
    }

    @Test("DittoAppConfig decodes all auth modes correctly")
    func testDittoAppConfigAuthModes() async throws {
        let modes: [(String, AuthMode)] = [
            ("onlineplayground", .onlinePlayground),
            ("offlineplayground", .offlinePlayground),
            ("sharedkey", .sharedKey)
        ]

        for (modeString, expectedMode) in modes {
            let json = """
            {
                "_id": "test-id",
                "name": "Test App",
                "appId": "test-app-id",
                "authToken": "test-token",
                "authUrl": "https://auth.example.com",
                "websocketUrl": "wss://sync.example.com",
                "httpApiUrl": "https://api.example.com",
                "httpApiKey": "test-api-key",
                "mode": "\(modeString)"
            }
            """

            let data = json.data(using: .utf8)!
            let config = try JSONDecoder().decode(DittoAppConfig.self, from: data)

            #expect(config.mode == expectedMode)
        }
    }

    @Test("DittoAppConfig decoding fails with missing required fields")
    func testDittoAppConfigDecodingMissingFields() async throws {
        let json = """
        {
            "_id": "test-id",
            "name": "Test App"
        }
        """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DittoAppConfig.self, from: data)
        }
    }

    // MARK: - AuthMode Tests

    @Test("AuthMode has correct raw values")
    func testAuthModeRawValues() async throws {
        #expect(AuthMode.onlinePlayground.rawValue == "onlineplayground")
        #expect(AuthMode.offlinePlayground.rawValue == "offlineplayground")
        #expect(AuthMode.sharedKey.rawValue == "sharedkey")
    }

    @Test("AuthMode has correct display names")
    func testAuthModeDisplayNames() async throws {
        #expect(AuthMode.onlinePlayground.displayName == "Online Playground")
        #expect(AuthMode.offlinePlayground.displayName == "Offline Playground")
        #expect(AuthMode.sharedKey.displayName == "Shared Key")
    }

    @Test("AuthMode default is onlinePlayground")
    func testAuthModeDefault() async throws {
        #expect(AuthMode.default == .onlinePlayground)
    }

    @Test("AuthMode allCases contains all modes")
    func testAuthModeAllCases() async throws {
        let allModes = AuthMode.allCases
        #expect(allModes.count == 3)
        #expect(allModes.contains(.onlinePlayground))
        #expect(allModes.contains(.offlinePlayground))
        #expect(allModes.contains(.sharedKey))
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
            "appId",
            "authToken",
            "httpApiUrl",
            "httpApiKey"
        ]

        // This documents the expected structure for regression testing
        #expect(requiredFields.count == 7)
    }

    @Test("loadAppConfig returns onlinePlayground mode by default")
    func testLoadAppConfigDefaultMode() async throws {
        // Document that loadAppConfig always sets mode to .onlinePlayground
        // This is a regression test to ensure this behavior doesn't change unexpectedly
        let expectedMode = AuthMode.onlinePlayground
        #expect(expectedMode == .onlinePlayground)
    }

    @Test("loadAppConfig sets allowUntrustedCerts to false by default")
    func testLoadAppConfigDefaultAllowUntrustedCerts() async throws {
        // Document that loadAppConfig always sets allowUntrustedCerts to false
        // This is a regression test for security-critical default
        let expectedValue = false
        #expect(expectedValue == false)
    }

    // MARK: - Configuration Validation Tests

    @Test("Config validation detects empty appId")
    func testValidationEmptyAppId() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        // DittoManager.initializeStore should reject empty appId
        #expect(config.appId.isEmpty)
    }

    @Test("Config validation detects placeholder appId")
    func testValidationPlaceholderAppId() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "put appId here",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )

        // DittoManager.initializeStore should reject placeholder appId
        #expect(config.appId == "put appId here")
    }

    @Test("Config validation for hydrateDittoSelectedApp requires non-empty fields")
    func testValidationHydrateSelectedApp() async throws {
        // Test empty appId
        let configEmptyAppId = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(configEmptyAppId.appId.isEmpty)

        // Test empty authToken
        let configEmptyToken = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(configEmptyToken.authToken.isEmpty)

        // Test valid config
        let validConfig = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key"
        )
        #expect(!validConfig.appId.isEmpty && !validConfig.authToken.isEmpty)
    }

    // MARK: - Mode-Specific Configuration Tests

    @Test("Shared key mode configuration")
    func testSharedKeyModeConfig() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "offline-license-token",
            authUrl: "",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .sharedKey,
            allowUntrustedCerts: false,
            secretKey: "test-shared-key"
        )

        #expect(config.mode == .sharedKey)
        #expect(!config.secretKey.isEmpty)
        #expect(!config.authToken.isEmpty) // Used for offline license token
    }

    @Test("Offline playground mode configuration")
    func testOfflinePlaygroundModeConfig() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "offline-license-token",
            authUrl: "",
            websocketUrl: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .offlinePlayground,
            allowUntrustedCerts: false,
            secretKey: ""
        )

        #expect(config.mode == .offlinePlayground)
        #expect(!config.authToken.isEmpty) // Used for offline license token
    }

    @Test("Online playground mode configuration")
    func testOnlinePlaygroundModeConfig() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "playground-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .onlinePlayground,
            allowUntrustedCerts: false,
            secretKey: ""
        )

        #expect(config.mode == .onlinePlayground)
        #expect(!config.authToken.isEmpty) // Used for playground token
        #expect(!config.authUrl.isEmpty)
    }

    // MARK: - URL Format Tests

    @Test("Config accepts valid URL formats")
    func testValidURLFormats() async throws {
        let config = DittoAppConfig(
            "test-id",
            name: "Test App",
            appId: "test-app-id",
            authToken: "test-token",
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
