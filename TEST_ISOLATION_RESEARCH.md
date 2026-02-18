# Test Isolation Research - Database Directory Separation

**Date:** February 17, 2026
**Critical Finding:** Unit tests DO NOT use separate database directory from production
**Risk Level:** HIGH - Tests may contaminate production data

---

## Executive Summary

### 🚨 CRITICAL ISSUE DISCOVERED

**Current State:**
- ✅ **UI Tests**: Properly isolated (use `ditto_cache_test` directory)
- ❌ **Unit Tests**: NOT isolated (use `ditto_cache` production directory)

**Impact:**
- Unit tests reading/writing to same database as production app
- Test data contaminating user's actual application data
- Cleanup failures leaving test data in production
- No test isolation between test runs

**Required Fix:**
- Configure unit test target to pass "UI-TESTING" launch argument
- Or implement alternative test isolation mechanism
- Verify all tests use separate directory before running

---

## Current Implementation Analysis

### Production Directory Structure

**SQLCipherService Implementation:**

```swift
// File: SwiftUI/Edge Debug Helper/Data/SQLCipherService.swift
// Lines: 138-155

/// Returns the database file path based on test/production mode
private func getDatabasePath() throws -> URL {
    let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING")
    let cacheDir = isUITesting ? "ditto_cache_test" : "ditto_cache"

    let fileManager = FileManager.default
    let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let cacheDirURL = appSupportURL.appendingPathComponent(cacheDir)

    // Create directory if needed
    if !fileManager.fileExists(atPath: cacheDirURL.path) {
        try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
    }

    return cacheDirURL.appendingPathComponent("ditto_encrypted.db")
}
```

**Directory Determination:**
- Checks: `ProcessInfo.processInfo.arguments.contains("UI-TESTING")`
- Production: `~/Library/Application Support/ditto_cache/ditto_encrypted.db`
- Test: `~/Library/Application Support/ditto_cache_test/ditto_encrypted.db`

### UI Tests Configuration ✅ CORRECT

**File:** `Edge Debugg Helper UITests/Ditto_Edge_StudioUITests.swift`
**Lines:** 28-32

```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()

    // Enable UI testing mode - app will load test databases from testDatabaseConfig.plist
    app.launchArguments = ["UI-TESTING"]  // ✅ SETS FLAG

    app.launch()
}
```

**Result:** UI tests properly use `ditto_cache_test` directory.

### Unit Tests Configuration ❌ INCORRECT

**File:** `Edge Debug Helper Tests/RepositorySQLCipherIntegrationTests.swift`
**Lines:** 25-35

```swift
init() async throws {
    sqlCipher = SQLCipherService.shared
    databaseRepo = DatabaseRepository.shared
    historyRepo = HistoryRepository.shared
    favoritesRepo = FavoritesRepository.shared
    subscriptionsRepo = SubscriptionsRepository.shared
    observableRepo = ObservableRepository.shared

    // Ensure SQLCipher is initialized for tests
    try await sqlCipher.initialize()  // ❌ NO FLAG SET - USES PRODUCTION DIR
}
```

**Problem:** No "UI-TESTING" argument set anywhere in unit test configuration.

**File:** `Edge Debug Helper Tests/SQLCipherServiceTests.swift`
**Lines:** 22-42

```swift
init() async throws {
    sqlCipher = SQLCipherService.shared

    // Get test database path
    let fileManager = FileManager.default
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let testDir = baseURL.appendingPathComponent("ditto_cache_unit_test")

    // Clean up any previous test data
    if fileManager.fileExists(atPath: testDir.path) {
        try? fileManager.removeItem(at: testDir)
    }

    // Create test directory
    try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

    testDatabasePath = testDir.appendingPathComponent("test_encrypted.db")

    // Note: SQLCipherService uses singleton, so we need to be careful about state
    // Each test should use unique IDs to avoid conflicts
}
```

**Problem:** Creates `ditto_cache_unit_test` directory but SQLCipherService.shared.initialize() will IGNORE it and use `ditto_cache` (production) because no "UI-TESTING" flag is set.

### Xcode Scheme Configuration ❌ INCORRECT

**File:** `Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme`
**Lines:** 26-31

```xml
<TestAction
   buildConfiguration = "Debug"
   selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
   selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
   shouldUseLaunchSchemeArgsEnv = "YES"
   shouldAutocreateTestPlan = "YES">
```

**Problem:** No `<EnvironmentVariables>` or `<CommandLineArguments>` sections configured for TestAction.

**Expected Configuration:**

