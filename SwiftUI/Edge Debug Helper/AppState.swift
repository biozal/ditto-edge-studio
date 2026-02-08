import Foundation
enum AppError : Error {
    case error(message: String)
}

class AppState: ObservableObject {
    @Published var appConfig: DittoAppConfig
    @Published var error: Error? = nil

    init() {
        appConfig = AppState.loadAppConfig()

        // Load test databases if running UI tests
        if ProcessInfo.processInfo.arguments.contains("UI-TESTING") {
            print("🧪 UI Testing mode detected - loading test databases")
            Task {
                await AppState.loadTestDatabases()
            }
        }
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

    /// Loads test database configurations from testDatabaseConfig.plist for UI testing
    static func loadTestDatabases() async {
        guard let path = Bundle.main.path(forResource: "testDatabaseConfig", ofType: "plist") else {
            print("⚠️ testDatabaseConfig.plist not found - UI tests will have no databases")
            print("   Create this file by copying testDatabaseConfig.plist.example")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

            guard let databasesArray = plist["databases"] as? [[String: Any]] else {
                print("⚠️ testDatabaseConfig.plist missing 'databases' array")
                return
            }

            print("📦 Loading \(databasesArray.count) test database(s)...")

            for (index, dbDict) in databasesArray.enumerated() {
                // Required fields for all modes
                guard let name = dbDict["name"] as? String,
                      let appId = dbDict["appId"] as? String else {
                    print("⚠️ Skipping database \(index + 1) - missing name or appId")
                    continue
                }

                // Parse mode (default to onlinePlayground if not specified)
                let modeString = (dbDict["mode"] as? String) ?? "onlineplayground"
                guard let mode = AuthMode(rawValue: modeString) else {
                    print("⚠️ Skipping database '\(name)' - invalid mode: \(modeString)")
                    print("   Valid modes: onlineplayground, offlineplayground, sharedkey")
                    continue
                }

                // Optional fields with defaults
                let authToken = (dbDict["authToken"] as? String) ?? ""
                let authUrl = (dbDict["authUrl"] as? String) ?? ""
                let websocketUrl = (dbDict["websocketUrl"] as? String) ?? ""
                let httpApiUrl = (dbDict["httpApiUrl"] as? String) ?? ""
                let httpApiKey = (dbDict["httpApiKey"] as? String) ?? ""
                let secretKey = (dbDict["secretKey"] as? String) ?? ""
                let allowUntrustedCerts = (dbDict["allowUntrustedCerts"] as? Bool) ?? false

                // Transport settings with defaults
                let isBluetoothLeEnabled = (dbDict["isBluetoothLeEnabled"] as? Bool) ?? true
                let isLanEnabled = (dbDict["isLanEnabled"] as? Bool) ?? true
                let isAwdlEnabled = (dbDict["isAwdlEnabled"] as? Bool) ?? true
                let isCloudSyncEnabled = (dbDict["isCloudSyncEnabled"] as? Bool) ?? true

                let config = DittoAppConfig(
                    UUID().uuidString,
                    name: name,
                    appId: appId,
                    authToken: authToken,
                    authUrl: authUrl,
                    websocketUrl: websocketUrl,
                    httpApiUrl: httpApiUrl,
                    httpApiKey: httpApiKey,
                    mode: mode,
                    allowUntrustedCerts: allowUntrustedCerts,
                    secretKey: secretKey,
                    isBluetoothLeEnabled: isBluetoothLeEnabled,
                    isLanEnabled: isLanEnabled,
                    isAwdlEnabled: isAwdlEnabled,
                    isCloudSyncEnabled: isCloudSyncEnabled
                )

                // Save to DatabaseRepository
                try await DatabaseRepository.shared.addDittoAppConfig(config)
                print("✅ Loaded test database: '\(name)' (mode: \(mode.displayName))")
            }

            print("🎉 Test databases loaded successfully")

        } catch {
            print("❌ Error loading test databases: \(error)")
        }
    }
}


