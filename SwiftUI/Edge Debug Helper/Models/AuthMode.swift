import Foundation

enum AuthMode: String, CaseIterable, Codable {
    case onlinePlayground = "onlineplayground"
    case offlinePlayground = "offlineplayground"
    case sharedKey = "sharedkey"
    
    var displayName: String {
        switch self {
        case .onlinePlayground:
            return "Online Playground"
        case .offlinePlayground:
            return "Offline Playground"
        case .sharedKey:
            return "Shared Key"
        }
    }
    
    static var `default`: AuthMode {
        return .onlinePlayground
    }
}