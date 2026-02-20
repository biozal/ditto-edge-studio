# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Edge Debug Helper is a comprehensive SwiftUI application for macOS and iPadOS, providing a production-ready GUI for querying and managing Ditto databases.

## Ditto SDK Version

**CRITICAL: This project is migrating to Ditto SDK v5.**

### Terminology Changes (v5)

In Ditto SDK v5, the terminology has changed:
- **Old term:** "Ditto App" (or "App")
- **New term:** "Ditto Database" (or "Database")

**Throughout this codebase:**
- When we refer to a "Ditto App", we actually mean a **Ditto Database**
- The model `DittoConfigForDatabase` represents a database configuration (formerly known as app config)
- Each "database" in the UI represents a separate Ditto database instance with its own configuration
## Screenshots

From time to time to debug or design new features screenshots or design mock ups will always be stored in the screens folder of the repository.  If you are told
there is a screenshot named and then a filename always asssume it's in the screens folder.

## File Management with Xcode MCP Server

**CRITICAL WORKFLOW REQUIREMENT: When adding or modifying files in this project, ALWAYS use the Xcode MCP server.**

### Why Use Xcode MCP Server

The Xcode MCP server ensures proper integration with the Xcode project structure:
- Automatically adds new files to the correct build targets
- Maintains proper file references in the `.xcodeproj` structure
- Prevents "file not in target" compilation errors
- Handles File System Synchronized directories correctly
- Updates `project.pbxproj` with proper membership settings

### When to Use Xcode MCP Server

Use the Xcode MCP server for:
- ✅ Creating new Swift files (Views, ViewModels, Utilities, etc.)
- ✅ Creating new test files (unit tests, UI tests)
- ✅ Adding new resource files (images, fonts, plists)
- ✅ Moving or renaming files within the project
- ✅ Any operation that modifies the Xcode project structure

### How to Use

Before creating or modifying files that need to be part of the Xcode project:

1. **Check available Xcode MCP tools:**
   ```
   Use ToolSearch to find xcode-related tools
   ```

2. **Use appropriate Xcode MCP commands** for file operations instead of standard file tools

3. **Verify the file appears in Xcode** after creation/modification

### Standard File Operations vs. Xcode Operations

| Operation | Use Standard Tools | Use Xcode MCP Server |
|-----------|-------------------|---------------------|
| Read existing files | ✅ Read tool | - |
| Edit existing files | ✅ Edit tool | - |
| Create documentation (`.md` files) | ✅ Write tool | - |
| Create Swift source files | ❌ | ✅ Xcode MCP |
| Create test files | ❌ | ✅ Xcode MCP |
| Add resources to bundle | ❌ | ✅ Xcode MCP |
| Move files in project | ❌ | ✅ Xcode MCP |

**Important:** Only use the Xcode MCP server for files that need to be compiled or bundled with the app. Documentation, scripts, and configuration files outside the Xcode project can use standard file tools.

## Testing Requirements

**CRITICAL RULE: All code MUST have tests. All tests MUST be runnable in Xcode and MUST pass after any code changes.**

### Testing Philosophy

Testing is **mandatory**, not optional. Every feature, service, repository, and significant logic change must have corresponding tests. Tests are:
- **Documentation** - Tests show how code should be used
- **Safety Net** - Tests catch regressions when refactoring
- **Design Tool** - Writing tests first improves API design
- **Confidence** - Tests enable aggressive refactoring and optimization

**Coverage Requirements:**
- **New Code**: 80%+ coverage required for all new code
- **Existing Code**: Minimum 50% overall coverage (current: 15.96%)
- **Critical Paths**: 95%+ coverage for security, data storage, authentication

### Test Infrastructure

Edge Debug Helper uses **three separate test targets** for comprehensive testing:

| Target | Framework | Purpose | Coverage Goal |
|--------|-----------|---------|---------------|
| **EdgeStudioUnitTests** | Swift Testing | Fast, isolated unit tests | 70% |
| **EdgeStudioIntegrationTests** | Swift Testing | Multi-component integration tests | 50% |
| **EdgeStudioUITests** | XCTest | UI automation and visual validation | 30% |

**Why three targets?**
- **Unit tests** run in <1 second - fast feedback during development
- **Integration tests** validate components work together
- **UI tests** catch visual regressions and user workflow issues

### Testing Framework: Swift Testing

**All new unit and integration tests MUST use Swift Testing framework (`import Testing`), NOT XCTest.**

**Why Swift Testing?**
- Modern, native Swift API (not Objective-C based like XCTest)
- Better async/await support
- Clearer test organization with `@Suite` and `@Test` attributes
- More expressive assertions with `#expect()` macro
- Parallel execution by default (with `.serialized` opt-out)
- Better Xcode integration

**XCTest is ONLY used for UI tests** (XCUITest framework has no Swift Testing alternative).

### General Testing Rules
- Tests must be properly configured to compile and run in the Xcode test target
- Tests must NOT be moved to temporary directories or locations outside the project
- If tests produce warnings about being in the wrong target, fix the Xcode project configuration (using `membershipExceptions` in project.pbxproj for File System Synchronized targets)
- Tests that cannot be run in Xcode are not acceptable and the configuration must be fixed
- Use Swift Testing framework (`import Testing`) for all new unit tests, not XCTest
- Use XCTest for UI tests (XCUITest framework)

---

## Writing Unit Tests with Swift Testing

### Test File Structure

Tests are split across two targets by type of I/O:

**`SwiftUI/EdgeStudioUnitTests/`** — Pure logic, no real I/O (~105 tests):
```
EdgeStudioUnitTests/
├── Models/
│   └── ModelTests.swift                 # Pure in-memory model tests
├── Utilities/
│   └── DQLGeneratorTests.swift          # Pure string generation, no I/O
├── Repositories/
│   ├── CollectionsRepositoryTests.swift # Error paths only, no DB
│   └── SystemRepositoryTests.swift      # Error paths only, no Ditto/DB
├── Services/
│   └── QueryServiceTests.swift          # Error paths + format string tests
├── Fixtures/
│   └── QueryFixtures.swift              # Shared fixture data (also copied to integration)
└── TestTags.swift                       # Shared test tags (also copied to integration)
```

**`SwiftUI/EdgeStudioIntegrationTests/`** — Real I/O, multi-component (~115 tests):
```
EdgeStudioIntegrationTests/
├── Services/
│   ├── SQLCipherServiceTests.swift      # Real SQLite file I/O
│   └── KeychainServiceTests.swift       # Real macOS Keychain
├── Repositories/
│   ├── DatabaseRepositoryTests.swift    # Repository + SQLCipher + SQLite
│   ├── HistoryRepositoryTests.swift     # Repository + SQLCipher + SQLite
│   ├── FavoritesRepositoryTests.swift   # Repository + SQLCipher + SQLite
│   ├── SubscriptionsRepositoryTests.swift # Repository + SQLCipher + SQLite
│   └── ObservableRepositoryTests.swift  # Repository + SQLCipher + SQLite
├── Fixtures/
│   ├── DatabaseConfigFixtures.swift     # Fixture data for repository tests
│   ├── MockServices.swift               # Mock implementations
│   └── QueryFixtures.swift              # Shared fixture data (copy from unit tests)
├── TestHelpers.swift                    # withFreshDatabase, test isolation helpers
├── TestConfiguration.swift             # Test environment configuration
└── TestTags.swift                       # Shared test tags (copy from unit tests)
```

**Decision rule:** If a test touches real SQLite files, the macOS Keychain, or exercises multiple layers (Repository → SQLCipher → SQLite), it belongs in `EdgeStudioIntegrationTests`. Pure in-memory logic with no real I/O belongs in `EdgeStudioUnitTests`.

### Basic Test Structure

**Use `@Suite` to group related tests:**

```swift
import Testing
@testable import Edge_Debug_Helper

@Suite("Component Name")
struct ComponentNameTests {

    // Setup runs before EACH test
    init() async throws {
        // Initialize fresh test state
        try await TestHelpers.setupFreshDatabase()
    }

    // Teardown runs after EACH test
    deinit {
        // Clean up resources (called automatically)
    }

    @Test("Test description in plain English")
    func testFeatureBehavior() async throws {
        // Test implementation
    }
}
```

### The AAA Pattern (Arrange-Act-Assert)

**CRITICAL: All tests MUST follow the AAA pattern for clarity.**

```swift
@Test("Service initializes with default configuration")
func testInitialization() async throws {
    // ========================================
    // ARRANGE: Set up test data and preconditions
    // ========================================
    try await TestHelpers.setupFreshDatabase()
    let service = SQLCipherService.shared

    // ========================================
    // ACT: Perform the operation being tested
    // ========================================
    try await service.initialize()

    // ========================================
    // ASSERT: Verify the expected outcome
    // ========================================
    let version = try await service.getSchemaVersion()
    #expect(version == 2)  // Current schema version
}
```

**Why AAA pattern?**
- Makes test intent immediately clear
- Easy to understand what's being tested
- Simplifies debugging when tests fail
- Standard pattern across the industry

### Assertions with `#expect()`

Swift Testing uses `#expect()` macro instead of XCTest's `XCTAssert` functions.

```swift
// Basic equality
#expect(actual == expected)
#expect(result == "Hello, World!")

// Boolean conditions
#expect(isValid)
#expect(!isError)

// Comparisons
#expect(count > 0)
#expect(age >= 18)

// Optional unwrapping
#expect(optionalValue != nil)

// Collection assertions
#expect(array.isEmpty)
#expect(array.count == 5)
#expect(array.contains("item"))

// Throws validation
#expect(throws: DatabaseError.self) {
    try service.invalidOperation()
}

// Async operations
let result = try await service.fetchData()
#expect(result.count > 0)
```

### Nested Test Suites

**Group related tests using nested `@Suite` attributes:**

```swift
@Suite("SQLCipherService Tests")
struct SQLCipherServiceTests {

    @Suite("Initialization & Encryption")
    struct InitializationTests {

        @Test("Service initializes successfully")
        func testInitialization() async throws {
            // ...
        }

        @Test("Encryption key is generated and stored")
        func testEncryptionKeyGeneration() async throws {
            // ...
        }
    }

    @Suite("CRUD Operations")
    struct CRUDTests {

        @Test("Insert database config stores all fields")
        func testInsertConfig() async throws {
            // ...
        }

        @Test("Update config changes all fields")
        func testUpdateConfig() async throws {
            // ...
        }
    }
}
```

**Benefits:**
- Clear test organization visible in Xcode Test Navigator
- Easy to run subset of tests (run only "CRUD Operations" suite)
- Self-documenting test structure

### Test Tags

**Use tags to categorize and filter tests:**

```swift
extension Tag {
    @Tag static var database: Tag
    @Tag static var encryption: Tag
    @Tag static var slow: Tag
}

@Test("Encryption key persists across reinitializations",
      .tags(.encryption, .database))
func testEncryptionKeyPersistence() async throws {
    // ...
}
```

