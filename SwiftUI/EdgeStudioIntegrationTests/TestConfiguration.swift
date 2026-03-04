import Foundation

/// Test environment configuration
/// Ensures tests use separate database directories and never touch production data
enum TestConfiguration {
    
    // MARK: - Test Database Paths
    
    /// Base directory for unit test databases
    /// Returns the actual Application Support directory (respects sandboxing)
    static var unitTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL.appendingPathComponent("ditto_cache_unit_test").path
    }

    /// Base directory for integration test databases
    /// Returns the actual Application Support directory (respects sandboxing)
    static var integrationTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL.appendingPathComponent("ditto_cache_integration_test").path
    }

    /// Base directory for UI test databases
    /// Returns the actual Application Support directory (respects sandboxing)
    static var uiTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL.appendingPathComponent("ditto_cache_test").path
    }
    
    // MARK: - Test Mode Detection
    
    /// Verify test isolation is active
    /// Returns true if running in test mode (UI-TESTING argument present)
    static var isTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("UI-TESTING")
    }
    
    // MARK: - Test Directory Management
    
    /// Clean all test database directories
    /// Call this in test teardown to ensure clean state
    static func cleanAllTestDirectories() throws {
        let fileManager = FileManager.default
        let testDirs = [
            "ditto_cache_unit_test",
            "ditto_cache_integration_test",
            "ditto_cache_test",
            "ditto_apps_test",
            "ditto_appconfig_test"
        ]
        
        for dir in testDirs {
            let url = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(dir)
            
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
    
    /// Clean specific test directory
    static func cleanTestDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }
    
    /// Create test directory if it doesn't exist
    static func ensureTestDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    // MARK: - Safety Checks
    
    /// Verify we're not using production directories
    /// Throws error if production paths are detected
    static func verifyTestIsolation() throws {
        let productionPaths = [
            "ditto_cache",
            "ditto_apps",
            "ditto_appconfig"
        ]
        
        let testPaths = [
            unitTestDatabasePath,
            integrationTestDatabasePath,
            uiTestDatabasePath
        ]
        
        for testPath in testPaths {
            for productionPath in productionPaths {
                if testPath.contains(productionPath) && !testPath.contains("_test") {
                    throw TestConfigurationError.productionPathDetected(testPath)
                }
            }
        }
    }
}

// MARK: - Errors

enum TestConfigurationError: Error {
    case productionPathDetected(String)
    
    var localizedDescription: String {
        switch self {
        case .productionPathDetected(let path):
            return "CRITICAL: Test attempted to use production path: \(path)"
        }
    }
}
