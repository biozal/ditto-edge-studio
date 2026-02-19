import Foundation
@testable import Ditto_Edge_Studio

/// Common test helper functions
enum TestHelpers {
    
    // MARK: - ID Generation
    
    /// Generate unique test ID with optional prefix
    /// - Parameter prefix: Prefix for the ID (default: "test")
    /// - Returns: Unique identifier in format "prefix-UUID"
    static func uniqueTestId(prefix: String = "test") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
    
    /// Generate unique database name for testing
    static func uniqueDatabaseName() -> String {
        "TestDB-\(UUID().uuidString.prefix(8))"
    }
    
    // MARK: - Async Utilities
    
    /// Wait for specified duration (for async operations)
    /// - Parameter seconds: Duration to wait
    static func wait(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    
    /// Wait until condition becomes true or timeout expires
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    ///   - interval: Check interval (default: 0.1 seconds)
    ///   - condition: Async condition to check
    /// - Returns: True if condition met, false if timeout
    static func waitUntil(
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.1,
        condition: () async -> Bool
    ) async -> Bool {
        let endTime = Date().addingTimeInterval(timeout)
        
        while Date() < endTime {
            if await condition() {
                return true
            }
            await wait(seconds: interval)
        }
        
        return false
    }
    
    /// Wait until async throws condition succeeds or timeout expires
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    ///   - interval: Check interval (default: 0.1 seconds)
    ///   - condition: Async throws condition to check
    /// - Returns: True if condition succeeded, false if timeout or error
    static func waitUntilSucceeds(
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.1,
        condition: () async throws -> Void
    ) async -> Bool {
        let endTime = Date().addingTimeInterval(timeout)
        
        while Date() < endTime {
            do {
                try await condition()
                return true
            } catch {
                await wait(seconds: interval)
            }
        }
        
        return false
    }
    
    // MARK: - File Utilities
    
    /// Create temporary test file
    /// - Parameters:
    ///   - name: File name
    ///   - content: File content
    /// - Returns: URL to created file
    static func createTempFile(name: String, content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    /// Remove temporary test file
    static func removeTempFile(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Random Data Generation
    
    /// Generate random string of specified length
    static func randomString(length: Int = 10) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
    
    /// Generate random integer in range
    static func randomInt(min: Int = 0, max: Int = 100) -> Int {
        Int.random(in: min...max)
    }
    
    /// Generate random date within past days
    static func randomDate(withinPastDays days: Int = 30) -> Date {
        let now = Date()
        let secondsInDay = 86400.0
        let randomSeconds = TimeInterval.random(in: 0...(Double(days) * secondsInDay))
        return now.addingTimeInterval(-randomSeconds)
    }
    
    // MARK: - Test Data Cleanup

    /// Clean up test resources after test completion
    /// Call this in test deinit or teardown
    static func cleanupTestResources() async throws {
        try TestConfiguration.cleanAllTestDirectories()
    }

    // MARK: - Database Testing (Isolated per-task instances)

    /// Runs the test body with a fully isolated, initialized SQLCipher database.
    ///
    /// Each call creates a unique directory, spins up a fresh service instance,
    /// injects it via @TaskLocal (so repositories automatically see it), executes
    /// the body, then deletes the directory — even if the body throws.
    ///
    /// Concurrent test suites each get their own directory; there is NO shared
    /// filesystem state between tasks.
    ///
    /// Usage:
    /// ```swift
    /// @Test("My test") func testSomething() async throws {
    ///     try await TestHelpers.withFreshDatabase {
    ///         let service = SQLCipherContext.current
    ///         // Database is initialized and isolated to this task
    ///     }
    /// }
    /// ```
    @discardableResult
    static func withFreshDatabase<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let uniqueDirName = "ditto_test_\(UUID().uuidString)"
        let testService = SQLCipherService(testPath: uniqueDirName)
        try await testService.initialize()

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testDirURL = appSupportURL.appendingPathComponent(uniqueDirName)

        defer {
            try? FileManager.default.removeItem(at: testDirURL)
        }

        return try await SQLCipherContext.$current.withValue(testService) {
            try await body()
        }
    }

    /// Runs the test body with an uninitialized, isolated SQLCipher database.
    ///
    /// Use ONLY for tests that explicitly test the `initialize()` method itself.
    /// The service instance is created but NOT initialized before calling the body.
    ///
    /// Usage:
    /// ```swift
    /// @Test("Test initialization") func testInit() async throws {
    ///     try await TestHelpers.withUninitializedDatabase {
    ///         let service = SQLCipherContext.current
    ///         try await service.initialize()  // Test the initialization
    ///         // Verify initialization worked...
    ///     }
    /// }
    /// ```
    @discardableResult
    static func withUninitializedDatabase<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let uniqueDirName = "ditto_test_uninit_\(UUID().uuidString)"
        let testService = SQLCipherService(testPath: uniqueDirName)
        // NOT calling initialize() — the test body does that explicitly

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testDirURL = appSupportURL.appendingPathComponent(uniqueDirName)

        defer {
            try? FileManager.default.removeItem(at: testDirURL)
        }

        return try await SQLCipherContext.$current.withValue(testService) {
            try await body()
        }
    }
}
