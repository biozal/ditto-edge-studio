import Testing

/// Test tags for organizing and filtering tests
///
/// Usage:
/// ```swift
/// @Test(.tags(.encryption, .slow))
/// func testEncryptionPerformance() { ... }
/// ```
///
/// Run tests with specific tags:
/// ```bash
/// swift test --filter tag:encryption
/// swift test --skip tag:slow
/// ```
extension Tag {
    
    // MARK: - Component Tags
    
    /// Tests related to encryption (SQLCipher, Keychain)
    @Tag static var encryption: Tag
    
    /// Tests related to database operations
    @Tag static var database: Tag
    
    /// Tests related to repository layer
    @Tag static var repository: Tag
    
    /// Tests related to service layer
    @Tag static var service: Tag
    
    /// Tests related to models and data structures
    @Tag static var model: Tag
    
    /// Tests related to utilities and helpers
    @Tag static var utility: Tag
    
    // MARK: - Test Type Tags
    
    /// Integration tests (multi-component)
    @Tag static var integration: Tag
    
    /// UI tests
    @Tag static var ui: Tag
    
    /// Performance tests
    @Tag static var performance: Tag
    
    /// Regression tests
    @Tag static var regression: Tag
    
    // MARK: - Duration Tags
    
    /// Tests that take >1 second to run
    @Tag static var slow: Tag
    
    /// Tests that take >5 seconds to run
    @Tag static var verySlow: Tag
    
    /// Quick tests (<0.1 seconds)
    @Tag static var fast: Tag
    
    // MARK: - Stability Tags
    
    /// Tests that occasionally fail (flaky)
    @Tag static var flaky: Tag
    
    /// Tests that require external resources (network, etc.)
    @Tag static var external: Tag
    
    /// Tests that require specific environment setup
    @Tag static var requiresSetup: Tag
}

// MARK: - Tag Combinations

/// Common tag combinations for convenience
extension Tag {
    
    /// Database encryption tests (slow, encryption, database)
    static var databaseEncryption: [Tag] {
        [.encryption, .database, .slow]
    }
    
    /// Quick unit tests (fast, no external dependencies)
    static var quickUnit: [Tag] {
        [.fast]
    }
    
    /// Slow integration tests
    static var slowIntegration: [Tag] {
        [.integration, .slow]
    }
}
