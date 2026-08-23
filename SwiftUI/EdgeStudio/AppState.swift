import Foundation
import Observation

enum AppError: Error {
    case error(message: String)
}

@Observable
@MainActor
final class AppState {
    var error: Error?

    init() {
        // Eagerly warm up SQLCipher so the picker has data ready when it appears.
        // We log but do NOT propagate failures here — `ContentView.ViewModel.loadApps`
        // calls `initialize()` itself (idempotent) and is the canonical place that
        // surfaces SQLCipher init failure to the user with a Retry affordance.
        Task {
            do {
                try await SQLCipherService.shared.initialize()
                Log.info("✅ SQLCipher initialized successfully")
            } catch {
                Log.error("❌ Failed to initialize SQLCipher (will surface via loadApps retry): \(error.localizedDescription)")
            }
        }
    }

    func setError(_ error: Error?) {
        self.error = error
    }
}
