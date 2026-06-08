import Foundation

/// Database configuration model.
///
/// `@unchecked Sendable` contract: instances are created and any in-place
/// mutation happens on the `@MainActor` (the editor / transport-config view
/// models). Once a config is handed to an actor (`DittoManager`, the
/// repositories), it is treated as a read-only snapshot — those actors only
/// read its properties, never mutate them. The MainActor mutation phase and the
/// actor read phase do not overlap for a given instance, so cross-actor sharing
/// is race-free in practice even though the compiler cannot prove it for an
/// `@Observable` reference type with mutable storage.
///
/// Property names follow the Ditto v5 portal terminology (`databaseId`,
/// `developmentToken`, `url`). For backward compatibility, `init(from:)` also
/// accepts the legacy keys (`appId`, `token`, `authUrl`) so older exported JSON,
/// QR codes, and `dittoConfig.plist` files still decode.
@Observable
final class DittoConfigForDatabase: Codable, @unchecked Sendable {
    var _id: String
    var name: String
    var databaseId: String
    var developmentToken: String
    var url: String
    var httpApiUrl: String
    var httpApiKey: String
    var mode: AuthMode
    var allowUntrustedCerts: Bool
    var secretKey: String

    // Transport Configuration
    var isBluetoothLeEnabled: Bool
    var isLanEnabled: Bool
    var isAwdlEnabled: Bool
    var isCloudSyncEnabled: Bool

    /// Developer Options
    var logLevel: String
    var isStrictModeEnabled: Bool

    init(
        _ _id: String,
        name: String,
        databaseId: String,
        developmentToken: String,
        url: String,
        httpApiUrl: String,
        httpApiKey: String,
        mode: AuthMode = .development,
        allowUntrustedCerts: Bool = false,
        secretKey: String = "",
        isBluetoothLeEnabled: Bool = true,
        isLanEnabled: Bool = true,
        isAwdlEnabled: Bool = true,
        isCloudSyncEnabled: Bool = true,
        logLevel: String = "info",
        isStrictModeEnabled: Bool = false
    ) {
        self._id = _id
        self.name = name
        self.databaseId = databaseId
        self.developmentToken = developmentToken
        self.url = url
        self.httpApiUrl = httpApiUrl
        self.httpApiKey = httpApiKey
        self.mode = mode
        self.allowUntrustedCerts = allowUntrustedCerts
        self.secretKey = secretKey
        self.isBluetoothLeEnabled = isBluetoothLeEnabled
        self.isLanEnabled = isLanEnabled
        self.isAwdlEnabled = isAwdlEnabled
        self.isCloudSyncEnabled = isCloudSyncEnabled
        self.logLevel = logLevel
        self.isStrictModeEnabled = isStrictModeEnabled
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case name
        case databaseId
        case developmentToken
        case url
        case httpApiUrl
        case httpApiKey
        case mode
        case allowUntrustedCerts
        case secretKey
        case isBluetoothLeEnabled
        case isLanEnabled
        case isAwdlEnabled
        case isCloudSyncEnabled
        case logLevel
        case isStrictModeEnabled
    }

    /// Legacy (pre-v5) keys accepted on decode for backward compatibility.
    private enum LegacyCodingKeys: String, CodingKey {
        case appId // → databaseId
        case token // → developmentToken
        case authUrl // → url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(name, forKey: .name)
        try container.encode(databaseId, forKey: .databaseId)
        try container.encode(developmentToken, forKey: .developmentToken)
        try container.encode(url, forKey: .url)
        try container.encode(httpApiUrl, forKey: .httpApiUrl)
        try container.encode(httpApiKey, forKey: .httpApiKey)
        try container.encode(mode, forKey: .mode)
        try container.encode(allowUntrustedCerts, forKey: .allowUntrustedCerts)
        try container.encode(secretKey, forKey: .secretKey)
        try container.encode(isBluetoothLeEnabled, forKey: .isBluetoothLeEnabled)
        try container.encode(isLanEnabled, forKey: .isLanEnabled)
        try container.encode(isAwdlEnabled, forKey: .isAwdlEnabled)
        try container.encode(isCloudSyncEnabled, forKey: .isCloudSyncEnabled)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(isStrictModeEnabled, forKey: .isStrictModeEnabled)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        name = try container.decode(String.self, forKey: .name)

        // v5 keys, falling back to the legacy key name when absent.
        databaseId = try container.decodeIfPresent(String.self, forKey: .databaseId)
            ?? legacy.decodeIfPresent(String.self, forKey: .appId) ?? ""
        developmentToken = try container.decodeIfPresent(String.self, forKey: .developmentToken)
            ?? legacy.decodeIfPresent(String.self, forKey: .token) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
            ?? legacy.decodeIfPresent(String.self, forKey: .authUrl) ?? ""

        httpApiUrl = try container.decode(String.self, forKey: .httpApiUrl)
        httpApiKey = try container.decode(String.self, forKey: .httpApiKey)
        // Tolerate legacy `mode` raw values ("server"/"smallpeersonly") on decode,
        // so older exported JSON / QR codes / dittoConfig.plist still load even when
        // decoded directly (not just via DittoAppConfigLoader's prepare path).
        if let modeString = try container.decodeIfPresent(String.self, forKey: .mode) {
            mode = DittoAppConfigLoader.parseMode(from: modeString) ?? .default
        } else {
            mode = .default
        }
        allowUntrustedCerts = try container.decodeIfPresent(Bool.self, forKey: .allowUntrustedCerts) ?? false
        secretKey = try container.decodeIfPresent(String.self, forKey: .secretKey) ?? ""

        // Transport settings with backward compatibility (default to true if missing)
        isBluetoothLeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBluetoothLeEnabled) ?? true
        isLanEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLanEnabled) ?? true
        isAwdlEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAwdlEnabled) ?? true
        isCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudSyncEnabled) ?? true
        // Developer options with backward compatibility
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
        isStrictModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isStrictModeEnabled) ?? false
    }
}

extension DittoConfigForDatabase {
    static func new() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "",
            databaseId: "",
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
            logLevel: "info",
            isStrictModeEnabled: false
        )
    }
}
