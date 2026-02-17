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
    }

    func setError(_ error: Error?) {
        DispatchQueue.main.async {
            self.error = error
        }
    }
}