**Run tests by tag:**
```bash
# Run only database tests
xcodebuild test -only-testing:EdgeStudioUnitTests -testPlan DatabaseTests

# Skip slow tests during development
xcodebuild test -skip-testing:EdgeStudioUnitTests/SlowTests
```

### Testing Async Code

Swift Testing has native async/await support:

```swift
@Test("Async operation completes successfully")
func testAsyncOperation() async throws {
    // Mark test function as async
    let service = MyService()

    // Await async operations directly
    let result = try await service.fetchData()

    // Assert on result
    #expect(result.count > 0)
}

@Test("Multiple concurrent operations succeed")
func testConcurrentOperations() async throws {
    // Use TaskGroup for concurrent testing
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
```

### Test Serialization

**By default, Swift Testing runs tests in parallel for speed.**

For tests that share state (like singleton actors), use `.serialized`:

```swift
@Suite("SQLCipher Service Tests", .serialized)
struct SQLCipherServiceTests {
    // All tests in this suite run sequentially
    // Prevents race conditions with shared SQLCipherService.shared
}
```

**When to use `.serialized`:**
- Tests that use singleton instances (actors, managers)
- Tests that modify shared file system state
- Tests that require specific execution order

**Prefer parallel execution when possible** - it's much faster.

### Test Isolation and Sandboxing

**CRITICAL: Tests MUST NEVER touch production data.**

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

    // ... rest of method
}
```

**Test paths (macOS sandboxed):**
- Production: `~/Library/Application Support/ditto_cache`
- Unit tests: `~/Library/Application Support/ditto_cache_unit_test`
- UI tests: `~/Library/Application Support/ditto_cache_test`

**Why runtime detection instead of compile-time flags?**
- Works reliably with macOS app sandboxing
- No TESTING flag needed in Debug builds
- Normal development runs use production paths
- Tests automatically use isolated paths

### Test Helper Functions

**Use `TestHelpers.swift` for common test setup:**

```swift
enum TestHelpers {

    /// Creates a fresh, initialized test database
    static func setupFreshDatabase() async throws {
        try await setupUninitializedDatabase()
        let service = SQLCipherService.shared
        try await service.initialize()
    }

    /// Creates a clean test database directory (uninitialized)
    static func setupUninitializedDatabase() async throws {
        let service = SQLCipherService.shared
        await service.resetForTesting()

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
        let dbDir = appSupportURL.appendingPathComponent("ditto_cache_unit_test")

        // Remove existing test database
        if fileManager.fileExists(atPath: dbDir.path) {
            try? fileManager.removeItem(at: dbDir)
        }

        // Create fresh directory
        try fileManager.createDirectory(at: dbDir,
                                       withIntermediateDirectories: true)
    }

    /// Generate unique test ID
    static func uniqueTestId(prefix: String = "test") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
}
```

**When to use each helper:**

```swift
// Use setupFreshDatabase() when you need a working database
@Test("Query executes successfully")
func testQueryExecution() async throws {
    try await TestHelpers.setupFreshDatabase()  // Initialized DB
    let service = SQLCipherService.shared

    let configs = try await service.getAllDatabaseConfigs()
    #expect(configs.isEmpty)  // Fresh database
}

// Use setupUninitializedDatabase() to test initialization itself
@Test("Initialize creates schema")
func testInitialization() async throws {
    try await TestHelpers.setupUninitializedDatabase()  // No schema yet
    let service = SQLCipherService.shared

    try await service.initialize()  // Test initialization

    let version = try await service.getSchemaVersion()
    #expect(version == 2)
}
```

### Complete Unit Test Example

```swift
import Testing
@testable import Edge_Debug_Helper

@Suite("SQLCipherService Tests", .serialized)
struct SQLCipherServiceTests {

    @Suite("Initialization & Encryption")
    struct InitializationTests {

        @Test("Service initializes successfully", .tags(.database, .encryption))
        func testInitialization() async throws {
            // ARRANGE
            try await TestHelpers.setupUninitializedDatabase()
            let service = SQLCipherService.shared

            // ACT
            try await service.initialize()

            // ASSERT
            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.isEmpty)  // Fresh database, no configs yet
        }

        @Test("Encryption key is generated and stored", .tags(.encryption))
        func testEncryptionKeyGeneration() async throws {
            // ARRANGE
            try await TestHelpers.setupFreshDatabase()

            // ACT
            let dbDir = TestConfiguration.unitTestDatabasePath
            let keyFilePath = URL(fileURLWithPath: dbDir)
                .appendingPathComponent("sqlcipher.key")

            // ASSERT
            let fileManager = FileManager.default
            #expect(fileManager.fileExists(atPath: keyFilePath.path))

            let keyData = try Data(contentsOf: keyFilePath)
            let key = String(data: keyData, encoding: .utf8)
            #expect(key?.count == 64)  // 256-bit hex key
        }
    }

    @Suite("CRUD Operations")
    struct CRUDTests {

        @Test("Insert database config stores all fields", .tags(.database))
        func testInsertConfig() async throws {
            // ARRANGE
            try await TestHelpers.setupFreshDatabase()
            let service = SQLCipherService.shared

            let config = SQLCipherService.DatabaseConfigRow(
                _id: TestHelpers.uniqueTestId(),
                name: "Test Database",
                databaseId: "db-test-123",
                mode: "server",
                allowUntrustedCerts: false,
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: false,
                isCloudSyncEnabled: true,
                token: "my-token",
                authUrl: "https://auth.example.com",
                websocketUrl: "wss://sync.example.com",
                httpApiUrl: "https://api.example.com",
                httpApiKey: "api-key-123",
                secretKey: ""
            )

            // ACT
            try await service.insertDatabaseConfig(config)

            // ASSERT
            let configs = try await service.getAllDatabaseConfigs()
            #expect(configs.count == 1)
            #expect(configs[0]._id == config._id)
            #expect(configs[0].name == "Test Database")
            #expect(configs[0].token == "my-token")
        }
    }
}
```

---

## Mandatory Testing Requirements for New Code

**CRITICAL: The following rules are MANDATORY for all code contributions:**

### 1. All New Code MUST Have Tests

- ✅ New service methods → unit tests required
- ✅ New repository methods → unit tests required
- ✅ New view models → unit tests required
- ✅ New utilities/helpers → unit tests required
- ✅ Bug fixes → regression test required
- ❌ No tests → Pull request will be rejected

### 2. Test Coverage Requirements

**Minimum coverage by component type:**

| Component Type | Minimum Coverage | Rationale |
|---------------|------------------|-----------|
| **Services** (SQLCipherService, QueryService) | 80% | Critical business logic |
| **Repositories** (all repositories) | 70% | Data access layer |
| **Utilities** (DQL generators, parsers) | 75% | Complex logic |
| **View Models** | 60% | UI state management |
| **Models** (data classes) | 50% | Getters/setters, simple logic |

**Current project coverage: 15.96%**
- SQLCipherService: 62.19% coverage ✅
- Target: Reach 50% overall coverage (Phase 4 in progress)

### 3. Tests Must Follow Standards

- ✅ Use Swift Testing framework (`import Testing`)
- ✅ Follow AAA pattern (Arrange-Act-Assert)
- ✅ Include descriptive test names
- ✅ Use `#expect()` assertions with meaningful messages
- ✅ Test isolation (use `TestHelpers.setupFreshDatabase()`)
- ✅ Clean up resources in `deinit`
- ❌ No skipped tests (`.enabled(if: false)`)
- ❌ No commented-out tests
- ❌ No `print()` debugging (use proper logging)

### 4. Tests Must Pass Before Merging

```bash
# Run all tests before committing
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64"

# Check coverage
./scripts/generate_coverage_report.sh
```

**Pre-push validation:**
- All tests pass ✅
- Coverage has not decreased ✅
- No new SwiftLint warnings ✅

### 5. Test Documentation

**Every test file MUST include:**

```swift
/// Comprehensive test suite for ComponentName
///
/// Tests cover:
/// - Initialization and configuration
/// - Core functionality (CRUD operations, business logic)
/// - Error handling and edge cases
/// - Async operations and concurrency
///
/// Each test uses a fresh test database with proper isolation.
/// Target: 80% code coverage for this component.
@Suite("Component Name", .serialized)
struct ComponentNameTests {
    // ...
}
```

### 6. What NOT to Test

**Don't waste time testing:**
- Simple getters/setters with no logic
- Third-party library internals (e.g., Ditto SDK)
- Auto-generated code (e.g., `FontAwesomeIcons.swift`)
- SwiftUI view layouts (use UI tests instead)

**DO test:**
- Business logic and algorithms
- Data transformations
- Error handling
- Boundary conditions
- Integration between components

---

## Test Coverage and Reporting

### Running Coverage Reports

**Generate coverage report:**

```bash
# Run tests with coverage tracking
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
```

### Coverage Threshold Enforcement

**Pre-push hook** automatically enforces 50% minimum coverage:

```bash
# Enable pre-push hook
chmod +x .git/hooks/pre-push

# Hook runs automatically before every push
git push origin main

# Bypass once (emergency only)
git push --no-verify
```

### Viewing Coverage in Xcode

1. Open `SwiftUI/TestResults.xcresult` in Xcode
2. Navigate to **Coverage** tab
3. Browse per-file and per-function coverage
4. Click on files to see line-by-line coverage highlighting

**Green lines** = covered by tests
**Red lines** = not covered by tests

### Coverage Best Practices

- **Focus on critical paths first**: Security, data storage, authentication
- **Don't chase 100% coverage**: 80-90% is realistic and valuable
- **Test behavior, not implementation**: Don't test private methods directly
- **Use coverage to find gaps**: Low coverage indicates missing test cases

---

### Running Tests After Changes

**CRITICAL: Always run tests after making changes to validate the app still works.**

#### Run All Tests

```bash
# Run all tests (unit + integration + UI tests)
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64"

# Or run via Xcode: Product → Test (⌘U)

# Or use the UI test runner script
cd SwiftUI
./run_ui_tests.sh
```

#### Run Specific Test Targets

```bash
# Run only unit tests (fast - <1 second)
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioUnitTests

# Run only integration tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioIntegrationTests

# Run only UI tests (slower - requires app launch)
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioUITests
```

#### Run Specific Test Suite or Test

```bash
# Run a specific test suite
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioUnitTests/SQLCipherServiceTests

# Run a single test
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64" \
                -only-testing:EdgeStudioUnitTests/SQLCipherServiceTests/testInitialization
```

#### Test Output

**Successful test run:**
```
Test Suite 'All tests' passed at 2026-02-17 10:30:15.123.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.892 (0.952) seconds
```

**Failed test:**
```
❌ Test testInsertConfig() failed: Expected 1 config, got 0
   File: SQLCipherServiceTests.swift:185
   Assertion: #expect(configs.count == 1)
```

---

## UI Testing with XCTest

