import Foundation

enum AuthMode: String, CaseIterable, Codable {
    case server
    case smallPeersOnly = "smallpeersonly"

    var displayName: String {
        switch self {
        case .server:
            return "Server"
        case .smallPeersOnly:
            return "Small Peers Only"
        }
    }

    static var `default`: AuthMode {
        .server
    }
}
