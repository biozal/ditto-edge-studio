import Foundation

@Observable
class DittoAppConfig: Decodable {
    var _id: String
    var name: String
    var appId: String
    var authToken: String
    var authUrl: String
    var websocketUrl: String
    var httpApiUrl: String
    var httpApiKey: String
    var mode: AuthMode
    var allowUntrustedCerts: Bool
    var secretKey: String

    init(
        _ _id: String,
        name: String,
        appId: String,
        authToken: String,
        authUrl: String,
        websocketUrl: String,
        httpApiUrl: String,
        httpApiKey: String,
        mode: AuthMode = .onlinePlayground,
        allowUntrustedCerts: Bool = false,
        secretKey: String = ""
    ) {

        self._id = _id
        self.name = name
        self.appId = appId
        self.authToken = authToken
        self.authUrl = authUrl
        self.websocketUrl = websocketUrl
        self.httpApiUrl = httpApiUrl
        self.httpApiKey = httpApiKey
        self.mode = mode
        self.allowUntrustedCerts = allowUntrustedCerts
        self.secretKey = secretKey
    }
    enum CodingKeys: String, CodingKey {
        case _id
        case name
        case appId
        case authToken
        case authUrl
        case websocketUrl
        case httpApiUrl
        case httpApiKey
        case mode
        case allowUntrustedCerts
        case secretKey
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        name = try container.decode(String.self, forKey: .name)
        appId = try container.decode(String.self, forKey: .appId)
        authToken = try container.decode(String.self, forKey: .authToken)
        authUrl = try container.decode(String.self, forKey: .authUrl)
        websocketUrl = try container.decode(String.self, forKey: .websocketUrl)
        httpApiUrl = try container.decode(String.self, forKey: .httpApiUrl)
        httpApiKey = try container.decode(String.self, forKey: .httpApiKey)
        mode = try container.decode(AuthMode.self, forKey: .mode)
        allowUntrustedCerts = try container.decodeIfPresent(Bool.self, forKey: .allowUntrustedCerts) ?? false
        secretKey = try container.decodeIfPresent(String.self, forKey: .secretKey) ?? ""
    }
}

extension DittoAppConfig {
    static func new() -> DittoAppConfig {
        return DittoAppConfig(
            UUID().uuidString,
            name: "",
            appId: "",
            authToken: "",
            authUrl: "",
            websocketUrl: "",
            httpApiUrl: "",
            httpApiKey: "",
            mode: .onlinePlayground,
            allowUntrustedCerts: false,
            secretKey: ""
        )
    }
}
