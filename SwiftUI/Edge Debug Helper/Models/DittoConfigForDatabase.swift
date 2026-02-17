import Foundation

@Observable
class DittoConfigForDatabase: Decodable {
    var _id: String
    var name: String
    var databaseId: String
    var token: String
    var authUrl: String
    var websocketUrl: String
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

    init(
        _ _id: String,
        name: String,
        databaseId: String,
        token: String,
        authUrl: String,
        websocketUrl: String,
        httpApiUrl: String,
        httpApiKey: String,
        mode: AuthMode = .server,
        allowUntrustedCerts: Bool = false,
        secretKey: String = "",
        isBluetoothLeEnabled: Bool = true,
        isLanEnabled: Bool = true,
        isAwdlEnabled: Bool = true,
        isCloudSyncEnabled: Bool = true
    ) {
        self._id = _id
        self.name = name
        self.databaseId = databaseId
        self.token = token
        self.authUrl = authUrl
        self.websocketUrl = websocketUrl
        self.httpApiUrl = httpApiUrl
        self.httpApiKey = httpApiKey
        self.mode = mode
        self.allowUntrustedCerts = allowUntrustedCerts
        self.secretKey = secretKey
        self.isBluetoothLeEnabled = isBluetoothLeEnabled
        self.isLanEnabled = isLanEnabled
        self.isAwdlEnabled = isAwdlEnabled
        self.isCloudSyncEnabled = isCloudSyncEnabled
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case name
        case databaseId
        case token
        case authUrl
        case websocketUrl
        case httpApiUrl
        case httpApiKey
        case mode
        case allowUntrustedCerts
        case secretKey
        case isBluetoothLeEnabled
        case isLanEnabled
        case isAwdlEnabled
        case isCloudSyncEnabled
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        name = try container.decode(String.self, forKey: .name)
        databaseId = try container.decode(String.self, forKey: .databaseId)
        token = try container.decode(String.self, forKey: .token)
        authUrl = try container.decode(String.self, forKey: .authUrl)
        websocketUrl = try container.decode(String.self, forKey: .websocketUrl)
        httpApiUrl = try container.decode(String.self, forKey: .httpApiUrl)
        httpApiKey = try container.decode(String.self, forKey: .httpApiKey)
        mode = try container.decode(AuthMode.self, forKey: .mode)
        allowUntrustedCerts = try container.decodeIfPresent(Bool.self, forKey: .allowUntrustedCerts) ?? false
        secretKey = try container.decodeIfPresent(String.self, forKey: .secretKey) ?? ""

        // Transport settings with backward compatibility (default to true if missing)
        isBluetoothLeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBluetoothLeEnabled) ?? true
        isLanEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLanEnabled) ?? true
        isAwdlEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAwdlEnabled) ?? true
        isCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudSyncEnabled) ?? true
    }
}

extension DittoConfigForDatabase {
    static func new() -> DittoConfigForDatabase {
        DittoConfigForDatabase(
            UUID().uuidString,
            name: "",
            databaseId: "",
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
}