**UI tests use XCTest framework (NOT Swift Testing)** because XCUITest has no Swift Testing alternative.

UI tests validate user workflows, visual layouts, and end-to-end functionality that unit tests cannot cover:
- App launches successfully
- User can navigate between views
- Forms accept input correctly
- Visual layouts render properly (using screenshots)
- Database selection and query execution flows work end-to-end

**UI tests are slower than unit tests** (require app launch, window activation, UI rendering), so:
- Use unit tests for business logic
- Use UI tests for user workflows and visual validation

### Overview

Comprehensive UI tests validate:
- App launches successfully
- Database list screen displays correctly
- Database selection opens MainStudioView
- All navigation menu items (Subscriptions, Collections, Observer, Ditto Tools) work
- Each sidebar and detail view renders properly

**Note:** Navigation tests will skip if no databases are configured (expected behavior).

**Test Files:**
- `Edge Debugg Helper UITests/Ditto_Edge_StudioUITests.swift` - Main UI test suite
- `SwiftUI/run_ui_tests.sh` - Automated test runner script

### Screenshot-Based Visual Validation

**CRITICAL: For visual layout bugs, screenshots are REQUIRED for validation.**

UI tests can capture screenshots using `XCUIApplication().screenshot()` to validate visual behavior that cannot be detected by compilation or element existence checks alone.

**When to use screenshot validation:**
- Layout issues (views not appearing, overlapping, or positioned incorrectly)
- NavigationSplitView + Inspector layout conflicts
- Split view sizing problems
- Any bug that requires "seeing" the UI to validate

**How to implement screenshot-based UI tests:**

```swift
import XCTest

class VisualLayoutTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testNavigationSplitViewInspectorLayout() {
        // 1. Capture initial state
        let screenshot1 = app.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01-initial-state"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // 2. Navigate to Collections
        app.buttons["Collections"].tap()
        sleep(1) // Allow layout to settle

        let screenshot2 = app.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02-collections-selected"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // 3. Open inspector
        app.buttons["Toggle Inspector"].tap()
        sleep(1) // Allow layout to settle

        let screenshot3 = app.screenshot()
        let attachment3 = XCTAttachment(screenshot: screenshot3)
        attachment3.name = "03-inspector-opened"
        attachment3.lifetime = .keepAlways
        add(attachment3)

        // 4. Validate sidebar still visible (element check + visual screenshot)
        XCTAssertTrue(app.buttons["Subscriptions"].exists, "Sidebar should remain visible")
        XCTAssertTrue(app.buttons["Collections"].exists, "Sidebar should remain visible")
        XCTAssertTrue(app.buttons["Observer"].exists, "Sidebar should remain visible")

        // Screenshot serves as visual proof of layout correctness
    }
}
```

**Viewing screenshots:**
- Screenshots are attached to test results in Xcode Test Navigator
- Click on test result → View attachments
- Screenshots saved with `.lifetime = .keepAlways` are always available
- Use screenshots to debug visual issues that aren't caught by element assertions

**Best practices:**
- Always capture screenshots AFTER allowing layout to settle (`sleep(1)`)
- Name screenshots descriptively (e.g., "03-inspector-opened-sidebar-visible")
- Use `.lifetime = .keepAlways` for debugging, `.deleteOnSuccess` for CI
- Combine element assertions with screenshots for complete validation
- Create feedback loops: Test → Screenshot → Analyze → Fix → Test again

**Reference:**
- Apple Documentation: https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot
- XCTAttachment: https://developer.apple.com/documentation/xctest/xctattachment

### macOS XCUITest Requirements and Setup

**CRITICAL: XCUITest on macOS requires specific system permissions and configuration to work properly.**

#### Accessibility Permissions (REQUIRED)

XCUITest uses the macOS Accessibility framework to control and inspect UI elements. Without proper permissions, tests will fail because:
- App windows won't come to the foreground
- UI elements will be invisible to the test framework (zero buttons, zero controls detected)
- `app.activate()` will fail silently

**Required Accessibility Permissions:**

Add these to **System Settings → Privacy & Security → Accessibility:**

1. **Xcode Helper** (Primary - Required):
   ```
   /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/Xcode Helper.app
   ```

   Or for Xcode beta/RC:
   ```
   /Applications/Xcode RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/Xcode Helper.app
   ```

2. **xctest** (Also Required):
   ```
   /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest
   ```

3. **Xcode itself** (Optional but recommended):
   ```
   /Applications/Xcode.app
   ```

**How to Add:**
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **lock icon** (requires password)
3. Click **"+"** button
4. Press **⌘⇧G** (Go to Folder)
5. Paste path and click **Go**
6. Select the app/executable and click **Open**