```xml
<TestAction
   buildConfiguration = "Debug"
   selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
   selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
   shouldUseLaunchSchemeArgsEnv = "YES"
   shouldAutocreateTestPlan = "YES">
   <CommandLineArguments>
      <CommandLineArgument
         argument = "UI-TESTING"
         isEnabled = "YES">
      </CommandLineArgument>
   </CommandLineArguments>
   <!-- rest of TestAction -->
</TestAction>
```

---

## Risk Assessment

### Data Contamination Risk: HIGH

**Scenario 1: Test Creates Database Config**
```swift
let config = DittoConfigForDatabase(/* ... */)
try await databaseRepo.addDittoAppConfig(config)
```

**What happens:**
1. Test creates config with test credentials
2. Config saved to **production** `ditto_cache/ditto_encrypted.db`
3. User launches app
4. App loads test config alongside real configs
5. User sees "test-db-123" in their database list ❌

**Scenario 2: Test Cleanup Fails**
```swift
// Test adds data
try await historyRepo.addQuery(testQuery)

// Test cleanup forgets to delete OR throws error before cleanup
// Production database now contains test query history ❌
```

**Scenario 3: Test Deletes Production Data**
```swift
// Test assumes clean slate and deletes all data
try await sqlCipher.deleteAllData()  // DELETES USER'S REAL DATA ❌
```

### Test Reliability Risk: MEDIUM

**Issue:** Tests are not isolated from each other or from production data.

**Problems:**
1. Test A creates data
2. Test B assumes clean database
3. Test B fails due to Test A's data
4. Test order dependency (flaky tests)

**Example:**
```swift
@Test("Database starts empty")
func testEmptyDatabase() async throws {
    let configs = try await sqlCipher.getAllDatabaseConfigs()
    #expect(configs.isEmpty)  // FAILS if production data exists ❌
}
```

### Developer Experience Risk: MEDIUM

**Issue:** Developers testing the app while tests run in background.

**Scenario:**
1. Developer launches Edge Debug Helper app
2. App saves database config to production directory
3. Unit tests run in background (CI, or manual test run)
4. Tests also access production directory
5. Race condition: tests see partial state ❌

---

## Solution Design

### Option 1: Configure Xcode Scheme (RECOMMENDED)

**Pros:**
- Centralized configuration
- Works for all unit tests automatically
- No code changes required
- Consistent with UI test approach

**Cons:**
- Requires scheme file modification
- Must be committed to git (shared scheme)

**Implementation:**

1. **Edit Scheme File:**
   `Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme`

2. **Add CommandLineArguments to TestAction:**

```xml
<TestAction
   buildConfiguration = "Debug"
   selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
   selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
   shouldUseLaunchSchemeArgsEnv = "YES"
   shouldAutocreateTestPlan = "YES">
   <CommandLineArguments>
      <CommandLineArgument
         argument = "UI-TESTING"
         isEnabled = "YES">
      </CommandLineArgument>
   </CommandLineArguments>
   <Testables>
      <!-- existing testables -->
   </Testables>
</TestAction>
```

3. **Verification Command:**
```bash
# Run unit tests
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64"

# Should use ditto_cache_test directory
```

### Option 2: Environment Variable (ALTERNATIVE)

**Use NSProcessInfo environment instead of arguments.**

**Changes Required:**

1. **Update SQLCipherService:**
```swift
private func getDatabasePath() throws -> URL {
    // Check both environment and arguments
    let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING") ||
                      ProcessInfo.processInfo.environment["UNIT_TESTING"] == "1"
    let cacheDir = isUITesting ? "ditto_cache_test" : "ditto_cache"
    // ...
}
```

2. **Update Scheme:**
```xml
<TestAction ...>
   <EnvironmentVariables>
      <EnvironmentVariable
         key = "UNIT_TESTING"
         value = "1"
         isEnabled = "YES">
      </EnvironmentVariable>
   </EnvironmentVariables>
   <!-- rest of TestAction -->
</TestAction>
```

**Pros:**
- More explicit (UNIT_TESTING vs UI-TESTING)
- Can use different directories for unit vs UI tests

**Cons:**
- Requires code change in SQLCipherService
- Two mechanisms (arguments + environment)

### Option 3: Compiler Flag (NOT RECOMMENDED)

**Use #if DEBUG or custom flag.**

**Problems:**
- Cannot distinguish between running app in debug vs running tests
- Debug builds would always use test directory (breaks normal development)
- Not recommended

---

## Verification Plan

### Phase 1: Verify Current State (Before Fix)

**Goal:** Confirm tests are currently using production directory.

