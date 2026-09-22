import Foundation

enum StudioPreferences {
    /// Both SwiftUI property wrappers and services must use the same domain.
    static var store: UserDefaults {
        store(for: .current)
    }

    static func store(for configuration: UITestConfiguration) -> UserDefaults {
        guard let suite = configuration.preferencesSuiteName else { return .standard }
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Unable to create the UI test preferences domain")
        }
        return defaults
    }
}
