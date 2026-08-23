import Foundation
@testable import Ditto_Edge_Studio

/// Test fixtures for database configurations
/// Provides pre-configured DittoConfigForDatabase instances for testing
enum DatabaseConfigFixtures {
    // MARK: - Valid Configurations

    /// Create a valid development (server-connected) configuration
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid DittoConfigForDatabase
    static func validServerConfig(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Development DB \(id.prefix(8))",
            databaseId: "db-\(id)",
            developmentToken: "test-token-\(id)",
            url: "https://auth.test.ditto.live",
            httpApiUrl: "https://api.test.ditto.live",
            httpApiKey: "api-key-\(id)",
            mode: .development,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true,
            isStrictModeEnabled: false,
            collectionSyncScopes: [],
            startupSettings: []
        )
    }

    /// Create a valid small-peer-only configuration
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid small-peer-only config
    static func validSmallPeersConfig(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Small Peer DB \(id.prefix(8))",
            databaseId: "db-\(id)",
            developmentToken: "",
            url: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .smallPeerOnly,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: false,
            isStrictModeEnabled: false,
            collectionSyncScopes: [],
            startupSettings: []
        )
    }

    /// Create another valid development configuration variant
    /// - Parameter id: Custom ID (default: random UUID)
    /// - Returns: Valid development config variant
    static func validServerConfig2(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            id,
            name: "Test Development DB 2 \(id.prefix(8))",
            databaseId: "db-\(id)",
            developmentToken: "server-token-\(id)",
            url: "https://auth2.test.ditto.live",
            httpApiUrl: "https://api2.test.ditto.live",
            httpApiKey: "api-key-2-\(id)",
            mode: .development,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: false,
            isCloudSyncEnabled: false,
            isStrictModeEnabled: false,
            collectionSyncScopes: [],
            startupSettings: []
        )
    }

    // MARK: - Strict Mode Fixtures

    /// Config with DQL strict mode enabled (SDK 4.x compatibility)
    static func configWithStrictModeEnabled(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validServerConfig(id: id)
        config.isStrictModeEnabled = true
        return config
    }

    /// Config with DQL strict mode explicitly disabled (SDK 5.0 default)
    static func configWithStrictModeDisabled(id: String = UUID().uuidString) -> DittoConfigForDatabase {
        let config = validServerConfig(id: id)
        config.isStrictModeEnabled = false
        return config
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
            developmentToken: "",
            url: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .development,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true,
            isStrictModeEnabled: false,
            collectionSyncScopes: [],
            startupSettings: []
        )
    }

    /// Config with invalid secret key (non-empty for development mode)
    static func invalidConfigWithSecretKey() -> DittoConfigForDatabase {
        let config = validServerConfig()
        config.secretKey = "should-be-empty-for-development"
        return config
    }

    /// Config with invalid URLs
    static func invalidConfigBadUrls() -> DittoConfigForDatabase {
        let config = validServerConfig()
        config.url = "not-a-valid-url"
        config.httpApiUrl = "still-invalid"
        return config
    }

    // MARK: - Batch Fixtures

    /// Generate multiple test configurations
    /// - Parameter count: Number of configs to generate
    /// - Returns: Array of unique configs
    static func multipleConfigs(count: Int = 5) -> [DittoConfigForDatabase] {
        (0 ..< count).map { index in
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
                developmentToken: "token-1",
                url: "https://auth.test.ditto.live",
                httpApiUrl: "https://api.test.ditto.live",
                httpApiKey: "key-1",
                mode: .development,
                allowUntrustedCerts: false,
                secretKey: "",
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: true,
                isCloudSyncEnabled: true,
                isStrictModeEnabled: false,
                collectionSyncScopes: [],
                startupSettings: []
            ),
            DittoConfigForDatabase(
                UUID().uuidString,
                name: name, // Same name
                databaseId: "db-2",
                developmentToken: "token-2",
                url: "https://auth.test.ditto.live",
                httpApiUrl: "https://api.test.ditto.live",
                httpApiKey: "key-2",
                mode: .development,
                allowUntrustedCerts: false,
                secretKey: "",
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: true,
                isCloudSyncEnabled: true,
                isStrictModeEnabled: false,
                collectionSyncScopes: [],
                startupSettings: []
            )
        ]
    }
}