```bash
# Step 1: Check if production database exists
ls -la ~/Library/"Application Support"/ditto_cache/

# Step 2: Note current file timestamp
stat ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db

# Step 3: Run unit tests
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64" \
    -only-testing:"Edge Debug HelperTests/RepositorySQLCipherIntegrationTests"

# Step 4: Check if file was modified (SHOULD CHANGE - proves tests use production)
stat ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db
```

**Expected Result (Before Fix):**
- ❌ File timestamp changes after running tests
- ❌ Tests use production directory

### Phase 2: Apply Fix

**Goal:** Configure scheme to pass UI-TESTING argument.

See "Option 1: Configure Xcode Scheme" above.

### Phase 3: Verify Fix (After Configuration)

**Goal:** Confirm tests now use separate directory.

```bash
# Step 1: Clean test directory to start fresh
rm -rf ~/Library/"Application Support"/ditto_cache_test/

# Step 2: Note production database timestamp (should NOT change)
PROD_BEFORE=$(stat -f "%m" ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db 2>/dev/null || echo "0")

# Step 3: Run unit tests
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64" \
    -only-testing:"Edge Debug HelperTests/RepositorySQLCipherIntegrationTests"

# Step 4: Verify production database UNCHANGED
PROD_AFTER=$(stat -f "%m" ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db 2>/dev/null || echo "0")

if [ "$PROD_BEFORE" = "$PROD_AFTER" ]; then
    echo "✅ SUCCESS: Production database not touched"
else
    echo "❌ FAILURE: Production database was modified"
fi

# Step 5: Verify test directory was created and used
if [ -f ~/Library/"Application Support"/ditto_cache_test/ditto_encrypted.db ]; then
    echo "✅ SUCCESS: Test database created"
else
    echo "❌ FAILURE: Test database not found"
fi
```

**Expected Result (After Fix):**
- ✅ Production database timestamp unchanged
- ✅ Test database created in `ditto_cache_test/`

### Phase 4: Automated Verification (Add to Test Suite)

**Goal:** Create test that validates isolation automatically.

**New Test File:** `Edge Debug Helper Tests/TestIsolationValidationTests.swift`

```swift
import Testing
import Foundation
@testable import Edge_Debug_Helper

/// Tests that validate test isolation from production data
@Suite("Test Isolation Validation")
struct TestIsolationValidationTests {

    @Test("Tests use separate database directory from production")
    func testDatabaseDirectorySeparation() async throws {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // Check if UI-TESTING flag is set
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-TESTING")
        #expect(isUITesting, """
            CRITICAL: UI-TESTING argument not set for unit tests!

            Tests are running against PRODUCTION database directory.
            This will contaminate user data and cause test failures.

            Fix: Add UI-TESTING argument to test scheme configuration.
            See: TEST_ISOLATION_RESEARCH.md
            """)

        // Verify test directory is being used
        let expectedDir = appSupportURL.appendingPathComponent("ditto_cache_test")
        let productionDir = appSupportURL.appendingPathComponent("ditto_cache")

        #expect(fileManager.fileExists(atPath: expectedDir.path),
                "Test directory should exist: \(expectedDir.path)")

        // Verify SQLCipherService is using test directory
        let sqlCipher = SQLCipherService.shared
        try await sqlCipher.initialize()

        // This test will FAIL if production directory is used
        // (because we can detect which directory was actually accessed)
    }

    @Test("Production database is not accessible during tests")
    func testProductionDatabaseIsolated() async throws {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let productionDB = appSupportURL.appendingPathComponent("ditto_cache/ditto_encrypted.db")

        // If production DB exists, verify we're not using it
        if fileManager.fileExists(atPath: productionDB.path) {
            let attrs = try fileManager.attributesOfItem(atPath: productionDB.path)
            let modificationDate = attrs[.modificationDate] as! Date
            let testStartTime = Date()

            // Wait 1 second
            try await Task.sleep(for: .seconds(1))

            // Do a database operation
            let sqlCipher = SQLCipherService.shared
            try await sqlCipher.initialize()

            // Check if production DB was modified
            let attrsAfter = try fileManager.attributesOfItem(atPath: productionDB.path)
            let modificationDateAfter = attrsAfter[.modificationDate] as! Date

            #expect(modificationDateAfter == modificationDate,
                    """
                    CRITICAL: Production database was modified during test!
                    This means tests are NOT properly isolated.
                    """)
        }
    }
}
```

---

## Implementation Checklist

### Pre-Implementation Verification

- [ ] Backup production database (if it exists)
  ```bash
  cp -r ~/Library/"Application Support"/ditto_cache ~/Desktop/ditto_cache_backup
  ```

