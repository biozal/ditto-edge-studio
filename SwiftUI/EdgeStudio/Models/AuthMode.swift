import Foundation

/// Database connection mode, named to match the Ditto v5 portal.
///
/// Raw values are persisted (in the SQLite `mode` column and in exported JSON),
/// so reading must tolerate the legacy raw values too — that mapping lives in
/// `DittoAppConfigLoader.parseMode(from:)`, which is used everywhere a stored
/// string is turned back into an `AuthMode`.
enum AuthMode: String, CaseIterable, Codable {
    case development
    case smallPeerOnly

    var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .smallPeerOnly:
            return "Small Peer Only"
        }
    }

    static var `default`: AuthMode {
        .development
    }
}
