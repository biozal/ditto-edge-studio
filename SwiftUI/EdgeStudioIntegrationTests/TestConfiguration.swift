import Foundation

/// Test environment configuration
/// Ensures tests use separate database directories and never touch production data
///
/// The directory names here MUST mirror the real isolation scheme in
/// `SQLCipherService.getDatabasePath()`:
///   - production:        `ditto_edge_studio`
///   - unit tests:        `ditto_edge_studio_unit_test`
///   - UI tests:          `ditto_edge_studio_test`
///   - integration tests: `ditto_test_<UUID>` per test run
///     (see `TestHelpers.withFreshDatabase`)
enum TestConfiguration {
    // MARK: - Test Database Paths

    /// Base directory for unit test databases
    /// Returns the actual Application Support directory (respects sandboxing)
    static var unitTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL.appendingPathComponent("ditto_edge_studio_unit_test").path
    }

    /// Directory name prefix for integration test databases. Integration tests
    /// do not share a single directory — each run gets a unique
    /// `ditto_test_<UUID>` directory that self-deletes via `defer` in
    /// `TestHelpers.withFreshDatabase`.
    static var integrationTestDirectoryPrefix: String {
        "ditto_test_"
    }

    /// Base directory for UI test databases
    /// Returns the actual Application Support directory (respects sandboxing)
    static var uiTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL.appendingPathComponent("ditto_edge_studio_test").path
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
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // Fixed-name directories used by the unit/UI test modes of
        // SQLCipherService.getDatabasePath().
        let fixedTestDirs = [
            "ditto_edge_studio_unit_test",
            "ditto_edge_studio_test"
        ]

        for dir in fixedTestDirs {
            let url = appSupportURL.appendingPathComponent(dir)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        // Per-test integration directories (ditto_test_<UUID>) normally
        // self-delete via `defer` in TestHelpers.withFreshDatabase, but a
        // crashed test run can orphan them — sweep any that remain.
        let contents = try fileManager.contentsOfDirectory(atPath: appSupportURL.path)
        for entry in contents where entry.hasPrefix(integrationTestDirectoryPrefix) {
            try fileManager.removeItem(at: appSupportURL.appendingPathComponent(entry))
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
        // The real production directory from SQLCipherService.getDatabasePath().
        let productionDirectoryName = "ditto_edge_studio"

        let testPaths = [
            unitTestDatabasePath,
            uiTestDatabasePath
        ]

        for testPath in testPaths {
            let lastComponent = (testPath as NSString).lastPathComponent
            // A test path whose directory is exactly the production name — or
            // that lacks a `_test` marker — would read and write production
            // data. Fail loudly before that can happen.
            if lastComponent == productionDirectoryName || !lastComponent.contains("_test") {
                throw TestConfigurationError.productionPathDetected(testPath)
            }
        }
    }
}

// MARK: - Errors

enum TestConfigurationError: Error {
    case productionPathDetected(String)

    var localizedDescription: String {
        switch self {
        case let .productionPathDetected(path):
            return "CRITICAL: Test attempted to use production path: \(path)"
        }
    }
}
