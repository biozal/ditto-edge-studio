import Foundation

enum AppError: Error {
    case error(message: String)
}

class AppState: ObservableObject {
    @Published var appConfig: DittoConfigForDatabase
    @Published var error: Error?

    init() {
        // Initialize with empty config - database configs now loaded from secure storage
        appConfig = DittoConfigForDatabase.new()

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
        DispatchQueue.main.async {
            self.error = error
        }
    }
}
