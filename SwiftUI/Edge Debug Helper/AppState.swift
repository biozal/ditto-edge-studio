import Foundation
enum AppError : Error {
    case error(message: String)
}

class AppState: ObservableObject {
    @Published var appConfig: DittoAppConfig
    @Published var error: Error? = nil
    
    init() {
        appConfig = AppState.loadAppConfig()
    }
    
    func setError(_ error: Error?) {
        DispatchQueue.main.async {
            self.error = error
        }
    }
    
    // Read the dittoConfig.plist file and store the appId, endpointUrl, and authToken to use elsewhere.
    static func loadAppConfig() -> DittoAppConfig {
        guard let path = Bundle.main.path(forResource: "dittoConfig", ofType: "plist") else {
            fatalError("Could not load dittoConfig.plist file!")
        }
        
        // Any errors here indicate that the dittoConfig.plist file has not been formatted properly.
        let data = NSData(contentsOfFile: path)! as Data
        let dittoConfigPropertyList = try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let name = dittoConfigPropertyList["name"]! as! String
        let authUrl = dittoConfigPropertyList["authUrl"]! as! String
        let websocketUrl = dittoConfigPropertyList["websocketUrl"]! as! String
        let appId = dittoConfigPropertyList["appId"]! as! String
        let authToken = dittoConfigPropertyList["authToken"]! as! String
        let httpApiUrl = dittoConfigPropertyList["httpApiUrl"]! as! String
        let httpApiKey = dittoConfigPropertyList["httpApiKey"]! as! String

        return DittoAppConfig(
            UUID().uuidString,
            name: name,
            appId: appId,
            authToken: authToken,
            authUrl:  authUrl,
            websocketUrl: websocketUrl,
            httpApiUrl: httpApiUrl,
            httpApiKey: httpApiKey,
            mode: .onlinePlayground,
            allowUntrustedCerts: false
        )
    }
}


