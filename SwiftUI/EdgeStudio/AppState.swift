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
        // Initialize SQLCipher on app startup
        Task {
            do {
                try await SQLCipherService.shared.initialize()
                Log.info("✅ SQLCipher initialized successfully")
            } catch {
                Log.error("❌ Failed to initialize SQLCipher: \(error.localizedDescription)")
                self.setError(error)
            }
        }
    }

    func setError(_ error: Error?) {
        self.error = error
    }
}
