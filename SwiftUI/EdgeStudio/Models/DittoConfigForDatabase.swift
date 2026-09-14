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

    // Reliable UDP multicast transport (beta, Ditto SDK 5.1.0). Default OFF —
    // unlike the other p2p transports it requires all peers on the same L2 segment.
    var isMulticastEnabled: Bool
    var multicastGroupAddress: String
    var multicastPort: Int
    var multicastInterfaceName: String?

    /// Developer Options
    var logLevel: String
    var isStrictModeEnabled: Bool

    /// Advanced Configuration — re-applied on every database open because the SDK
    /// keeps `ALTER SYSTEM` state in memory only.
    var collectionSyncScopes: [CollectionSyncScope]
    var startupSettings: [StartupSetting]

    /// Set by the repository when the stored sync-scope JSON could not be decoded.
    ///
    /// Runtime-only (never persisted, never encoded): the config still loads so it shows
    /// in the list and can be repaired in the editor, but `DittoManager` refuses to open
    /// it — dropping a `LocalPeerOnly` scope silently would start syncing data the user
    /// marked device-local.
    var hasCorruptSyncScopes = false

    /// - Note: `collectionSyncScopes` and `startupSettings` are intentionally
    ///   **not** defaulted. Every caller rebuilds this object from scratch and
    ///   `updateDatabaseConfig` overwrites all columns, so a defaulted parameter
    ///   lets a forgetful call site silently erase a user's sync scopes. Requiring
    ///   both arguments makes the compiler catch that instead.
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
        isMulticastEnabled: Bool = false,
        multicastGroupAddress: String = MulticastConfig.defaultGroupAddress,
        multicastPort: Int = MulticastConfig.defaultPort,
        multicastInterfaceName: String? = nil,
        logLevel: String = "info",
        isStrictModeEnabled: Bool = false,
        collectionSyncScopes: [CollectionSyncScope],
        startupSettings: [StartupSetting]
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
        self.isMulticastEnabled = isMulticastEnabled
        self.multicastGroupAddress = multicastGroupAddress
        self.multicastPort = multicastPort
        self.multicastInterfaceName = multicastInterfaceName
        self.logLevel = logLevel
        self.isStrictModeEnabled = isStrictModeEnabled
        self.collectionSyncScopes = collectionSyncScopes
        self.startupSettings = startupSettings
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
        case isMulticastEnabled
        case multicastGroupAddress
        case multicastPort
        case multicastInterfaceName
        case logLevel
        case isStrictModeEnabled
        case collectionSyncScopes
        case startupSettings
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
        try container.encode(isMulticastEnabled, forKey: .isMulticastEnabled)
        try container.encode(multicastGroupAddress, forKey: .multicastGroupAddress)
        try container.encode(multicastPort, forKey: .multicastPort)
        try container.encode(multicastInterfaceName, forKey: .multicastInterfaceName)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(isStrictModeEnabled, forKey: .isStrictModeEnabled)
        try container.encode(collectionSyncScopes, forKey: .collectionSyncScopes)
        try container.encode(startupSettings, forKey: .startupSettings)
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
        // Multicast defaults to OFF (not true like the other transports): it is a
        // beta transport that requires all peers on the same L2 segment, so an
        // upgrade must never silently enable it. Older payloads (incl. QR codes)
        // simply lack the keys.
        isMulticastEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMulticastEnabled) ?? false
        multicastGroupAddress = try container.decodeIfPresent(
            String.self, forKey: .multicastGroupAddress
        ) ?? MulticastConfig.defaultGroupAddress
        multicastPort = try container.decodeIfPresent(Int.self, forKey: .multicastPort)
            ?? MulticastConfig.defaultPort
        multicastInterfaceName = try container.decodeIfPresent(
            String.self, forKey: .multicastInterfaceName
        )
        // Developer options with backward compatibility
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
        isStrictModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isStrictModeEnabled) ?? false

        // Advanced configuration. Absent is fine (older payloads), but present-and-
        // malformed is NOT tolerated for sync scopes: quietly dropping a
        // `LocalPeerOnly` entry would let that collection sync. `decodeIfPresent`
        // rethrows a malformed array rather than yielding nil, which is what we want.
        collectionSyncScopes = try container
            .decodeIfPresent([CollectionSyncScope].self, forKey: .collectionSyncScopes) ?? []
        startupSettings = try container
            .decodeIfPresent([StartupSetting].self, forKey: .startupSettings) ?? []

        // Multicast validation at the decode boundary, UNCONDITIONALLY (not gated
        // on the enable flag — a disabled config carrying garbage must not
        // resurrect it when the user later toggles multicast on). Port 0 is the
        // SDK's broken "any port" sentinel and UInt16(clamping:) silently
        // truncates out-of-range values, so an invalid group/port can never reach
        // the SDK: reset all three fields to the SDK defaults, and flip an
        // ENABLED config off — an unusable transport must not stay enabled.
        // Mirrors Android's QrCodeDecoder; covers every JSON-decode path (QR v1/v2,
        // plist, exported JSON), not just the QR scanner. (Runs last: @Observable
        // stored properties must all be initialized before `self` is used.)
        if !MulticastConfig.isValidGroupAddress(multicastGroupAddress) || !(1 ... 65535).contains(multicastPort) {
            multicastGroupAddress = MulticastConfig.defaultGroupAddress
            multicastPort = MulticastConfig.defaultPort
            multicastInterfaceName = nil
            if isMulticastEnabled {
                isMulticastEnabled = false
            }
        }
    }

    /// A copy with the advanced settings stripped, for QR sharing.
    ///
    /// Returns a **new instance** on purpose. This is a reference type with no copy
    /// initializer, so clearing the arrays in place would delete the user's real sync
    /// scopes from the shared `@Observable` object the moment they opened the QR
    /// sheet — data loss triggered by a read-only action.
    func sanitizedForSharing() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            _id,
            name: name,
            databaseId: databaseId,
            developmentToken: developmentToken,
            url: url,
            httpApiUrl: httpApiUrl,
            httpApiKey: httpApiKey,
            mode: mode,
            allowUntrustedCerts: allowUntrustedCerts,
            secretKey: secretKey,
            isBluetoothLeEnabled: isBluetoothLeEnabled,
            isLanEnabled: isLanEnabled,
            isAwdlEnabled: isAwdlEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isMulticastEnabled: isMulticastEnabled,
            multicastGroupAddress: multicastGroupAddress,
            multicastPort: multicastPort,
            multicastInterfaceName: multicastInterfaceName,
            logLevel: logLevel,
            isStrictModeEnabled: isStrictModeEnabled,
            collectionSyncScopes: [],
            startupSettings: []
        )
        // Deliberately NOT copied: a shared copy carries no advanced settings, so it has
        // nothing corrupt to flag. Stated explicitly because this initializer is a
        // positional re-construction — any property added to the class and not to
        // `init` is silently dropped here.
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
            isStrictModeEnabled: false,
            collectionSyncScopes: [],
            startupSettings: []
        )
        // Deliberately NOT copied: a shared copy carries no advanced settings, so it has
        // nothing corrupt to flag. Stated explicitly because this initializer is a
        // positional re-construction — any property added to the class and not to
        // `init` is silently dropped here.
    }
}