**Symptoms of Missing Permissions:**
- Tests launch app but window stays in Dock (doesn't come to foreground)
- UI hierarchy appears empty (0 buttons, 0 controls)
- Tests fail with "element not found" even though app is running
- Manual click on Dock icon makes tests pass

#### Test Database Isolation

**CRITICAL: UI tests use a separate database directory to avoid contaminating production data.**

When tests run with the `UI-TESTING` launch argument:
- Production database path: `~/Library/Application Support/ditto_appconfig`
- Test database path: `~/Library/Application Support/ditto_appconfig_test`
- Test directory is **cleared on each test run** for consistent state

**Test Database Configuration:**

Tests load databases from `SwiftUI/Edge Debug Helper/testDatabaseConfig.plist` (gitignored).

**To set up test databases:**
1. Copy `testDatabaseConfig.plist.example` to `testDatabaseConfig.plist`
2. Add real test credentials for each auth mode (online playground, offline playground, shared key)
3. Tests will automatically load these databases when launched

**Implementation Details:**
- `DittoManager.initializeStore()` detects `UI-TESTING` argument
- Uses `ditto_appconfig_test` directory for test runs
- `AppState.loadTestDatabases()` loads configs from plist file
- Each test run starts with a fresh, clean database state

#### macOS Window Activation Issues

**Known macOS Bug (macOS 11+):**

Starting with macOS 11 Big Sur, Apple introduced a regression where `NSRunningApplication.activate()` doesn't properly bring all windows to the foreground. The `NSApplicationActivateAllWindows` flag is not honored.

**Impact on XCUITest:**
- `XCUIApplication.activate()` uses `NSRunningApplication` under the hood
- So it inherits this macOS system bug
- Only the frontmost window comes forward, not all windows
- This affects both AppleScript activation AND NSRunningApplication

**Workaround in Tests:**

The test setUp implements multi-step activation:
1. Launch app
2. Wait for window to appear using `waitForExistence()`
3. Call `app.activate()`
4. Click the window element to force focus
5. Verify UI hierarchy is accessible (button count > 0)
6. Retry activation if needed (up to 5 attempts)

**References:**
- [Michael Tsai: Activating Applications via AppleScript](https://mjtsai.com/blog/2022/05/31/activating-applications-via-applescript/)
- [NSRunningApplication activate() issues since macOS 11](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:))

#### Multi-Monitor and Multi-App Environments

**Issue:** With many apps open or multi-monitor setups, the test app may launch but not become the active window.

**Solution:** Tests must:
1. Call `app.activate()` immediately after launch
2. Click the window element explicitly
3. Reactivate after any `tap()` operation that changes views
4. Add delays (`sleep()`) after activations to allow window manager to respond

**Example:**
```swift
// After tapping an element that transitions to a new view
firstAppCard.tap()
app.activate()  // Reactivate to maintain focus
sleep(1)
let window = app.windows.firstMatch
if window.exists {
    window.click()  // Force window to front
    sleep(1)
}
```

### UI Testing Best Practices (Learned from testSelectFirstApp Refactor)

**CRITICAL: These patterns are based on Apple's official recommendations and industry best practices.**

#### Data Setup Pattern (Production-Ready)

✅ **Your current implementation is correct:**
- Load test data in `AppState.init()` when `UI-TESTING` launch argument is detected
- Use `testDatabaseConfig.plist` for test database configurations
- Repository observer pattern automatically updates SwiftUI `@Published` properties
- No manual data loading in test setUp() needed - app handles it

**Implementation:**
```swift
// In AppState.init()
if ProcessInfo.processInfo.arguments.contains("UI-TESTING") {
    Task {
        await AppState.loadTestDatabases()
    }
}

// In test setUp
app.launchArguments = ["UI-TESTING"]
app.launch()
```

#### Waiting for Async Operations

✅ **Prefer `waitForExistence(timeout:)` over `sleep()`**

```swift
// ✅ CORRECT - Returns immediately if element exists
let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
guard navigationPicker.waitForExistence(timeout: 10) else {
    XCTFail("Navigation picker did not appear")
    return
}

// ⚠️ Use sleep() ONLY for animations/transitions
button.tap()
sleep(1)  // Allow animation to complete
```

**When to use each:**
- `waitForExistence()` - Element appearance, loading states, async data
- `sleep()` - UI animations, layout transitions, window activation delays

**For Ditto Operations:**
- Wait for **resulting UI elements** (e.g., navigation picker), not internal state
- Use 30+ second timeouts for slow operations (Ditto connections)

#### Dynamic Validation from Test Config

✅ **Read testDatabaseConfig.plist to get expected counts**

```swift
// Helper method in test file
private func getExpectedDatabaseCount() -> Int? {
    guard let appBundle = Bundle(identifier: "io.ditto.EdgeStudio"),
          let path = appBundle.path(forResource: "testDatabaseConfig", ofType: "plist") else {
        return nil
    }

    let data = try? Data(contentsOf: URL(fileURLWithPath: path))
    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

    return (plist?["databases"] as? [[String: Any]])?.count
}

// In test
let expectedCount = getExpectedDatabaseCount()
XCTAssertEqual(actualDatabaseCount, expectedCount, "Database count mismatch")
```

**Why this is better:**
- No hardcoded expectations - adapts to changing test config
- Validates data loading pipeline end-to-end
- Catches discrepancies between config and UI

#### Accessibility Identifiers

✅ **Add to all testable elements:**

```swift
// In SwiftUI views
Button("Sync") { /* action */ }
    .accessibilityIdentifier("SyncButton")

Picker("", selection: $selectedTab) { /* options */ }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("SyncTabPicker")
```

**Best Practices:**
- ✅ Use **descriptive, stable names** ("SyncButton" not "button1")
- ✅ Apply to buttons, pickers, tabs, containers
- ✅ Access in tests via `app.buttons["SyncButton"]`
- ✅ Never rely on localized text - always use accessibility IDs

#### Alert Dialog Checks

✅ **Always check for alerts on failure:**

```swift
guard element.waitForExistence(timeout: 10) else {
    // Check for alerts before failing
    if app.alerts.count > 0 {
        let alert = app.alerts.firstMatch
        XCTFail("Element not found - Alert detected: \(alert.label)")
    } else {
        XCTFail("Element not found")
    }
    throw XCTSkip("Test cannot continue")
}
```

**Why this is critical:**
- Alert dialogs indicate app errors (invalid credentials, connection failures)
- Provides actionable debugging info (alert message)
- Prevents confusing test failures ("element not found" when real issue is auth error)

#### Screenshot Best Practices

✅ **Use screenshots for visual validation:**

```swift
let screenshot = app.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.name = "02-main-studio-loaded"
attachment.lifetime = .deleteOnSuccess  // CI-friendly
add(attachment)
```

**Screenshot Lifetime:**
- `.deleteOnSuccess` - For CI/automated testing (saves space)
- `.keepAlways` - For debugging failing tests only

**When to capture:**
- ✅ Every major state transition (list → detail → list)
- ✅ After validation steps (to prove UI rendered correctly)
- ✅ On test failure (always use `.keepAlways` for failure screenshots)
- ✅ Always `sleep(1)` before screenshot to allow animations to settle

**Naming convention:**
- Use descriptive, sequential names: `"01-initial-state"`, `"02-after-action"`, `"FAIL-error-state"`
- Prefix failures with `"FAIL-"` for easy identification

#### Test Structure (AAA Pattern)

✅ **Use Arrange-Act-Assert pattern with clear sections:**

```swift
func testFeature() throws {
    // ========================================
    // ARRANGE: Set up preconditions
    // ========================================
    waitForAppToFinishLoading()
    let expectedCount = getExpectedDatabaseCount()

    // ========================================
    // ACT: Perform the action being tested
    // ========================================
    firstAppCard.tap()

    // ========================================
    // ASSERT: Verify the expected outcome
    // ========================================
    XCTAssertTrue(navigationPicker.waitForExistence(timeout: 30))
    XCTAssertEqual(actualCount, expectedCount)
}
```

**Why AAA pattern:**
- Clear separation of test phases
- Easy to understand test intent
- Easier to debug when tests fail

#### Comprehensive Element Validation

✅ **Validate multiple aspects of UI state:**

```swift
// Don't just check picker exists
XCTAssertTrue(syncTabPicker.exists)

// ALSO check content is correct
let peersListText = syncTabPicker.staticTexts["Peers List"]
XCTAssertTrue(peersListText.exists, "'Peers List' text should be visible")
```

**Why this is better:**
- Catches partial rendering bugs (element exists but content missing)
- Validates actual user-visible state, not just internal UI hierarchy
- More thorough validation = fewer production bugs

#### Error Messages That Help Debug

✅ **Write actionable error messages:**

```swift
// ❌ BAD
XCTAssertTrue(button.exists, "Button not found")

// ✅ GOOD
XCTAssertTrue(
    button.waitForExistence(timeout: 5),
    """
    Sync button not found in MainStudioView toolbar.

    MainStudioView loaded but toolbar buttons are missing.
    Check that .accessibilityIdentifier("SyncButton") was added to syncToolbarButton().
    Screenshot saved: 'FAIL-sync-button-not-found'
    """
)
```

**Good error messages include:**
- What failed (specific element and location)
- What was expected vs actual
- How to fix it (which file, what to check)
- Reference to screenshots for visual debugging

#### Example: Complete Test Flow

```swift
func testSelectFirstApp() throws {
    // ARRANGE: Wait and validate initial state
    waitForAppToFinishLoading()
    let expectedCount = getExpectedDatabaseCount()
    XCTAssertTrue(addDatabaseButton.waitForExistence(timeout: 5))

    // ASSERT: Validate database list loaded correctly
    guard databaseList.waitForExistence(timeout: 10) else {
        if app.alerts.count > 0 {
            XCTFail("Alert detected: \(app.alerts.firstMatch.label)")
        }
        throw XCTSkip("No database list")
    }

    let actualCount = databaseList.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")).count
    XCTAssertEqual(actualCount, expectedCount, "Database count mismatch")

    // Screenshot for visual validation
    let screenshot1 = app.screenshot()
    let attachment1 = XCTAttachment(screenshot: screenshot1)
    attachment1.name = "01-database-list"
    attachment1.lifetime = .deleteOnSuccess
    add(attachment1)

    // ACT: Select first database (note: identifier uses legacy "AppCard_" naming)
    let firstCard = databaseList.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")).firstMatch
    firstCard.tap()

    // ASSERT: Validate MainStudioView loaded
    let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
    guard navigationPicker.waitForExistence(timeout: 30) else {
        if app.alerts.count > 0 {
            XCTFail("MainStudioView failed to load - Alert: \(app.alerts.firstMatch.label)")
        }
        throw XCTSkip("MainStudioView not loaded")
    }

    // Validate UI elements
    XCTAssertTrue(app.buttons["SyncButton"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["CloseButton"].waitForExistence(timeout: 5))

    let syncTabPicker = app.segmentedControls["SyncTabPicker"]
    XCTAssertTrue(syncTabPicker.waitForExistence(timeout: 5))
    XCTAssertTrue(syncTabPicker.staticTexts["Peers List"].exists)

    // ACT: Close MainStudioView
    app.buttons["CloseButton"].tap()
    sleep(2)

    // ASSERT: Validate returned to list with same database count
    XCTAssertTrue(addDatabaseButton.waitForExistence(timeout: 5))
    let finalCount = databaseList.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")).count  // Legacy identifier
    XCTAssertEqual(finalCount, expectedCount, "Database count changed")
}
```

#### Reference Documentation

- [Apple: waitForExistence(timeout:)](https://developer.apple.com/documentation/xctest/xcuielement/2879412-waitforexistence)
- [Apple: accessibility(identifier:)](https://developer.apple.com/documentation/swiftui/view/accessibility(identifier:))
- [Apple: XCUIScreenshot](https://developer.apple.com/documentation/xctest/xcuiscreenshot)
- [Waiting in XCTest | Masilotti.com](https://masilotti.com/xctest-waiting/)
- [Configuring UI tests with launch arguments](https://www.polpiella.dev/configuring-ui-tests-with-launch-arguments)

### Established UI Testing Patterns (2026-02)

**CRITICAL: These patterns were established through comprehensive testing and are required for reliable UI tests.**

#### Pattern 1: Database Setup via Form Automation

**Problem:** Programmatic database loading during app initialization is unreliable due to sandboxing, race conditions, and timing issues.

**Solution:** Use XCUITest to automate the actual UI workflow (Add Database button → fill form → save).

**Implementation:**

```swift
/// Reads testDatabaseConfig.plist and adds all databases via UI automation
@MainActor
private func addDatabasesFromPlist() throws {
    guard let appBundle = Bundle(identifier: "io.ditto.EdgeStudio"),
          let path = appBundle.path(forResource: "testDatabaseConfig", ofType: "plist") else {
        throw XCTSkip("testDatabaseConfig.plist not found")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

    guard let databases = plist?["databases"] as? [[String: Any]] else {
        throw XCTSkip("testDatabaseConfig.plist missing 'databases' array")
    }

    print("📋 Found \(databases.count) database(s) to add")

    for (index, config) in databases.enumerated() {
        let name = config["name"] as? String ?? "Unknown"
        print("\n📦 Adding database \(index + 1)/\(databases.count): '\(name)'")
        try addSingleDatabase(config: config)
    }

    print("\n✅ All databases added successfully")
}

/// Adds a single database by automating the DatabaseEditorView form
@MainActor
private func addSingleDatabase(config: [String: Any]) throws {
    let name = config["name"] as? String ?? ""
    let appId = config["appId"] as? String ?? ""
    let authToken = config["authToken"] as? String ?? ""

    // 1. Tap Add Database button (use .firstMatch for nested buttons)
    let addButton = app.buttons["AddDatabaseButton"].firstMatch
    guard addButton.waitForExistence(timeout: 5) else {
        XCTFail("Add Database button not found")
        return
    }
    addButton.tap()
    sleep(2)  // Wait for sheet animation

    // 2. Wait for form (use text field, NOT picker - see Pattern 2)
    let nameField = app.textFields["NameTextField"]
    guard nameField.waitForExistence(timeout: 10) else {
        XCTFail("Form not found")
        return
    }

    // 3. Fill required fields
    nameField.tap()
    sleep(1)  // CRITICAL: Allow focus to register
    nameField.typeText(name)

    let appIdField = app.textFields["AppIdTextField"]
    appIdField.tap()
    sleep(1)
    appIdField.typeText(appId)

    let authTokenField = app.textFields["AuthTokenTextField"]
    authTokenField.tap()
    sleep(1)
    authTokenField.typeText(authToken)

    // 4. Save
    let saveButton = app.buttons["SaveButton"]
    saveButton.tap()
    sleep(2)  // Wait for save

    // 5. Wait for sheet to dismiss (active monitoring)
    let sheets = app.sheets
    if sheets.count > 0 {
        for _ in 0..<10 {
            if !sheets.firstMatch.exists { break }
            usleep(500000)  // 0.5s
        }
    }
    sleep(2)  // Additional wait for database to save

    // 6. Validate database appeared
    let cardIdentifier = "AppCard_\(name)"
    let card = app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@", cardIdentifier))
        .firstMatch

    guard card.waitForExistence(timeout: 20) else {
        XCTFail("Database '\(name)' not added")
        return
    }

    print("✅ Database '\(name)' added successfully")
}
```

**Usage in tests:**

```swift
func testFeature() throws {
    waitForAppToFinishLoading(timeout: 20)

    // Add databases via UI automation (required for fresh sandbox)
    try addDatabasesFromPlist()

    // Now databases are available for testing
    let firstCard = app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'"))  // Legacy identifier
        .firstMatch
    firstCard.tap()

    // ... rest of test
}
```

**Benefits:**
- ✅ Works reliably with sandboxing
- ✅ Tests the real user experience
- ✅ Easy to debug visually
- ✅ No database initialization changes needed

**Documentation:** See `ADDBUTTON_FIRSTMATCH_FIX.md`, `SHEET_TIMING_FIX.md`, `PICKER_WORKAROUND_FIX.md`, `SHEET_DISMISS_TIMING_FIX.md`

#### Pattern 2: SwiftUI Picker Accessibility Issues

**CRITICAL LIMITATION: SwiftUI Pickers with `.pickerStyle(.segmented)` DO NOT expose as segmented controls in XCUITest.**

**Problem:**
```swift
// This WILL FAIL - picker not accessible
let picker = app.segmentedControls["MyPicker"]
guard picker.waitForExistence(timeout: 10) else {
    // This will always timeout
}
```

**Why it fails:**
- SwiftUI Picker implementation doesn't expose accessibility correctly
- `app.segmentedControls["MyPicker"]` returns empty query
- This affects ALL SwiftUI Pickers on macOS, regardless of identifiers added

**Solution: Use Alternative Validation Elements**

**Example 1: AuthModePicker in DatabaseEditorView**
```swift
// ❌ DOESN'T WORK
let modePicker = app.segmentedControls["AuthModePicker"]

// ✅ WORKS - Validate form readiness with text field instead
let nameField = app.textFields["NameTextField"]
guard nameField.waitForExistence(timeout: 10) else {
    XCTFail("Form not found")
    return
}
// Form is ready, mode defaults to first option
```

**Example 2: NavigationSegmentedPicker in MainStudioView**
```swift
// ❌ DOESN'T WORK
let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]

// ✅ WORKS - Validate MainStudioView loaded with toolbar button
let closeButton = app.buttons["CloseButton"].firstMatch
guard closeButton.waitForExistence(timeout: 60) else {
    XCTFail("MainStudioView not loaded")
    return
}
```

**Example 3: SyncTabPicker in MainStudioView**
```swift
// ❌ DOESN'T WORK
let syncTabPicker = app.segmentedControls["SyncTabPicker"]

// ✅ WORKS - Validate sync detail view with static text
let connectedPeers = app.staticTexts["Connected Peers"]
guard connectedPeers.waitForExistence(timeout: 10) else {
    XCTFail("Sync detail view not loaded")
    return
}
```

**Making Pickers Testable:**

For pickers where you need to interact with segments (not just validate they loaded), you must make them accessible:

**Option 1: Add Accessibility to Picker Segments** (Partial solution)
```swift
// In SwiftUI view
Picker("", selection: $selectedItem) {
    ForEach(items) { item in
        item.image
            .tag(item)
            .accessibilityIdentifier("PickerItem_\(item.name)")
            .accessibilityLabel(item.name)
    }
}
```

⚠️ **NOTE:** This only works if picker segments use **text labels**. Pickers with **SF Symbol images** (no text) remain inaccessible even with identifiers.

**Option 2: Use Text Labels** (Recommended)
```swift
// Replace SF Symbol images with text
Picker("", selection: $selectedItem) {
    ForEach(items) { item in
        Text(item.name)  // Use text instead of image
            .tag(item)
            .accessibilityIdentifier("PickerItem_\(item.name)")
    }
}
```

**Option 3: Custom Button-Based Control** (Most reliable)
```swift
// Replace Picker with buttons
HStack(spacing: 0) {
    ForEach(items) { item in
        Button(action: { selectedItem = item }) {
            item.image
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("PickerItem_\(item.name)")
    }
}
```

**Tests should handle inaccessible pickers gracefully:**

```swift
let navigationButton = app.buttons["NavigationItem_Collections"]

guard navigationButton.waitForExistence(timeout: 2) else {
    print("⚠️ Navigation button not accessible")
    print("   Picker uses SF Symbol images which don't expose to XCUITest")
    throw XCTSkip("""
        Navigation requires picker segments to be accessible.
        Update picker to use Text labels or custom buttons.
        """)
}
```

#### Pattern 3: Nested Button Structures (.firstMatch)

**Problem:** FontAwesomeText and other custom button labels create nested button hierarchies.

```
↳Button, identifier: 'AddDatabaseButton', label: ''
  ↳Button, identifier: 'AddDatabaseButton', label: ''  (nested child)
```

**Solution:** Always use `.firstMatch` for buttons with custom labels.

```swift
// ❌ FAILS - Multiple matching elements
let button = app.buttons["AddDatabaseButton"]
button.tap()  // Error: Multiple matching elements found

// ✅ WORKS - Gets the parent button
let button = app.buttons["AddDatabaseButton"].firstMatch
button.tap()
```

**Apply to ALL buttons with custom labels:**
```swift
let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
let closeButton = app.buttons["CloseButton"].firstMatch
let syncButton = app.buttons["SyncButton"].firstMatch
```

**Note:** The "AddDatabaseButton" button opens the database editor (DatabaseEditorView) for adding new database configurations.

#### Pattern 4: Timing Patterns

**CRITICAL: Proper timing is essential for reliable tests.**

**Rule 1: Use `sleep()` after `tap()` for animations**
```swift
button.tap()
sleep(1)  // Wait for animation to complete
```

**Rule 2: Use `waitForExistence()` for async content**
```swift
guard element.waitForExistence(timeout: 10) else {
    XCTFail("Element did not appear")
    return
}
```

**Rule 3: macOS Sheet Timing**
```swift
// After tapping button that opens sheet
button.tap()
sleep(2)  // Wait for sheet animation

// Wait for sheet content to render
let sheets = app.sheets
sleep(2)  // Additional wait for content rendering
```

**Rule 4: Database Save Operations**
```swift
saveButton.tap()
sleep(2)  // Initial wait for tap to register

// Actively monitor sheet dismissal
for _ in 0..<10 {
    if !sheet.exists { break }
    usleep(500000)  // Poll every 0.5s
}

sleep(2)  // Wait for database save + UI update
```

**Rule 5: MainStudioView Initialization (Slow!)**
```swift
// MainStudioView initialization is SLOW (Ditto connections, subscriptions, observers)
let closeButton = app.buttons["CloseButton"].firstMatch
guard closeButton.waitForExistence(timeout: 60) else {  // 60s!
    XCTFail("MainStudioView did not load")
    return
}
```

**Documentation:** See `SHEET_TIMING_FIX.md`, `SHEET_DISMISS_TIMING_FIX.md`

#### Pattern 5: Helper Function Pattern

**ensureMainStudioViewIsOpen() - Standard helper for navigation tests**

```swift
/// Ensures MainStudioView is open by checking for CloseButton
/// If not open, selects first database from list
@MainActor
private func ensureMainStudioViewIsOpen() throws {
    // Use CloseButton to validate MainStudioView (NOT navigationPicker)
    let closeButton = app.buttons["CloseButton"].firstMatch

    // Already in MainStudioView?
    if closeButton.exists {
        print("✅ Already in MainStudioView")
        return
    }

    // Not in MainStudioView - open first database
    print("📋 Not in MainStudioView, opening first database...")

    let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
    guard addDatabaseButton.waitForExistence(timeout: 5) else {
        throw XCTSkip("Not on ContentView")
    }

    // Find and tap first database (note: uses legacy "AppCard_" identifier)
    let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
    let firstCard = app.descendants(matching: .any)
        .matching(predicate)
        .firstMatch

    guard firstCard.waitForExistence(timeout: 5) else {
        throw XCTSkip("No databases found")
    }

    firstCard.tap()
    sleep(2)  // Wait for transition

    // Wait for MainStudioView (validate with CloseButton, NOT navigationPicker)
    guard closeButton.waitForExistence(timeout: 30) else {
        XCTFail("MainStudioView did not open")
        throw XCTSkip("MainStudioView failed to open")
    }

    print("✅ MainStudioView opened successfully")
}
```

#### Pattern 6: Complete Test Template

**Standard test structure following all established patterns:**

```swift
@MainActor
func testNavigationToView() throws {
    // ARRANGE: Wait for app to finish loading
    waitForAppToFinishLoading(timeout: 20)

    // Add databases via UI automation (required for fresh sandbox)
    try addDatabasesFromPlist()

    // Open MainStudioView
    try ensureMainStudioViewIsOpen()

    // ACT: Navigate to view (if navigation button accessible)
    let navigationButton = app.buttons["NavigationItem_Collections"]

    guard navigationButton.waitForExistence(timeout: 5) else {
        print("⚠️ Navigation button not accessible")
        throw XCTSkip("Navigation requires accessible picker segments")
    }

    print("📍 Tapping navigation button...")
    navigationButton.tap()
    sleep(2)  // Wait for view transition

    // ASSERT: Validate view loaded
    let headerText = app.staticTexts["Ditto Collections"]
    XCTAssertTrue(
        headerText.waitForExistence(timeout: 5),
        """
        View header not found after navigation.
        View may not have rendered correctly.
        """
    )
    print("✅ View loaded successfully")

    // Capture screenshot
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "view-loaded"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
}
```

#### Pattern 7: Test Documentation

**Required documentation in test files:**

```swift
/// Tests navigation to Collections view
///
/// **Setup:**
/// - Requires testDatabaseConfig.plist with at least one database
/// - Uses UI form automation to add databases (fresh sandbox)
///
/// **Test Flow:**
/// 1. Wait for app to finish loading
/// 2. Add databases via form automation
/// 3. Open first database (MainStudioView)
/// 4. Navigate to Collections view
/// 5. Validate Collections sidebar and detail view
///
/// **Known Limitations:**
/// - Navigation button may not be accessible if picker uses SF Symbol images
/// - Test will skip with clear message if navigation not possible
///
/// **See Also:**
/// - NAVIGATION_TESTS_UPDATE_SUMMARY.md
/// - PICKER_WORKAROUND_FIX.md
@MainActor
func testNavigationToCollections() throws {
    // ... implementation
}
```

#### Pattern 8: Skip Messages

**When tests must skip due to accessibility limitations, provide clear guidance:**

```swift
guard navigationButton.waitForExistence(timeout: 2) else {
    print("⚠️ Navigation button not accessible in UI tests")
    print("   SwiftUI Picker with SF Symbol images doesn't expose segments to XCUITest")
    print("")
    print("   TO FIX: Update picker to use text labels:")
    print("   Replace: item.image.tag(item)")
    print("   With: Text(item.name).tag(item)")
    print("")
    throw XCTSkip("""
        Navigation requires picker segments to be accessible.

        Current picker uses SF Symbol images which aren't exposed in XCUITest.
        Update picker to use Text labels or custom buttons for testability.

        See NAVIGATION_TESTS_UPDATE_SUMMARY.md for details.
        """)
}
```

### UI Testing Documentation Files

Comprehensive documentation created during UI test development:

- **`NAVIGATION_TESTS_UPDATE_SUMMARY.md`** - Complete summary of all navigation test updates, patterns, and solutions
- **`ADDBUTTON_FIRSTMATCH_FIX.md`** - Nested button structure fix (.firstMatch pattern)
- **`SHEET_TIMING_FIX.md`** - macOS sheet timing patterns and workarounds
- **`PICKER_WORKAROUND_FIX.md`** - SwiftUI Picker accessibility issues and workarounds
- **`SHEET_DISMISS_TIMING_FIX.md`** - Sheet dismissal and database save timing patterns

**Refer to these documents for detailed explanations and examples.**

## Code Quality Tools

**CRITICAL: This project uses automated tools to detect unused code, enforce code quality, and maintain consistent style.**

### Tool Overview

| Tool | Purpose | When to Run | Configuration File |
|------|---------|-------------|-------------------|
| **Periphery** | Detects unused Swift code | Monthly or before releases | `.periphery.yml` |
| **SwiftLint** | Enforces style and detects issues | During development | `.swiftlint.yml` |
| **SwiftFormat** | Auto-formats code | Before committing | `.swiftformat` |

### Installation (Required for Contributors)

All tools installed via Homebrew:

```bash
# Install all three tools
brew install peripheryapp/periphery/periphery
brew install swiftlint
brew install swiftformat

# Verify installations
periphery version  # Should show 2.21.2+
swiftlint version  # Should show 0.63.2+
swiftformat --version  # Should show 0.59.1+
```

### Periphery - Unused Code Detection

**What it does:**
- Scans entire project to find unused Swift code
- Detects unused classes, structs, enums, protocols, functions, properties
- Analyzes build graph to understand actual usage patterns
- Generates reports of dead code candidates

**When to run:**
- Monthly code cleanup sessions
- Before major releases
- When preparing for refactoring
- After removing features

**How to run:**

```bash
# Standard scan (from project root)
cd /Users/labeaaa/Developer/ditto-edge-studio
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format xcode

# Save report to file
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format xcode > periphery-report.txt

# Generate baseline (track new unused code only)
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --baseline .periphery_baseline.json
```

**Configuration (`.periphery.yml`):**
- Excludes test files and generated code
- Retains `@main`, `@objc`, and other special attributes
- Configured for app targets (not framework/library)

**Understanding results:**
- Periphery lists file path, line number, and type/name of unused code
- Verify before deleting - some code may be used via runtime reflection or dynamic lookups
- SwiftUI views with no direct references may still be used via navigation

**Common false positives:**
- SwiftUI view initializers
- Protocol requirements in protocol definitions
- Code used via Objective-C runtime
- Entry points (`@main`, `@NSApplicationMain`)

### SwiftLint - Code Quality & Style

**What it does:**
- Enforces Swift style guidelines (based on Swift.org and community standards)
- Detects code smells and potential bugs
- Finds unused imports, variables, and closures
- Warns about force unwraps, force casts, and overly complex code

**When to run:**
- During active development (continuously)
- Before committing changes
- As part of code review process
- Can be integrated into Xcode build phase

**How to run:**

```bash
# Lint entire project
swiftlint lint

# Lint and auto-fix issues
swiftlint lint --fix

# Lint specific directory
swiftlint lint --path "SwiftUI/Edge Debug Helper/"

# Strict mode (treat warnings as errors)
swiftlint lint --strict

# Generate HTML report
swiftlint lint --reporter html > swiftlint-report.html
```

**Xcode Integration:**

Add a "Run Script" build phase to show SwiftLint warnings in Xcode:

```bash
# Build Phase Script:
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

**Configuration (`.swiftlint.yml`):**
- Enables unused code detection rules
- Custom rules for project-specific patterns
- Excludes generated files (`FontAwesomeIcons.swift`)
- Excludes POC/experimental code

**Key enabled rules:**
- `unused_import` - Detects unused import statements
- `unused_declaration` - Finds unused functions/variables
- `unused_optional_binding` - Unused variables in if-let/guard-let
- `force_unwrapping` - Warns about `!` force unwraps
- `sorted_imports` - Enforces alphabetical import order

**Custom rules:**
- `todos_fixmes` - Warns about TODO/FIXME comments
- `no_print_statements` - Detects print() calls (use proper logging)

### SwiftFormat - Code Formatting

**What it does:**
- Automatically formats Swift code for consistency
- Enforces indentation, spacing, brace style
- Organizes imports and removes redundancies
- Makes code style uniform across the project

**When to run:**
- Before committing changes
- After pulling code from others
- When refactoring or restructuring code
- Can be run automatically via pre-commit hook

**How to run:**

```bash
# Format entire project
swiftformat .

# Format specific directory
swiftformat "SwiftUI/Edge Debug Helper/"

# Dry run (show what would change without modifying files)
swiftformat --verbose --dryrun .

# Format and show changes
swiftformat --verbose .
```

**Configuration (`.swiftformat`):**
- Swift 6.2 syntax
- 4-space indentation
- 150-character line width
- Inline commas and semicolons
- Removes redundant `self`

**Pre-commit hook (optional):**

Create `.git/hooks/pre-commit`:
```bash
#!/bin/sh
swiftformat --verbose .
git add -u
```

Make executable: `chmod +x .git/hooks/pre-commit`

### Best Practices for Using These Tools

**Daily Development:**
1. SwiftLint runs automatically if integrated into Xcode build phase
2. Run `swiftlint lint --fix` before committing to auto-correct issues
3. Review SwiftLint warnings and address high-priority ones

**Weekly/Sprint:**
1. Run SwiftFormat on modified files: `swiftformat "path/to/modified/files"`
2. Ensure all SwiftLint warnings are addressed before merging PRs

**Monthly/Major Releases:**
1. Run Periphery scan to identify unused code: `periphery scan ...`
2. Review Periphery report and create tickets for removal candidates
3. Verify test coverage before removing code flagged by Periphery

**Before Committing:**
```bash
# Recommended pre-commit checks
swiftlint lint --fix  # Auto-fix style issues
swiftformat .         # Format code
swiftlint lint        # Final check for remaining issues
```

**CI/CD Integration (Future):**

Add to GitHub Actions or CI pipeline:
```yaml
- name: SwiftLint
  run: swiftlint lint --strict

- name: Periphery
  run: periphery scan --format github-actions --fail-on-unused
```

### Tool Output Examples

**Periphery output:**
```
/path/to/File.swift:42:6: warning: Struct 'UnusedStruct' is unused
/path/to/File.swift:58:10: warning: Function 'unusedFunction()' is unused
```

**SwiftLint output:**
```
/path/to/File.swift:12:5: warning: Unused Import Violation: 'Foundation' is imported but not used
/path/to/File.swift:45:20: warning: Force Unwrapping Violation: Avoid using ! to force unwrap
```

**SwiftFormat output:**
```
1/245 files updated:
  /path/to/File.swift
```

### Troubleshooting

**Periphery scan fails or hangs:**
- Ensure Xcode project builds successfully first
- Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Check `.periphery.yml` excludes paths are correct
- Run with `--verbose` flag for debugging

**SwiftLint too strict:**
- Adjust rules in `.swiftlint.yml`
- Disable specific rules with `disabled_rules:`
- Use inline comments to suppress warnings: `// swiftlint:disable:next rule_name`

**SwiftFormat changes too aggressive:**
- Review `.swiftformat` configuration
- Use `--dryrun` to preview changes before applying
- Disable specific rules with `--disable rule_name`

### When NOT to Use These Tools

**Don't rely solely on automated tools for:**
- Architectural decisions (tools can't judge if code *should* exist)
- Performance optimization (tools don't measure runtime performance)
- Security audits (tools catch obvious issues, not all vulnerabilities)
- User experience issues (tools don't test UI/UX quality)

**Always combine automated tools with:**
- Manual code review
- Unit and UI testing
- Performance profiling
- User testing and feedback

### Further Reading

- **Periphery Documentation:** https://github.com/peripheryapp/periphery
- **SwiftLint Rules Reference:** https://realm.github.io/SwiftLint/rule-directory.html
- **SwiftFormat Rules Reference:** https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md
- **Swift Style Guide:** https://google.github.io/swift/

### Periphery Scanning Results Summary

**Last Full Scan:** February 17, 2026
**Total Unused Declarations Found:** 0
**Removed in Initial Cleanup:** 0 (clean codebase)
**Baseline Created:** February 17, 2026

**Scan Statistics:**
- **Files Analyzed:** 80 Swift files
- **Lines of Code:** ~22,015 lines
- **Scan Duration:** ~3 minutes
- **Tool Version:** Periphery 2.21.2

**Result Interpretation:**

The "no unused code" result is **accurate and expected** for this SwiftUI-based project:
- SwiftUI's dynamic view construction makes static analysis challenging
- Recent architecture refactoring (Font Awesome integration, repository optimization) removed legacy code
- Active development with comprehensive testing validates code usage
- Conservative retainers (SwiftUIRetainer, XCTestRetainer) mark most code as "potentially used"

**Common False Positives (Already Handled):**
- SwiftUI View structs used via @ViewBuilder - Retained by SwiftUIRetainer
- Protocol requirements in protocol definitions - Retained by ProtocolConformanceReferenceBuilder
- @objc declarations - Retained by configuration (`retain_objc_accessible: true`)
- Test code - Excluded via `report_exclude: [".*Tests\\.swift"]`
- Generated code - Excluded via `report_exclude: ["FontAwesomeIcons\\.swift"]`
- POC/experimental code - Excluded via `report_exclude: ["POC/.*"]`

**Baseline Tracking:**
- Baseline file: `.periphery_baseline.json` (gitignored)
- Baseline snapshot: `reports/periphery/baselines/periphery-baseline-20260217.json`
- Future scans will only show **new** unused code since baseline

**Next Scheduled Scan:** First Monday of each month

**Detailed Report:** See `reports/periphery/UNUSED_CODE_REPORT_2026-02-17.md` for comprehensive analysis.

## Logging Framework

**CRITICAL: This project uses CocoaLumberjack for file-based logging with user-viewable logs for debugging and GitHub issue support.**

### Why CocoaLumberjack?

Edge Debug Helper uses [CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack) for comprehensive logging:

- ✅ **File-based logging**: All logs written to files with automatic rotation
- ✅ **User accessibility**: Logs can be viewed in-app and exported for GitHub issues
- ✅ **Automatic rotation**: Keeps last 7 days, 5MB max per file
- ✅ **Performance**: Asynchronous logging, doesn't block UI
- ✅ **Thread-safe**: Safe for concurrent access across actors
- ✅ **macOS native**: Full support for macOS, iOS, tvOS, watchOS, visionOS

### Installation (Required)

**The project requires CocoaLumberjack to build.** Add it via Swift Package Manager:

1. Open `Edge Debug Helper.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/CocoaLumberjack/CocoaLumberjack`
4. Select version: **Latest** (3.8.5+)
5. Add to target: **Edge Debug Helper**

### Usage

The project provides a centralized `LoggingService` (`Utilities/LoggingService.swift`) with a global `Log` accessor:

```swift
// Import not needed - Log is globally available

// Debug (development only)
Log.debug("Detailed debug information")

// Info (general information)
Log.info("Starting operation")

// Warning (non-critical issues)
Log.warning("Missing optional configuration")

// Error (failures, exceptions)
Log.error("Operation failed: \(error.localizedDescription)")
```

**DO NOT use `print()` statements** - All logging must use the `Log` API for proper file logging and user support.

### Log File Location

Logs are automatically saved to:
```
~/Library/Logs/io.ditto.EdgeStudio/
```

**Log rotation:**
- Daily rotation (24-hour rolling)
- Maximum 7 log files kept
- 5MB maximum per file
- Old logs automatically deleted

### Retrieving Logs (for User Support)

```swift
// Get all log files
let logFiles = Log.getAllLogFiles()

// Get combined log content
let logContent = Log.getCombinedLogs()

// Get logs directory path
let logsDir = Log.getLogsDirectory()

// Export logs to specific location
try Log.exportLogs(to: destinationURL)

// Clear all logs (privacy/reset)
Log.clearAllLogs()
```

### Future Feature: Log Viewer

Planned feature for users to:
- View logs in-app
- Copy logs to clipboard
- Export logs as attachment for GitHub issues
- Clear logs for privacy

See `LoggingService.swift` for implementation details and future log viewer UI examples.

### Log Levels by Build Configuration

**Debug builds:**
- All log levels enabled (debug, info, warning, error)
- Console output to Xcode
- File logging enabled

**Release builds:**
- Info, warning, error only (debug disabled)
- No console output
- File logging enabled

### Best Practices

1. **Use appropriate log levels:**
   - `debug()` - Temporary debugging, verbose details
   - `info()` - Normal operations, state changes
   - `warning()` - Recoverable issues, missing optional data
   - `error()` - Failures, exceptions, critical issues

2. **Include context:**
   ```swift
   // ❌ Bad
   Log.error("Failed")

   // ✅ Good
   Log.error("Failed to load database '\(dbName)': \(error.localizedDescription)")
   ```

3. **Don't log sensitive data:**
   - No authentication tokens
   - No user passwords
   - No personally identifiable information (PII)

4. **Use descriptive messages:**
   - Logs should be understandable without code context
   - Include operation name, resource identifiers, error details

### Troubleshooting

**Build error: "No such module 'CocoaLumberjack'"**
- Verify CocoaLumberjack is added via Swift Package Manager
- Clean build: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Rebuild project

**Logs not appearing:**
- Check `~/Library/Logs/io.ditto.EdgeStudio/` directory exists
- Verify `LoggingService.shared` is initialized (happens automatically)
- Check Console.app for any initialization errors

**Too many log files:**
- Log rotation is automatic (7 days, 5MB max)
- Use `Log.clearAllLogs()` to manually clear all logs

## Development Environment Setup

### Xcode Version Requirements
This project requires **Xcode 26.2** (or later) with Swift 6.2 for proper dependency compatibility.

**To verify your Xcode version:**
```bash
# Verify Xcode version
xcode-select -p
xcodebuild -version
xcrun swift --version
```

### Build Environment Clean-up
If experiencing Swift version compatibility issues:
```bash
# Clear derived data to force fresh dependency compilation
rm -rf ~/Library/Developer/Xcode/DerivedData

# Clean and rebuild project
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" clean
```

## Build Commands

### SwiftUI (macOS/iPadOS)
```bash
# Build the app (ARM64 only to avoid multiple destination warnings)
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build

# Run tests
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" test

# Build for release
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release -destination "platform=macOS,arch=arm64" archive

# Export for distribution (requires exportOptions.plist)
xcodebuild -exportArchive -archivePath <path-to-archive> -exportPath <output-path> -exportOptionsPlist SwiftUI/exportOptions.plist
```

## Architecture

### SwiftUI App Structure
Located in the `SwiftUI/` directory:

- **DittoManager** (`Data/` folder): Core service layer split into functional modules:
  - `DittoManager.swift`: Base initialization and shared state
  - `DittoManager_Lifecycle.swift`: Connection management and sync controls
  - `DittoManager_Query.swift`: Query execution and results handling
  - `DittoManager_Subscription.swift`: Real-time subscription management
  - `DittoManager_Observable.swift`: Observe event handling
  - `DittoManager_LocalSubscription.swift`: Local database subscriptions for database state
  - `DittoManager_DittoAppConfig.swift`: Database configuration management (uses DittoConfigForDatabase model)
  - `DittoManager_Import.swift`: Data import functionality

- **QueryService** (`Data/QueryService.swift`): Query execution service with enhanced features:
  - Local and HTTP query execution
  - Commit ID tracking for mutated documents
  - Returns both document IDs and commit IDs for mutations

- **Repositories** (`Data/Repositories/` folder): Actor-based data repositories with threading optimizations:
  - `SubscriptionsRepository.swift`: Real-time subscription management
  - `HistoryRepository.swift`: Query history tracking with observer pattern
  - `FavoritesRepository.swift`: Favorite queries management
  - `ObservableRepository.swift`: Observable events management with diffing
  - `CollectionsRepository.swift`: Collections data management
  - `SystemRepository.swift`: System metrics and health monitoring, including sync status and connection transport statistics
  - All repositories use Task.detached(priority: .utility) for cleanup operations to prevent threading priority inversions
  
- **Views** (`Views/` folder):
  - `ContentView.swift`: Root view with database selection
  - `MainStudioView.swift`: Primary interface with navigation sidebar and detail views
    - Sync detail view uses native TabView with three tabs: Peers List, Presence Viewer, Settings
    - Tab selection persists when navigating between menu items
    - Threading optimizations for cleanup operations using TaskGroup
  - `DatabaseEditorView.swift`: Database configuration editor (uses DittoConfigForDatabase model)
  - **Tabs/**: Tab-specific views like `ObserversTabView.swift`
  - **Tools/**: Utility views (presence, disk usage, peers, permissions)
  
- **Components** (`Components/` folder): Reusable UI components
  - Query editor and results viewers
  - Database and subscription cards/lists
  - Pagination controls and secure input fields
  - `DatabaseCard.swift`: Card component for displaying database configurations
  - `NoDatabaseConfigurationView.swift`: Empty state when no databases are configured
  - `ConnectedPeersView.swift`: Extracted sync status view showing connected peers (used in Peers List tab)
  - `PresenceViewerTab.swift`: Wrapper for DittoPresenceViewer with connection handling
  - `TransportConfigView.swift`: Placeholder for future transport configuration settings

## Configuration Requirements
Requires `dittoConfig.plist` in `SwiftUI/Edge Debug Helper/` with:
- `appId`: Ditto application ID
- `authToken`: Authentication token
- `authUrl`: Authentication endpoint
- `websocketUrl`: WebSocket endpoint
- `httpApiUrl`: HTTP API endpoint
- `httpApiKey`: HTTP API key

## Key Features
- Multi-database connection management with local storage (using DittoConfigForDatabase model)
- Query execution with history and favorites
- Real-time subscriptions and observables
- Connection status bar with real-time transport-level monitoring (WebSocket, Bluetooth, P2P WiFi, Access Point)
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking
- Font Debug window for visualizing all Font Awesome icons (Help menu → Font Debug or ⌘⇧D)

## UI Patterns

### Picker Navigation Consistency

**CRITICAL: Sidebar and Inspector navigation MUST use identical Picker implementation.**

Both use this exact pattern:

```swift
HStack {
    Spacer()
    Picker("", selection: $selectedItem) {
        ForEach(items) { item in
            item.image  // 48pt SF Symbol
                .tag(item)
        }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .liquidGlassToolbar()
    .accessibilityIdentifier("NavigationSegmentedPicker") // or "InspectorSegmentedPicker"
    Spacer()
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
```

**Standards:**
- Navigation icons: **48pt** SF Symbols only (not Font Awesome)
- Picker height: **Auto-sized** (no fixed height constraint - allows picker to grow with icon size)
- Picker alignment: **Centered** using HStack with Spacers
- Both use MenuItem struct with `systemIcon: String`
- Both use `.accessibilityIdentifier()` for UI tests
- If styling changes in one, MUST change in the other

**Menu Items:**
- Sidebar: Subscriptions (arrow.trianglehead.2.clockwise.rotate.90), Collections (macpro.gen2), Observer (eye)
- Inspector: History (clock), Favorites (bookmark)

**MenuItem Structure:**
```swift
struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var systemIcon: String  // SF Symbol name

    @ViewBuilder
    var image: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 48))
    }
}
```

## Font Awesome Icons

### Icon System
The app uses Font Awesome 7 Pro for all icons instead of SF Symbols for better cross-platform consistency and design flexibility.

**Key Files:**
- `Utilities/FontAwesome.swift` - Icon alias enums and helper functions
- `Utilities/FontAwesomeIcons.swift` - Auto-generated enum with 4,245 icons
- `Views/Tools/FontDebugWindow.swift` - Debug window showing all icons in use
- `generate_icons.swift` - Script to regenerate icons from font files

**Icon Categories:**
- **PlatformIcon**: OS icons (Linux, macOS, Android, iOS, Windows)
- **ConnectivityIcon**: Network/transport icons (WiFi, Bluetooth, Ethernet, etc.)
- **SystemIcon**: System UI icons (Link, Info, Clock, Gear, Question, SDK)
- **NavigationIcon**: Navigation controls (Chevrons, Play, Refresh, Sync)
- **ActionIcon**: User actions (Plus, Download, Copy, Close)
- **DataIcon**: Data display (Code, Table, Database, Layers)
- **StatusIcon**: Status indicators (Check, Info, Warning, Question)
- **UIIcon**: Interface elements (Star, Eye, Clock, Nodes)

### Adding New Icons

**CRITICAL: When adding a new icon to any category, you MUST update the Font Debug Window.**

1. **Add icon to FontAwesome.swift:**
   ```swift
   enum NavigationIcon {
       static let newIcon: FAIcon = .icon_f123  // fa-icon-name
   }
   ```

2. **Update FontDebugWindow.swift** in the `allIcons` computed property:
   ```swift
   // Navigation Icons section
   icons.append(contentsOf: [
       // ... existing icons ...
       IconDebugInfo(icon: NavigationIcon.newIcon, aliasName: "NavigationIcon.newIcon",
                    category: "Navigation Icons", unicode: "f123",
                    fontFamily: "FontAwesome7Pro-Solid"),
   ])
   ```

3. **Use the icon in views:**
   ```swift
   FontAwesomeText(icon: NavigationIcon.newIcon, size: 14)
   ```

**Finding Unicode Values:**
- Use Font Book.app to inspect font glyphs
- Check Font Awesome website (fontawesome.com)
- Search FontAwesomeIcons.swift for icon codes
- Unicode format in Swift: `\u{XXXX}` (e.g., `\u{f2f1}`)

**Font Families:**
- `FontAwesome7Pro-Solid` (900 weight) - Most icons (3,725 icons)
- `FontAwesome7Pro-Regular` (400 weight) - Lighter variant of Solid icons
- `FontAwesome7Pro-Light` (300 weight) - Light weight for subtle UI elements
- `FontAwesome7Pro-Thin` (100 weight) - Thinnest weight for large icons or minimal designs
- `FontAwesome7Brands-Regular` - Brand/platform icons (526 icons)

### Font Weights

The app supports multiple font weights for the same icon unicode value using the `WeightedFAIcon` system.

**When to Use Different Weights:**
- **Solid (900)**: Default weight for most icons, provides best visibility at small sizes
- **Regular (400)**: Lighter appearance, better for large icons (64pt+) or when visual weight needs to be reduced
- **Light (300)**: Very subtle appearance, ideal for toolbar icons and non-primary actions
- **Thin (100)**: Extremely light weight, best for very large icons (80pt+) or minimalist designs

**Creating Weighted Icons:**
```swift
// In icon alias enums
enum DataIcon {
    static let database: FAIcon = .icon_f1c0                      // Solid (default)
    static let databaseRegular: WeightedFAIcon = WeightedFAIcon(.icon_f1c0, weight: .regular)
}

enum NavigationIcon {
    static let sync: FAIcon = .icon_f2f1                          // Solid (default)
    static let syncLight: WeightedFAIcon = WeightedFAIcon(.icon_f2f1, weight: .light)
}
```

**Usage Examples:**
```swift
// Solid database icon (default) for small size
FontAwesomeText(icon: DataIcon.database, size: 14)

// Regular database icon for large size (less visual weight)
FontAwesomeText(icon: DataIcon.databaseRegular, size: 64)

// Light sync icon for toolbar (subtle appearance)
FontAwesomeText(icon: NavigationIcon.syncLight, size: 20)
```

**Current Weighted Variants:**
- `DataIcon.databaseRegular` - Database icon in Regular (400) weight
- `DataIcon.databaseThin` - Database icon in Thin (100) weight (used for main screen)
- `NavigationIcon.syncLight` - Sync/rotate icon in Light (300) weight
- `ActionIcon.circleXmarkLight` - Close icon in Light (300) weight

### Font Debug Window
Access via **Help → Font Debug** or **⌘⇧D**

Features:
- Visual display of all 47+ icons currently in use (including weighted variants)
- Search by alias name or unicode value
- Category filtering (8 categories)
- Copy icon alias names to clipboard
- Shows: icon rendering, alias name, unicode value, font family, font weight

**Purpose:** Quick reference for developers and visual verification that all icons render correctly. The weight column shows which font weight each icon uses (Solid 900, Regular 400, Light 300, or Brands).

## App Launch and Navigation Flow

**CRITICAL: Understanding this flow is required for writing UI tests.**

### Complete Navigation Flow

```
App Launch (Ditto_Edge_StudioApp.swift)
  ↓
ContentView (root view)
  ├─ State: isMainStudioViewPresented = false (initially)
  ├─ onAppear: loadApps() - loads database configurations (DittoConfigForDatabase models)
  │
  ├──→ DATABASE LIST SCREEN (when isMainStudioViewPresented = false)
  │    │
  │    ├─ Component: DatabaseList
  │    │  └─ Accessibility ID: "DatabaseList" (macOS only)
  │    │
  │    ├─ Loading State: ProgressView("Loading Database Configs...")
  │    ├─ Empty State: NoDatabaseConfigurationView (component)
  │    │
  │    └─ Normal State: List of database cards
  │       ├─ Each card: DatabaseCard component
  │       ├─ Accessibility ID: "AppCard_{name}" (macOS only, legacy naming)
  │       └─ User taps card →
  │          ├─ showMainStudio(dittoDatabase) called
  │          ├─ selectedDittoConfigForDatabase = dittoDatabase
  │          ├─ hydrateDittoSelectedDatabase() - async setup
  │          └─ isMainStudioViewPresented = true
  │             ↓
  │             (ContentView re-renders)
  │             ↓
  └──→ MAINSTUDIOVIEW SCREEN (when isMainStudioViewPresented = true)
       │
       ├─ Toolbar (top)
       │  ├─ Sync toggle button
       │  ├─ Close button → returns to database list
       │  └─ Inspector toggle (ID: "Toggle Inspector")
       │
       ├─ Sidebar (left panel, 200-300px)
       │  ├─ NavigationSegmentedPicker (ID: "NavigationSegmentedPicker")
       │  └─ Menu Items: Subscriptions | Collections | Observer
       │
       ├─ Detail Area (center panel)
       │  ├─ Collections: QueryEditor (50%) + QueryResults (50%)
       │  ├─ Observer: ObserverEventsList + EventDetail
       │  └─ Subscriptions: Sync tabs (Peers/Presence/Settings)
       │
       ├─ Inspector (right panel, 250-500px, optional)
       │  ├─ InspectorSegmentedPicker (ID: "InspectorSegmentedPicker")
       │  └─ Tabs: History | Favorites
       │
       └─ Status Bar (bottom)
          └─ ConnectionStatusBar (sync status, peer count)
```

### Accessibility Identifiers for UI Testing

| Element | Identifier | Platform | Purpose |
|---------|-----------|----------|---------|
| **Add Database Button** | `"AddDatabaseButton"` | Both | **ContentView indicator** - CRITICAL for test verification |
| Database List Container | `"DatabaseList"` | macOS only | Root container for database cards |
| Individual Database Card | `"AppCard_{name}"` | macOS only | Each selectable database (legacy "App" naming) |
| Sidebar Navigation Picker | `"NavigationSegmentedPicker"` | Both | Sidebar menu switcher |
| Inspector Toggle Button | `"Toggle Inspector"` | Both | Show/hide inspector |
| Inspector Navigation Picker | `"InspectorSegmentedPicker"` | Both | Inspector menu |

**Note:** Some accessibility identifiers use legacy "App" naming (e.g., `"AppCard_{name}"`) but these refer to database configurations.

## Testing

### Unit Tests
- Location: `Edge Debug Helper Tests/`
- Run all tests: `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" test`

### UI Tests

**CRITICAL: UI tests must understand the app launch flow described above.**

- Location: `Edge Debugg Helper UITests/`
- Main test file: `Ditto_Edge_StudioUITests.swift`

**UI Test Environment Setup (REQUIRED):**

UI tests run in a sandboxed environment with NO access to your normal app data. To make tests work, you must:

1. **Create test database configuration file:**
   ```bash
   cd "SwiftUI/Edge Debug Helper"
   cp testDatabaseConfig.plist.example testDatabaseConfig.plist
   ```

2. **Edit `testDatabaseConfig.plist` with real test credentials:**

   The file supports three auth modes - you can add multiple databases of any type:

   **Online Playground Mode** (`mode: "onlineplayground"`):
   - Required: name, mode, appId, authToken, authUrl, websocketUrl, httpApiUrl, httpApiKey
   - Use for testing with cloud sync and authentication

   **Offline Playground Mode** (`mode: "offlineplayground"`):
   - Required: name, mode, appId
   - Optional auth fields can be empty strings
   - Use for testing local-only, no authentication scenarios

   **Shared Key Mode** (`mode: "sharedkey"`):
   - Required: name, mode, appId, secretKey
   - Optional auth fields can be empty strings
   - Use for testing shared key authentication (32-character secret key)

   **Optional fields** (all modes):
   - `isBluetoothLeEnabled`, `isLanEnabled`, `isAwdlEnabled`, `isCloudSyncEnabled` (default: true)
   - `allowUntrustedCerts` (default: false)

   - You can add multiple databases for testing different scenarios
   - This file is gitignored - safe to add real credentials

3. **How it works:**
   - Tests launch app with `UI-TESTING` argument
   - App detects UI testing mode in `AppState.init()`
   - Automatically loads all databases from `testDatabaseConfig.plist`
   - Databases are saved to sandboxed storage using `DatabaseRepository`
   - Tests can now select and interact with databases

**File Structure:**
```
SwiftUI/Edge Debug Helper/
├── testDatabaseConfig.plist.example  ← Template (checked into git)
└── testDatabaseConfig.plist          ← Your real credentials (gitignored)
```

**Writing UI Tests - Required Steps:**

1. **Understand the current view state:**
   - App always launches to ContentView (database list)
   - MainStudioView only appears after selecting a database
   - Navigation elements don't exist until MainStudioView is presented

2. **CRITICAL: Tests always start at ContentView in fresh sandbox**

   Each test run starts with a completely fresh sandbox (no saved data). The app MUST start at ContentView (database list screen). If it doesn't, the test should FAIL, not skip.

   **Standard UI test flow:**
   ```swift
   // 1. ALWAYS verify app started at ContentView (language-independent check)
   let addDatabaseButton = app.buttons["AddDatabaseButton"]
   XCTAssertTrue(
       addDatabaseButton.waitForExistence(timeout: 5),
       "App must start at ContentView. Tests run in fresh sandbox."
   )

   // 2. Wait for database list to load
   let databaseList = app.otherElements["DatabaseList"]
   guard databaseList.waitForExistence(timeout: 5) else {
       XCTFail("DatabaseList not found - check testDatabaseConfig.plist")
       throw XCTSkip("No database list")
   }

   // 3. Find and tap a database card (note: uses legacy "AppCard_" identifier)
   let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
   let firstCard = databaseList.descendants(matching: .any)
       .matching(predicate).firstMatch
   firstCard.tap()

   // 4. CRITICAL: Wait for UI transition (allow animation to complete)
   sleep(5)

   // 5. Wait for MainStudioView to appear
   let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
   guard navigationPicker.waitForExistence(timeout: 10) else {
       XCTFail("MainStudioView did not appear")
       return
   }

   // 6. Test MainStudioView elements
   // ALWAYS add sleep(2) after EVERY tap to allow UI to update
   button.tap()
   sleep(2)  // Required for UI to render
   ```

3. **Adding accessibility identifiers:**
   ```swift
   Button("My Button") {
       // action
   }
   .accessibilityIdentifier("MyButtonIdentifier")
   ```

   Reference: https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:)

**Reference Documentation:**
- XCUIAutomation: https://developer.apple.com/documentation/xcuiautomation

### Running Tests
```bash
# Run all tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio"

# Run specific test
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -only-testing:"Edge Debug HelperUITests/Ditto_Edge_StudioUITests/testNavigationPickersWithScreenshots"
```

## Platform Requirements

- macOS 26.0 with Xcode 26.0+ with Swift 6.2
- iPadOS 18.0+
- App sandbox enabled with entitlements for network, Bluetooth, and file access

## Threading and Performance Optimizations

### Threading Priority Inversion Prevention
The SwiftUI app includes comprehensive threading optimizations to prevent priority inversions during Ditto sync operations:

- **DittoManager**: All sync start/stop operations use `Task.detached(priority: .utility)` to run on appropriate background queues
- **Repository Cleanup**: All repository `stopObserver()` methods use background tasks to prevent blocking the main UI thread
- **MainStudioView**: App cleanup operations are separated into UI state updates (main thread) and heavy operations (background queues using TaskGroup)

These optimizations eliminate threading warnings like "Thread running at User-initiated quality-of-service class waiting on a lower QoS thread running at Default quality-of-service class."

### QueryService Enhancements
The QueryService now provides enhanced mutation tracking:
- Returns document IDs for all mutated documents
- Includes commit ID information for better change tracking
- Supports both local Ditto queries and HTTP API queries
- Format: `"Document ID: [id]"` followed by `"Commit ID: [commit_id]"`

## Troubleshooting

### Swift Version Compatibility Issues
If you encounter "module compiled with Swift 6.2 cannot be imported by the Swift 6.1.2 compiler" errors:

1. **Ensure Xcode 26.2+ is active**:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. **Clean build environment**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   xcodebuild clean
   ```

3. **Verify Swift version alignment**:
   ```bash
   xcrun swift --version  # Should show Swift 6.2
   ```

### Build Issues
- Use ARM64-only builds to avoid multiple destination warnings
- Ensure Xcode 26.2+ is active for Swift 6.2 compatibility
- Clean derived data if dependencies seem out of sync
