import Foundation
@testable import Edge_Debug_Helper

/// Test fixtures for database configurations
/// Provides pre-configured DittoConfigForDatabase instances for testing
struct DatabaseConfigFixtures {
    
    // MARK: - Valid Configurations
    
    /// Create a valid server configuration
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid DittoConfigForDatabase
    static func validServerConfig(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Online DB \(id.prefix(8))",
            databaseId: "db-\(id)",
            token: "test-token-\(id)",
            authUrl: "https://auth.test.ditto.live",
            websocketUrl: "wss://sync.test.ditto.live",
            httpApiUrl: "https://api.test.ditto.live",
            httpApiKey: "api-key-\(id)",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )
    }
    
    /// Create a valid small peers only configuration
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid offline playground config
    static func validSmallPeersConfig(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Offline DB \(id.prefix(8))",
            databaseId: "db-\(id)",
            token: "",
            authUrl: "",
            websocketUrl: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .smallPeersOnly,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: false
        )
    }
    
    /// Create another valid server configuration variant
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid server config variant
    static func validServerConfig2(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Server DB 2 \(id.prefix(8))",
            databaseId: "db-\(id)",
            token: "server-token-\(id)",
            authUrl: "https://auth2.test.ditto.live",
            websocketUrl: "wss://sync2.test.ditto.live",
            httpApiUrl: "https://api2.test.ditto.live",
            httpApiKey: "api-key-2-\(id)",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: false,
            isCloudSyncEnabled: false
        )
    }
    

    
    // MARK: - Configuration Variations
    
    /// Config with all transports disabled
    static func configWithNoTransports(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validSmallPeersConfig(id: id)
        config.isBluetoothLeEnabled = false
        config.isLanEnabled = false
        config.isAwdlEnabled = false
        config.isCloudSyncEnabled = false
        return config
    }
    
    /// Config with only Bluetooth enabled
    static func configWithBluetoothOnly(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validSmallPeersConfig(id: id)
        config.isBluetoothLeEnabled = true
        config.isLanEnabled = false
        config.isAwdlEnabled = false
        config.isCloudSyncEnabled = false
        return config
    }
    
    /// Config with only LAN enabled
    static func configWithLanOnly(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validSmallPeersConfig(id: id)
        config.isBluetoothLeEnabled = false
        config.isLanEnabled = true
        config.isAwdlEnabled = false
        config.isCloudSyncEnabled = false
        return config
    }
    
    /// Config with untrusted certificates allowed
    static func configWithUntrustedCerts(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validServerConfig(id: id)
        config.allowUntrustedCerts = true
        return config
    }
    
    // MARK: - Invalid Configurations (for error testing)
    
    /// Config with empty required fields
    static func invalidConfigEmptyFields() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "", // Empty name
            databaseId: "", // Empty database ID
            token: "",
            authUrl: "",
            websocketUrl: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true
        )
    }
    
    /// Config with invalid secret key (non-empty for server mode)
    static func invalidConfigWithSecretKey() -> DittoConfigForDatabase {
        let config = validServerConfig()
        config.secretKey = "should-be-empty-for-server"
        return config
    }
    
    /// Config with invalid URLs
    static func invalidConfigBadUrls() -> DittoConfigForDatabase {
        let config = validServerConfig()
        config.authUrl = "not-a-valid-url"
        config.websocketUrl = "also-invalid"
        config.httpApiUrl = "still-invalid"
        return config
    }
    
    // MARK: - Batch Fixtures
    
    /// Generate multiple test configurations
    /// - Parameter count: Number of configs to generate
    /// - Returns: Array of unique configs
    static func multipleConfigs(count: Int = 5) -> [DittoConfigForDatabase] {
        (0..<count).map { index in
            switch index % 3 {
            case 0: return validServerConfig()
            case 1: return validSmallPeersConfig()
            default: return validServerConfig2()
            }
        }
    }
    
    /// Generate configs with duplicate names (for testing deduplication)
    static func configsWithDuplicateNames() -> [DittoConfigForDatabase] {
        let name = "Duplicate Name"
        return [
            DittoConfigForDatabase(
                UUID().uuidString,
                name: name,
                databaseId: "db-1",
                token: "token-1",
                authUrl: "https://auth.test.ditto.live",
                websocketUrl: "wss://sync.test.ditto.live",
                httpApiUrl: "https://api.test.ditto.live",
                httpApiKey: "key-1",
                mode: .server,
                allowUntrustedCerts: false,
                secretKey: "",
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: true,
                isCloudSyncEnabled: true
            ),
            DittoConfigForDatabase(
                UUID().uuidString,
                name: name, // Same name
                databaseId: "db-2",
                token: "token-2",
                authUrl: "https://auth.test.ditto.live",
                websocketUrl: "wss://sync.test.ditto.live",
                httpApiUrl: "https://api.test.ditto.live",
                httpApiKey: "key-2",
                mode: .server,
                allowUntrustedCerts: false,
                secretKey: "",
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: true,
                isCloudSyncEnabled: true
            )
        ]
    }
}
