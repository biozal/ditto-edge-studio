import Foundation

@Observable
class DittoAppConfig: Decodable {
    let _id: String
    let name: String
    let appId: String
    let authToken: String
    let authUrl: String
    let websocketUrl: String
    let httpApiUrl: String
    let httpApiKey: String

    init (_ _id: String,
          name: String,
          appId: String,
          authToken: String,
          authUrl: String,
          websocketUrl: String,
          httpApiUrl: String,
          httpApiKey: String) {
        
        self._id = _id
        self.name = name
        self.appId = appId
        self.authToken = authToken
        self.authUrl = authUrl
        self.websocketUrl = websocketUrl
        self.httpApiUrl = httpApiUrl
        self.httpApiKey = httpApiKey
    }
    
    init(value: [String: Any?]) {
        self._id = value["_id"] as! String
        self.name = value["name"] as! String
        self.appId = value["appId"] as! String
        self.authToken = value["authToken"] as! String
        self.authUrl = value["authUrl"] as! String
        self.websocketUrl = value["websocketUrl"] as! String
        self.httpApiUrl = value["httpApiUrl"] as! String
        self.httpApiKey = value["httpApiKey"] as! String
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
            httpApiKey: ""
        )
    }
}
