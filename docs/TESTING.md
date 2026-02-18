# Testing Guide for Edge Debug Helper

**Complete guide to writing, running, and maintaining tests for Edge Debug Helper.**

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Test Infrastructure](#test-infrastructure)
4. [Writing Unit Tests](#writing-unit-tests)
5. [Writing Integration Tests](#writing-integration-tests)
6. [Writing UI Tests](#writing-ui-tests)
7. [Test Isolation and Sandboxing](#test-isolation-and-sandboxing)
8. [Test Coverage](#test-coverage)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)
11. [CI/CD Integration](#cicd-integration)

---

## Overview

Edge Debug Helper uses a **comprehensive testing strategy** with three types of tests:

- **Unit Tests** (Swift Testing) - Fast, isolated tests for individual components
- **Integration Tests** (Swift Testing) - Multi-component interaction tests
- **UI Tests** (XCTest) - End-to-end user workflow validation

**Testing is mandatory** - all new code must have tests with minimum 80% coverage.

### Why We Test

- **Catch bugs early** - Tests catch issues before they reach production
- **Enable refactoring** - Tests provide safety net for code improvements
- **Document behavior** - Tests show how components should be used
- **Prevent regressions** - Tests ensure bugs stay fixed
- **Build confidence** - Tests enable aggressive optimization

### Current Status

- **Overall Coverage**: 15.96% (target: 50%)
- **SQLCipherService**: 62.19% coverage ✅
- **Test Targets**: 3 (Unit, Integration, UI)
- **Total Tests**: 15+ and growing

---

## Quick Start

### Running Tests

```bash
# Run all tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64"

# Run with coverage
./scripts/generate_coverage_report.sh

# View coverage dashboard
./scripts/coverage_dashboard.sh
```

### Writing Your First Test

```swift
import Testing
@testable import Edge_Debug_Helper

@Suite("My Component Tests")
struct MyComponentTests {

    @Test("Component initializes correctly")
    func testInitialization() async throws {
        // ARRANGE: Set up test data
        let component = MyComponent()

        // ACT: Perform operation
        let result = try await component.initialize()

        // ASSERT: Verify result
        #expect(result == true)
    }
}
```

### Test File Location

Place tests in appropriate directory:

```
SwiftUI/EdgeStudioUnitTests/
├── Services/           # Service layer tests
├── Repositories/       # Data access tests
├── Utilities/          # Helper function tests
└── TestHelpers.swift   # Shared test utilities
```

---

## Test Infrastructure

### Test Targets

| Target | Framework | Purpose | Run Time | Coverage Goal |
|--------|-----------|---------|----------|---------------|
| **EdgeStudioUnitTests** | Swift Testing | Fast, isolated unit tests | <1 sec | 70% |
| **EdgeStudioIntegrationTests** | Swift Testing | Multi-component tests | 1-5 sec | 50% |
| **EdgeStudioUITests** | XCTest | UI automation | 10-30 sec | 30% |

### Running Specific Targets

```bash
# Unit tests only (fastest)
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioUnitTests

# Integration tests only
xcodebuild test -only-testing:EdgeStudioIntegrationTests

# UI tests only (slowest)
xcodebuild test -only-testing:EdgeStudioUITests
```

### Test Organization

```
SwiftUI/
├── EdgeStudioUnitTests/
│   ├── Services/
│   │   ├── SQLCipherServiceTests.swift      # Encryption, schema, CRUD
│   │   ├── KeychainServiceTests.swift       # Secure credential storage
│   │   └── QueryServiceTests.swift          # Query execution
│   ├── Repositories/
│   │   ├── DatabaseRepositoryTests.swift    # Database config management
│   │   ├── HistoryRepositoryTests.swift     # Query history
│   │   ├── FavoritesRepositoryTests.swift   # Favorites management
│   │   ├── SubscriptionsRepositoryTests.swift
│   │   ├── ObservableRepositoryTests.swift
│   │   ├── CollectionsRepositoryTests.swift
│   │   └── SystemRepositoryTests.swift
│   ├── Models/
│   │   ├── DittoConfigTests.swift
│   │   └── SyncStatusInfoTests.swift
│   ├── Utilities/
│   │   ├── DQLGeneratorTests.swift
│   │   └── TableResultsParserTests.swift
│   ├── Fixtures/
│   │   ├── DatabaseConfigFixtures.swift     # Test data generators
│   │   ├── QueryFixtures.swift
│   │   └── MockServices.swift
│   ├── TestHelpers.swift                    # Shared test utilities
│   └── TestConfiguration.swift              # Test environment config
├── EdgeStudioIntegrationTests/
│   ├── RepositoryIntegrationTests.swift
│   ├── DittoManagerIntegrationTests.swift
│   └── EndToEndWorkflowTests.swift
└── EdgeStudioUITests/
    ├── DatabaseManagementUITests.swift
    ├── QueryExecutionUITests.swift
    └── NavigationUITests.swift
```

---

## Writing Unit Tests

### Swift Testing Framework

**All unit tests use Swift Testing framework (`import Testing`), NOT XCTest.**

**Key differences from XCTest:**

| XCTest | Swift Testing |
|--------|---------------|
| `class MyTests: XCTestCase` | `@Suite struct MyTests` |
| `func testFeature()` | `@Test func testFeature()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `setUp()` / `tearDown()` | `init()` / `deinit` |
| Inherits from `XCTestCase` | Plain struct |

### Basic Test Structure

```swift
import Testing
@testable import Edge_Debug_Helper

/// Brief description of what this test suite covers
@Suite("Component Name")
struct ComponentNameTests {

    // Setup runs BEFORE EACH test
    init() async throws {
        try await TestHelpers.setupFreshDatabase()
    }

    // Teardown runs AFTER EACH test
    deinit {
        // Cleanup if needed (usually automatic)
    }

    @Test("Descriptive test name in plain English")
    func testSpecificBehavior() async throws {
        // Test implementation
    }
}
```

### The AAA Pattern

**CRITICAL: All tests MUST follow Arrange-Act-Assert pattern.**

```swift
@Test("Insert config stores all fields correctly")
func testInsertConfig() async throws {
    // ========================================
    // ARRANGE: Set up test data and preconditions
    // ========================================
    try await TestHelpers.setupFreshDatabase()
    let service = SQLCipherService.shared

    let config = SQLCipherService.DatabaseConfigRow(
        _id: TestHelpers.uniqueTestId(),
        name: "Test DB",
        databaseId: "test-db-123",
        mode: "server",
        allowUntrustedCerts: false,
        isBluetoothLeEnabled: true,
        isLanEnabled: true,
        isAwdlEnabled: false,
        isCloudSyncEnabled: true,
        token: "test-token",
        authUrl: "https://auth.test.com",
        websocketUrl: "wss://ws.test.com",
        httpApiUrl: "https://api.test.com",
        httpApiKey: "test-key",
        secretKey: ""
    )

    // ========================================
    // ACT: Perform the operation being tested
    // ========================================
    try await service.insertDatabaseConfig(config)

    // ========================================
    // ASSERT: Verify the expected outcome
    // ========================================
    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.count == 1)
    #expect(configs[0]._id == config._id)
    #expect(configs[0].name == "Test DB")
    #expect(configs[0].token == "test-token")
}
```

**Why AAA?**
- Makes test intent crystal clear
- Easy to understand what's being tested
- Simplifies debugging when tests fail
- Industry standard pattern

### Assertions with #expect()

Swift Testing uses `#expect()` macro (not `XCTAssert` functions).

```swift
// Basic equality
#expect(actual == expected)
#expect(name == "Alice")

// Boolean conditions
#expect(isValid)
#expect(!hasError)

// Comparisons
#expect(count > 0)
#expect(age >= 18)
#expect(price <= 100.0)

// Optional unwrapping
#expect(value != nil)
#expect(optionalString != nil)

// Collection assertions
#expect(array.isEmpty)
#expect(array.count == 5)
#expect(array.contains("item"))
#expect(set.contains(42))

// String assertions
#expect(text.hasPrefix("Hello"))
#expect(text.hasSuffix(".swift"))
#expect(text.contains("world"))

// Throws validation
#expect(throws: DatabaseError.self) {
    try service.invalidOperation()
}

#expect(throws: DatabaseError.notFound) {
    try service.fetchNonexistent()
}

// Does NOT throw
#expect(throws: Never.self) {
    try service.validOperation()
}

// Async operations
let result = try await service.fetchData()
#expect(result.count > 0)
```

### Nested Test Suites

**Organize related tests using nested `@Suite` attributes:**

```swift
@Suite("SQLCipherService Tests", .serialized)
struct SQLCipherServiceTests {

    @Suite("Initialization & Encryption")
    struct InitializationTests {

        @Test("Service initializes successfully")
        func testInitialization() async throws {
            try await TestHelpers.setupUninitializedDatabase()
            let service = SQLCipherService.shared

            try await service.initialize()

            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.isEmpty)
        }

        @Test("Encryption key is generated and stored")
        func testEncryptionKeyGeneration() async throws {
            try await TestHelpers.setupFreshDatabase()

            let dbDir = TestConfiguration.unitTestDatabasePath
            let keyFilePath = URL(fileURLWithPath: dbDir)
                .appendingPathComponent("sqlcipher.key")

            let fileManager = FileManager.default
            #expect(fileManager.fileExists(atPath: keyFilePath.path))

            let keyData = try Data(contentsOf: keyFilePath)
            let key = String(data: keyData, encoding: .utf8)
            #expect(key?.count == 64)  // 256-bit hex key
        }
    }

    @Suite("CRUD Operations")
    struct CRUDTests {

        @Test("Insert stores all fields")
        func testInsertConfig() async throws {
            // ...
        }

        @Test("Update modifies existing config")
        func testUpdateConfig() async throws {
            // ...
        }

        @Test("Delete removes config")
        func testDeleteConfig() async throws {
            // ...
        }
    }

    @Suite("Schema Management")
    struct SchemaTests {

        @Test("Fresh database creates schema version 2")
        func testSchemaVersion() async throws {
            // ...
        }

        @Test("Database has all required tables")
        func testSchemaTablesExist() async throws {
            // ...
        }
    }
}
```

**Benefits:**
- Clear organization in Xcode Test Navigator
- Can run subset of tests (e.g., only CRUD tests)
- Self-documenting structure
- Easy to find specific tests

### Test Tags

**Use tags to categorize and filter tests:**

```swift
// Define tags in TestTags.swift
extension Tag {
    @Tag static var database: Tag
    @Tag static var encryption: Tag
    @Tag static var repository: Tag
    @Tag static var service: Tag
    @Tag static var slow: Tag
    @Tag static var integration: Tag
}

// Use tags in tests
@Test("Encryption key persists across reinitializations",
      .tags(.encryption, .database))
func testEncryptionKeyPersistence() async throws {
    // ...
}

@Test("Large dataset query performance",
      .tags(.slow, .database))
func testLargeDatasetQuery() async throws {
    // ...
}
```

**Filter tests by tag:**

```bash
# Run only encryption tests
xcodebuild test -only-testing:EdgeStudioUnitTests/EncryptionTests

# Skip slow tests during development
xcodebuild test -skip-testing:EdgeStudioUnitTests/SlowTests
```

### Testing Async Code

Swift Testing has **native async/await support**:

```swift
@Test("Async operation completes successfully")
func testAsyncOperation() async throws {
    // Mark test as async
    let service = MyService()

    // Await async operations directly (no completion handlers!)
    let result = try await service.fetchData()

    // Assert on result
    #expect(result.count > 0)
}

@Test("Multiple concurrent operations succeed")
func testConcurrentOperations() async throws {
    // Use TaskGroup for testing concurrent operations
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            try? await service.operation1()
            return true
        }
        group.addTask {
            try? await service.operation2()
            return true
        }

        var successCount = 0
        for await success in group {
            if success { successCount += 1 }
        }

        #expect(successCount == 2)
    }
}

@Test("Operation completes within timeout")
func testOperationTimeout() async throws {
    let startTime = Date()

    _ = try await service.slowOperation()

    let duration = Date().timeIntervalSince(startTime)
    #expect(duration < 5.0)  // Should complete in <5 seconds
}
```

### Test Serialization

**By default, Swift Testing runs tests in parallel.**

For tests with shared state (singletons, files), use `.serialized`:

```swift
// Run all tests in this suite sequentially
@Suite("SQLCipher Service Tests", .serialized)
struct SQLCipherServiceTests {
    // Tests run one at a time (prevents race conditions)
}

// Run specific test suite sequentially
@Suite("File System Tests", .serialized)
struct FileSystemTests {
    // Tests that modify shared file system state
}
```

**When to use `.serialized`:**
- ✅ Tests using singleton instances (actors, managers)
- ✅ Tests modifying shared file system
- ✅ Tests requiring specific execution order
- ✅ Tests with global state (environment variables)

**Prefer parallel execution** when possible - it's **much faster**.

### Testing Error Handling

```swift
@Test("Invalid input throws error")
func testErrorHandling() async throws {
    let service = MyService()

    // Expect specific error type
    #expect(throws: DatabaseError.self) {
        try service.invalidOperation()
    }

    // Expect specific error case
    #expect(throws: DatabaseError.notFound) {
        try service.fetchNonexistent()
    }

    // Verify error message (if needed)
    do {
        try service.invalidOperation()
        #expect(Bool(false), "Should have thrown error")
    } catch let error as DatabaseError {
        #expect(error.localizedDescription.contains("Invalid"))
    }
}
```

---

## Test Isolation and Sandboxing

### Why Test Isolation Matters

**Tests MUST NEVER touch production data.**

- Production data corruption → data loss
- Flaky tests due to shared state
- Tests that pass locally but fail in CI
- Security: test credentials shouldn't access prod

### Runtime Test Detection

Edge Debug Helper uses **runtime detection** to isolate test data:

```swift
// In SQLCipherService.swift
private func getDatabasePath() throws -> URL {
    // Detect test environment at runtime
    let isUnitTesting = NSClassFromString("XCTest") != nil
    let args = ProcessInfo.processInfo.arguments
    let isUITesting = args.contains("UI-TESTING")

    let cacheDir: String
    if isUnitTesting && !isUITesting {
        cacheDir = "ditto_cache_unit_test"  // Unit tests
    } else if isUITesting {
        cacheDir = "ditto_cache_test"       // UI tests
    } else {
        cacheDir = "ditto_cache"            // Production
    }

    let fileManager = FileManager.default
    let appSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]

    return appSupportURL.appendingPathComponent(cacheDir)
}
```

**Test Paths (macOS sandboxed):**

| Environment | Path |
|-------------|------|
| **Production** | `~/Library/Application Support/ditto_cache` |
| **Unit Tests** | `~/Library/Application Support/ditto_cache_unit_test` |
| **UI Tests** | `~/Library/Application Support/ditto_cache_test` |

### Why Runtime Detection?

**Runtime detection** is superior to compile-time flags:

✅ **Works with macOS sandboxing** - Respects app container paths
✅ **No TESTING flag needed** - Normal Debug builds use production paths
✅ **Automatic isolation** - Tests use separate paths automatically
✅ **No build configuration changes** - Clean separation

❌ **Compile-time flags** (like `#if TESTING`) cause issues:
- Require TESTING flag in Debug builds
- Debug runs use test paths (wrong!)
- More complex build setup
- Doesn't work well with sandboxing

### Test Helper Functions

**Use `TestHelpers.swift` for common setup:**

```swift
enum TestHelpers {

    /// Creates a fresh, initialized test database
    /// Use this when you need a working database for tests
    static func setupFreshDatabase() async throws {
        try await setupUninitializedDatabase()
        let service = SQLCipherService.shared
        try await service.initialize()
    }

    /// Creates a clean test database directory (uninitialized)
    /// Use this when testing the initialization process itself
    static func setupUninitializedDatabase() async throws {
        let service = SQLCipherService.shared
        await service.resetForTesting()

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dbDir = appSupportURL.appendingPathComponent("ditto_cache_unit_test")

        // Remove existing test database
        if fileManager.fileExists(atPath: dbDir.path) {
            try? fileManager.removeItem(at: dbDir)
        }

        // Create fresh directory
        try fileManager.createDirectory(
            at: dbDir,
            withIntermediateDirectories: true
        )
    }

    /// Generate unique test ID
    static func uniqueTestId(prefix: String = "test") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
}
```

### When to Use Each Helper

```swift
// ✅ Use setupFreshDatabase() for most tests
@Test("Query executes successfully")
func testQueryExecution() async throws {
    try await TestHelpers.setupFreshDatabase()  // Initialized DB ready to use
    let service = SQLCipherService.shared

    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.isEmpty)  // Fresh database
}

// ✅ Use setupUninitializedDatabase() to test initialization
@Test("Initialize creates schema")
func testInitialization() async throws {
    try await TestHelpers.setupUninitializedDatabase()  // No schema yet
    let service = SQLCipherService.shared

    try await service.initialize()  // Test the initialization itself

    let version = try await service.getSchemaVersion()
    #expect(version == 2)
}
```

### Test Configuration

**`TestConfiguration.swift` provides test-specific paths:**

```swift
enum TestConfiguration {

    /// Unit test database path
    static var unitTestDatabasePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupportURL.appendingPathComponent("ditto_cache_unit_test").path
    }

    /// Verify test isolation is active
    static var isTestMode: Bool {
        NSClassFromString("XCTest") != nil
    }

    /// Clean all test directories
    static func cleanAllTestDirectories() throws {
        let fileManager = FileManager.default
        let testDirs = [
            "ditto_cache_unit_test",
            "ditto_cache_integration_test",
            "ditto_cache_test",
            "ditto_apps_test"
        ]

        for dir in testDirs {
            let url = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(dir)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
```

---

## Test Coverage

### Current Coverage Status

**As of February 2026:**

- **Overall**: 15.96% (target: 50%)
- **SQLCipherService**: 62.19% (500/804 lines) ✅
- **Next Priorities**:
  - DatabaseRepository
  - HistoryRepository
  - FavoritesRepository
  - QueryService

### Coverage Requirements

| Component Type | Minimum Coverage | Rationale |
|---------------|------------------|-----------|
| **Services** (SQLCipherService, QueryService) | 80% | Critical business logic |
| **Repositories** (all repositories) | 70% | Data access layer |
| **Utilities** (DQL generators, parsers) | 75% | Complex logic |
| **View Models** | 60% | UI state management |
| **Models** (data classes) | 50% | Simple getters/setters |

### Running Coverage Reports

```bash
# Generate coverage report
./scripts/generate_coverage_report.sh

# View detailed dashboard
./scripts/coverage_dashboard.sh
```

**Output:**

```
🧪 Running tests with coverage...
✅ Tests passed

📊 Coverage Dashboard
====================

Overall Coverage: 15.96%

SQLCipherService Coverage:
--------------------------
SQLCipherService.swift: 62.19% (500/804 lines)

Test Files Coverage:
--------------------
SQLCipherServiceTests.swift: 100.00%
TestHelpers.swift: 100.00%

To view detailed coverage in Xcode:
1. Open TestResults.xcresult in Xcode
2. Navigate to Coverage tab
```

### Viewing Coverage in Xcode

1. Open `SwiftUI/TestResults.xcresult` in Xcode
2. Navigate to **Coverage** tab
3. Browse per-file and per-function coverage
4. Click files to see line-by-line highlighting

**Colors:**
- **Green** = Covered by tests ✅
- **Red** = Not covered by tests ⚠️

### Coverage Enforcement

**Pre-push hook** automatically enforces 50% minimum:

```bash
# Enable pre-push hook
chmod +x .git/hooks/pre-push

# Hook runs automatically before push
git push origin main

# If coverage < 50%, push is blocked:
❌ Coverage 45.2% is below threshold 50%
   Fix coverage or use: git push --no-verify

# Bypass once (emergency only)
git push --no-verify
```

### Coverage Best Practices

- **Focus on critical paths first**: Security, data storage, auth
- **Don't chase 100%**: 80-90% is realistic and valuable
- **Test behavior, not implementation**: Don't test private methods
- **Use coverage to find gaps**: Low coverage = missing test cases
- **Exclude generated code**: Add to `.xcovignore` file

---

## Best Practices

### 1. Test Naming

**Use descriptive test names in plain English:**

```swift
// ✅ GOOD - Clear intent
@Test("Insert config stores all fields correctly")
@Test("Update modifies existing database config")
@Test("Delete removes config and returns success")

// ❌ BAD - Unclear
@Test("test1")
@Test("testInsert")
@Test("testUpdate")
```

### 2. One Assertion Per Test (Prefer)

```swift
// ✅ GOOD - One concept per test
@Test("Insert creates new config")
func testInsertCreatesConfig() async throws {
    try await service.insertDatabaseConfig(config)
    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.count == 1)
}

@Test("Insert stores config name correctly")
func testInsertStoresName() async throws {
    try await service.insertDatabaseConfig(config)
    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs[0].name == "Test DB")
}

// ⚠️ ACCEPTABLE - Multiple related assertions
@Test("Insert stores all config fields")
func testInsertStoresAllFields() async throws {
    try await service.insertDatabaseConfig(config)
    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.count == 1)
    #expect(configs[0].name == "Test DB")
    #expect(configs[0].token == "test-token")
    #expect(configs[0].databaseId == "test-db-123")
}
```

### 3. Test Independence

**Each test should be independent:**

```swift
// ✅ GOOD - Tests don't depend on each other
@Suite("My Tests")
struct MyTests {

    init() async throws {
        // Fresh setup for EACH test
        try await TestHelpers.setupFreshDatabase()
    }

    @Test func testA() async throws {
        // Standalone test
    }

    @Test func testB() async throws {
        // Doesn't depend on testA
    }
}

// ❌ BAD - Tests depend on execution order
@Suite("Bad Tests")
struct BadTests {
    static var sharedState: String?

    @Test func testA() {
        BadTests.sharedState = "data"
    }

    @Test func testB() {
        // Breaks if testA doesn't run first!
        #expect(BadTests.sharedState == "data")
    }
}
```

### 4. Avoid Test Logic

**Tests should be simple and linear:**

```swift
// ✅ GOOD - Simple, linear test
@Test("Insert stores config")
func testInsert() async throws {
    try await service.insertDatabaseConfig(config)
    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.count == 1)
}

// ❌ BAD - Complex logic in test
@Test("Complex test logic")
func testComplexLogic() async throws {
    for i in 0..<10 {
        if i % 2 == 0 {
            try await service.insertConfig(makeConfig(i))
        } else {
            try await service.deleteConfig(makeConfig(i).id)
        }
    }
    // What are we even testing?
}
```

### 5. Descriptive Failure Messages

```swift
// ✅ GOOD - Clear failure message
#expect(
    configs.count == 1,
    "Expected 1 config after insert, got \(configs.count)"
)

#expect(
    configs[0].name == "Test DB",
    "Config name should be 'Test DB', got '\(configs[0].name)'"
)

// ⚠️ OK - Implicit message from #expect
#expect(configs.count == 1)
```

### 6. Use Test Fixtures

**Create reusable test data generators:**

```swift
// In DatabaseConfigFixtures.swift
struct DatabaseConfigFixtures {

    static func validConfig(id: String = UUID().uuidString) -> DatabaseConfigRow {
        DatabaseConfigRow(
            _id: id,
            name: "Test DB \(id)",
            databaseId: "db-\(id)",
            mode: "server",
            allowUntrustedCerts: false,
            isBluetoothLeEnabled: true,
            isLanEnabled: true,
            isAwdlEnabled: true,
            isCloudSyncEnabled: true,
            token: "token-\(id)",
            authUrl: "https://auth.test.com",
            websocketUrl: "wss://ws.test.com",
            httpApiUrl: "https://api.test.com",
            httpApiKey: "key-\(id)",
            secretKey: ""
        )
    }

    static func offlinePlaygroundConfig() -> DatabaseConfigRow {
        var config = validConfig()
        config.mode = "offlinePlayground"
        config.token = ""
        config.isCloudSyncEnabled = false
        return config
    }
}

// Use in tests
@Test func testInsert() async throws {
    let config = DatabaseConfigFixtures.validConfig()
    try await service.insertDatabaseConfig(config)
    // ...
}
```

### 7. Test Edge Cases

```swift
@Suite("Edge Cases")
struct EdgeCaseTests {

    @Test("Empty string input")
    func testEmptyString() async throws {
        let config = DatabaseConfigFixtures.validConfig()
        config.name = ""
        // Should handle gracefully
    }

    @Test("Very long string input")
    func testLongString() async throws {
        let config = DatabaseConfigFixtures.validConfig()
        config.name = String(repeating: "a", count: 1000)
        // Should truncate or reject
    }

    @Test("Nil optional fields")
    func testNilFields() async throws {
        let config = DatabaseConfigFixtures.validConfig()
        config.token = ""
        config.authUrl = ""
        // Should work for offline mode
    }
}
```

### 8. What NOT to Test

**Don't waste time testing:**

- Simple getters/setters with no logic
- Third-party library internals (Ditto SDK)
- Auto-generated code (`FontAwesomeIcons.swift`)
- SwiftUI view layouts (use UI tests instead)
- Private methods directly (test through public API)

**DO test:**

- Business logic and algorithms
- Data transformations
- Error handling
- Boundary conditions
- Component integration

---

## Troubleshooting

### Common Issues

#### 1. Tests Fail Locally But Pass in CI

**Cause:** Shared state between tests (race conditions)

**Solution:** Add `.serialized` to test suite:

```swift
@Suite("My Tests", .serialized)
struct MyTests {
    // Tests run sequentially
}
```

#### 2. "SQLCipherService is not initialized"

**Cause:** Test didn't call setup helper

**Solution:** Use proper test setup:

```swift
init() async throws {
    try await TestHelpers.setupFreshDatabase()
}
```

#### 3. "Database file already exists"

**Cause:** Previous test didn't clean up

**Solution:** Ensure `setupUninitializedDatabase()` removes old data:

```swift
if fileManager.fileExists(atPath: dbDir.path) {
    try? fileManager.removeItem(at: dbDir)
}
```

#### 4. Tests Are Slow

**Causes:**
- Running UI tests during development (use unit tests)
- Not using `.serialized` when needed (causes retries)
- Creating too many database instances

**Solutions:**

```bash
# Run only unit tests (fast)
xcodebuild test -only-testing:EdgeStudioUnitTests

# Skip slow tests during development
xcodebuild test -skip-testing:EdgeStudioUnitTests/SlowTests
```

#### 5. Coverage Report Not Generated

**Cause:** Tests didn't run with coverage enabled

**Solution:**

```bash
# Run with coverage
./scripts/generate_coverage_report.sh

# Or manually
xcodebuild test -enableCodeCoverage YES \
                -resultBundlePath TestResults.xcresult
```

#### 6. Test Isolation Not Working

**Symptoms:** Tests affect production data

**Cause:** Runtime detection failing

**Solution:** Verify test is using correct path:

```swift
@Test func testIsolation() async throws {
    let isTest = NSClassFromString("XCTest") != nil
    #expect(isTest == true)  // Should be true in tests

    let path = TestConfiguration.unitTestDatabasePath
    #expect(path.contains("ditto_cache_unit_test"))
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

**Create `.github/workflows/test.yml`:**

```yaml
name: Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v3

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '26.2'

    - name: Run Unit Tests
      run: |
        xcodebuild test \
          -project "SwiftUI/Edge Debug Helper.xcodeproj" \
          -scheme "Edge Studio" \
          -destination "platform=macOS,arch=arm64" \
          -only-testing:EdgeStudioUnitTests

    - name: Run Integration Tests
      run: |
        xcodebuild test \
          -project "SwiftUI/Edge Debug Helper.xcodeproj" \
          -scheme "Edge Studio" \
          -destination "platform=macOS,arch=arm64" \
          -only-testing:EdgeStudioIntegrationTests

    - name: Generate Coverage Report
      run: ./scripts/generate_coverage_report.sh

    - name: Check Coverage Threshold
      run: |
        COVERAGE=$(cat coverage.json | jq -r '.lineCoverage * 100')
        if (( $(echo "$COVERAGE < 50" | bc -l) )); then
          echo "❌ Coverage $COVERAGE% is below threshold 50%"
          exit 1
        fi
        echo "✅ Coverage $COVERAGE% meets threshold"

    - name: Upload Coverage
      uses: actions/upload-artifact@v3
      with:
        name: coverage-report
        path: SwiftUI/TestResults.xcresult
```

### Pull Request Template

**Create `.github/PULL_REQUEST_TEMPLATE.md`:**

```markdown
## Description

<!-- Brief description of changes -->

## Testing Checklist

**CRITICAL: All items must be checked before merging.**

### Tests Written
- [ ] Unit tests added for new code
- [ ] Integration tests added if needed
- [ ] UI tests added for new workflows
- [ ] All tests pass locally (`⌘U` in Xcode)

### Coverage
- [ ] Coverage has not decreased
- [ ] New code has 80%+ coverage
- [ ] Coverage report reviewed: `./scripts/coverage_dashboard.sh`

### Code Quality
- [ ] No new SwiftLint warnings
- [ ] Code follows AAA test pattern
- [ ] Test names are descriptive
- [ ] No skipped or commented-out tests

### Documentation
- [ ] Test documentation added to test files
- [ ] CLAUDE.md updated if testing patterns changed
- [ ] README.md updated if setup changed

## Coverage Report

```
Overall Coverage: XX.XX%
New Code Coverage: XX.XX%
```

## Additional Notes

<!-- Any additional context -->
```

---

## Additional Resources

### Official Documentation

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [XCTest Framework](https://developer.apple.com/documentation/xctest)
- [XCUITest](https://developer.apple.com/documentation/xcuiautomation)

### Project Documentation

- [`CLAUDE.md`](../CLAUDE.md) - Complete project guide
- [`scripts/README.md`](../scripts/README.md) - Coverage scripts documentation
- [`TEST_MIGRATION_LOG.md`](../TEST_MIGRATION_LOG.md) - Testing infrastructure history

### Examples

- `SwiftUI/EdgeStudioUnitTests/Services/SQLCipherServiceTests.swift` - Complete test example
- `SwiftUI/EdgeStudioUnitTests/TestHelpers.swift` - Test utilities
- `SwiftUI/EdgeStudioUnitTests/Fixtures/` - Test data generators

---

## Summary

**Key Takeaways:**

1. **Testing is mandatory** - All new code must have tests with 80%+ coverage
2. **Use Swift Testing** - Modern framework for unit/integration tests
3. **Follow AAA pattern** - Arrange-Act-Assert for clarity
4. **Test isolation** - Use runtime detection and `TestHelpers`
5. **Run tests frequently** - Fast feedback during development
6. **Monitor coverage** - Use `./scripts/generate_coverage_report.sh`
7. **Keep tests simple** - Linear, independent, descriptive

**Questions or issues?** Check [Troubleshooting](#troubleshooting) or file an issue on GitHub.

Happy testing! 🧪