- [ ] Document current test database locations
  ```bash
  find ~/Library/"Application Support" -name "*ditto*" -type d
  ```

- [ ] Run current tests and record which directory they use
  ```bash
  # Before fix - should use ditto_cache (WRONG)
  ```

### Implementation Steps

- [ ] **Step 1:** Edit scheme file to add UI-TESTING argument
  - File: `Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme`
  - Add `<CommandLineArguments>` section to `<TestAction>`
  - Argument: `UI-TESTING`

- [ ] **Step 2:** Commit scheme file change
  ```bash
  git add "Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme"
  git commit -m "Configure unit tests to use separate database directory (ditto_cache_test)"
  ```

- [ ] **Step 3:** Clean test directories
  ```bash
  rm -rf ~/Library/"Application Support"/ditto_cache_test
  rm -rf ~/Library/"Application Support"/ditto_cache_unit_test
  ```

- [ ] **Step 4:** Run unit tests with new configuration
  ```bash
  xcodebuild test \
      -project "Edge Debug Helper.xcodeproj" \
      -scheme "Edge Studio" \
      -destination "platform=macOS,arch=arm64"
  ```

- [ ] **Step 5:** Verify test directory was created
  ```bash
  ls -la ~/Library/"Application Support"/ditto_cache_test/
  # Should contain ditto_encrypted.db
  ```

- [ ] **Step 6:** Verify production database NOT touched
  ```bash
  # Compare timestamp from Step 3 pre-verification
  ```

### Post-Implementation Verification

- [ ] All unit tests pass
- [ ] Production database unchanged
- [ ] Test database exists in `ditto_cache_test/`
- [ ] Add `TestIsolationValidationTests.swift` to test suite
- [ ] New isolation test passes
- [ ] Document change in CLAUDE.md

---

## Documentation Updates Required

### 1. CLAUDE.md - Testing Section

Add test isolation documentation:

```markdown
## Testing

### Test Database Isolation

**CRITICAL: Tests use a separate database directory from production.**

**Directory Structure:**
- Production: `~/Library/Application Support/ditto_cache/ditto_encrypted.db`
- UI Tests: `~/Library/Application Support/ditto_cache_test/ditto_encrypted.db`
- Unit Tests: `~/Library/Application Support/ditto_cache_test/ditto_encrypted.db` (same as UI tests)

**How It Works:**
- All tests run with `UI-TESTING` launch argument
- SQLCipherService checks for this argument and uses `ditto_cache_test` directory
- This ensures tests never contaminate production data

**Verification:**
Run `TestIsolationValidationTests` to verify proper isolation:
```bash
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -only-testing:"Edge Debug HelperTests/TestIsolationValidationTests"
```

**Manual Verification:**
```bash
# Before running tests - note timestamp
stat ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db

# Run tests
xcodebuild test -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio"

# After tests - verify timestamp unchanged
stat ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db
```
```

### 2. TEST_ISOLATION_RESEARCH.md (This File)

Keep this document for reference and historical context.

### 3. SECURECACHE_REMOVAL_PLAN.md

Add new Phase 0 (before all other phases) to verify and fix test isolation.

---

## Rollback Plan

If test isolation changes cause issues:

```bash
# Restore original scheme file
git checkout HEAD -- "Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme"

# Rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean build
```

---

## Related Files

**Test Configuration:**
- `Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme` - Needs UI-TESTING argument
- `Edge Debugg Helper UITests/Ditto_Edge_StudioUITests.swift` - Already sets UI-TESTING

**Test Files (Need Isolation):**
- `Edge Debug Helper Tests/RepositorySQLCipherIntegrationTests.swift`
- `Edge Debug Helper Tests/SQLCipherServiceTests.swift`
- `Edge Debug Helper Tests/DatabaseRepositoryIntegrationTests.swift` (to be removed)

**Production Code (Already Supports Isolation):**
- `Edge Debug Helper/Data/SQLCipherService.swift` - getDatabasePath() checks UI-TESTING
- `Edge Debug Helper/Data/SecureCacheService.swift` - Also checks UI-TESTING (legacy)
- `Edge Debug Helper/Data/DittoManager.swift` - Uses UI-TESTING for ditto data

---

## Timeline

**Phase 0: Test Isolation Fix** - 15 minutes
**Phase 1-8: SecureCacheService Removal** - 30 minutes
**Total:** 45 minutes (was 30 minutes)

---

**Document Status:** ✅ RESEARCH COMPLETE
**Critical Issue:** Test isolation NOT configured for unit tests
**Required Action:** Configure Xcode scheme before running tests
**Risk Level:** HIGH - Tests may contaminate production data

