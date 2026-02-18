# SecureCacheService Removal Plan

**Date:** February 17, 2026
**Updated:** February 17, 2026 (Added Phase 0: Test Isolation Fix)
**Issue:** Legacy `SecureCacheService` still exists but is no longer used in production code
**Root Cause:** Test file `DatabaseRepositoryIntegrationTests.swift` still references old cache service

## ⚠️ CRITICAL SAFETY REQUIREMENT

**MUST complete Phase 0 (Test Isolation Fix) BEFORE removing any code.**

Unit tests currently use the PRODUCTION database directory, risking data contamination. Phase 0 configures tests to use a separate directory (`ditto_cache_test/`) to ensure production data safety.

**See:** `TEST_ISOLATION_RESEARCH.md` for complete analysis.

---

## Current State Analysis

### Production Code Status: ✅ FULLY MIGRATED

**DatabaseRepository** (production):
```swift
actor DatabaseRepository {
    private let sqlCipher = SQLCipherService.shared  // ✅ Using SQLCipher
    // OLD: private let cacheService = SecureCacheService.shared  ❌ REMOVED
}
```

All repositories migrated to SQLCipher:
- ✅ DatabaseRepository
- ✅ HistoryRepository
- ✅ FavoritesRepository
- ✅ SubscriptionsRepository
- ✅ ObservableRepository

### Test Code Status: ❌ NOT MIGRATED

**DatabaseRepositoryIntegrationTests.swift** (test - OUTDATED):
```swift
struct DatabaseRepositoryIntegrationTests {
    let cacheService: SecureCacheService  // ❌ Still using old service
    // Lines 21, 36, 170, 205, 329
}
```

**RepositorySQLCipherIntegrationTests.swift** (test - CURRENT):
```swift
struct RepositorySQLCipherIntegrationTests {
    let sqlCipher: SQLCipherService  // ✅ Using new service
    // Tests the SAME workflows using SQLCipher
}
```

### Files to Remove

1. **SecureCacheService.swift** (358 lines)
   - Location: `SwiftUI/Edge Debug Helper/Data/SecureCacheService.swift`
   - Used only by: `DatabaseRepositoryIntegrationTests.swift`
   - Status: LEGACY CODE

2. **DatabaseRepositoryIntegrationTests.swift** (332 lines)
   - Location: `SwiftUI/Edge Debug Helper Tests/DatabaseRepositoryIntegrationTests.swift`
   - Status: REDUNDANT (superseded by `RepositorySQLCipherIntegrationTests.swift`)

### Why Periphery Didn't Flag It

**Periphery was correct** - `SecureCacheService` IS technically used by test code:

```
[mutator:run] XCTestRetainer (0.000s)
```

The `XCTestRetainer` marks anything used in test targets as "used" to prevent false positives. This is correct behavior but doesn't catch **outdated tests testing legacy implementations**.

---

## Test Coverage Comparison

### DatabaseRepositoryIntegrationTests (OLD - TO DELETE)

Tests using **SecureCacheService** (legacy):

| Test Case | Description | Lines |
|-----------|-------------|-------|
| `testAddDatabaseCreatesDirectoryIfNeeded` | Directory creation on first add | 42-76 |
| `testAddMultipleDatabases` | Multiple databases can coexist | 78-101 |
| `testAddDatabaseStoresCredentialsInKeychain` | Keychain storage | 105-130 |
| `testUpdateDatabaseUpdatesKeychain` | Keychain updates | 132-154 |
| `testAddDatabaseStoresMetadataInCache` | Cache file storage | 158-182 |
| `testDeleteDatabaseRemovesAllData` | Cleanup on delete | 184-208 |
| `testAddDatabaseWithFreshInstall` | Fresh install scenario | 212-252 |
| `testLoadDatabasesWithEmptyCache` | Empty cache handling | 254-271 |
| `testAddDatabaseWithDuplicateId` | Duplicate ID handling | 275-298 |

**Total:** 9 test cases

### RepositorySQLCipherIntegrationTests (NEW - KEEP)

Tests using **SQLCipherService** (current):

| Test Case | Description | Coverage |
|-----------|-------------|----------|
| `testDatabaseRepositoryCRUD` | Create, Read, Update, Delete | ✅ Covers add/update/delete |
| `testHistoryRepositoryPersistence` | History operations | ✅ Per-database data |
| `testFavoritesRepositoryPersistence` | Favorites operations | ✅ Per-database data |
| `testSubscriptionsRepositoryPersistence` | Subscriptions operations | ✅ Per-database data |
| `testObservableRepositoryPersistence` | Observable operations | ✅ Per-database data |
| `testCascadeDeleteRemovesAllData` | CASCADE DELETE validation | ✅ Cleanup on delete |
| `testMultipleRepositoriesWorkTogether` | Cross-repository operations | ✅ Multiple databases |
| `testTestIsolationFromProduction` | Test/production isolation | ✅ Fresh install handling |

**Total:** 8+ test cases

### Coverage Analysis

**RepositorySQLCipherIntegrationTests ALREADY covers:**

| Old Test Scenario | New Test Coverage | Status |
|-------------------|-------------------|--------|
| Directory creation | `testDatabaseRepositoryCRUD` creates DB | ✅ Covered |
| Multiple databases | `testMultipleRepositoriesWorkTogether` | ✅ Covered |
| Keychain storage | Tested in SQLCipherServiceTests | ✅ Covered |
| Keychain updates | `testDatabaseRepositoryCRUD` (update) | ✅ Covered |
| Metadata storage | `testDatabaseRepositoryCRUD` (read) | ✅ Covered |
| Delete cleanup | `testCascadeDeleteRemovesAllData` | ✅ Covered |
| Fresh install | `testTestIsolationFromProduction` | ✅ Covered |
| Empty cache | Implicit in initialization | ✅ Covered |
| Duplicate ID | `testDatabaseRepositoryCRUD` (update) | ✅ Covered |

**Conclusion:** All scenarios from the old test are covered by new SQLCipher tests.

---

## 🚨 CRITICAL PREREQUISITE: Test Isolation

**MUST BE COMPLETED BEFORE ANY OTHER PHASES**

### Current Issue

Unit tests do NOT use a separate database directory from production:
- ✅ **UI Tests**: Use `ditto_cache_test` (properly isolated)
- ❌ **Unit Tests**: Use `ditto_cache` (PRODUCTION directory)

**Risk:** Tests contaminate production data, cleanup failures leave test data in user's app.

**Root Cause:** Xcode test scheme does not pass "UI-TESTING" launch argument to unit tests.

**See:** `TEST_ISOLATION_RESEARCH.md` for complete analysis.

---

## Implementation Plan

### Phase 0: Fix Test Isolation (15 minutes) 🚨 REQUIRED FIRST

**Goal:** Configure unit tests to use separate database directory.

#### Step 1: Verify Current Problem

```bash
# Check if production database exists
ls -la ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db

# Note current timestamp
stat -f "%m" ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db > /tmp/db_timestamp_before.txt
```

#### Step 2: Edit Xcode Scheme

**File:** `SwiftUI/Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme`

**Find the TestAction section** (around line 26):

```xml
<TestAction
   buildConfiguration = "Debug"
   selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
   selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
   shouldUseLaunchSchemeArgsEnv = "YES"
   shouldAutocreateTestPlan = "YES">
```

**Add CommandLineArguments BEFORE Testables:**

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

#### Step 3: Clean Test Directories

```bash
# Remove any existing test directories to start fresh
rm -rf ~/Library/"Application Support"/ditto_cache_test
rm -rf ~/Library/"Application Support"/ditto_cache_unit_test

echo "✅ Test directories cleaned"
```

#### Step 4: Run Test to Verify Isolation

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Run a single test
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64" \
    -only-testing:"Edge Debug HelperTests/RepositorySQLCipherIntegrationTests/testDatabaseRepositoryCRUD"
```

#### Step 5: Verify Production Database NOT Touched

```bash
# Check production database timestamp (should be UNCHANGED)
BEFORE=$(cat /tmp/db_timestamp_before.txt)
AFTER=$(stat -f "%m" ~/Library/"Application Support"/ditto_cache/ditto_encrypted.db 2>/dev/null || echo "0")

if [ "$BEFORE" = "$AFTER" ]; then
    echo "✅ SUCCESS: Production database not touched"
else
    echo "❌ FAILURE: Production database was modified - DO NOT PROCEED"
    exit 1
fi
```

#### Step 6: Verify Test Database Created

```bash
# Verify test database was created
if [ -f ~/Library/"Application Support"/ditto_cache_test/ditto_encrypted.db ]; then
    echo "✅ SUCCESS: Test database created in ditto_cache_test/"
    ls -lh ~/Library/"Application Support"/ditto_cache_test/
else
    echo "❌ FAILURE: Test database not found - DO NOT PROCEED"
    exit 1
fi
```

#### Step 7: Commit Scheme Change

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio

git add "SwiftUI/Edge Debug Helper.xcodeproj/xcshareddata/xcschemes/Edge Studio.xcscheme"
git commit -m "Configure unit tests to use separate database directory (ditto_cache_test)

- Adds UI-TESTING launch argument to TestAction in scheme
- Ensures unit tests use ditto_cache_test/ (not production ditto_cache/)
- Prevents test data contamination of production database
- See: TEST_ISOLATION_RESEARCH.md for detailed analysis"

echo "✅ Scheme change committed"
```

**Success Criteria Phase 0:**
- ✅ Scheme file updated with UI-TESTING argument
- ✅ Production database timestamp unchanged after test run
- ✅ Test database created in `ditto_cache_test/`
- ✅ Scheme change committed to git

**⚠️ DO NOT PROCEED TO PHASE 1 UNTIL ALL PHASE 0 CHECKS PASS**

---

### Phase 1: Verification (5 minutes)

**Goal:** Confirm new tests provide equivalent coverage.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Run ONLY the new SQLCipher integration tests
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64" \
    -only-testing:"Edge Debug HelperTests/RepositorySQLCipherIntegrationTests"
```

**Success Criteria:**
- ✅ All tests pass
- ✅ No failures or skipped tests
- ✅ Coverage includes CRUD, cascade delete, isolation

### Phase 2: Remove Outdated Test (2 minutes)

**Goal:** Delete the legacy test file.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Remove outdated test file
rm "Edge Debug Helper Tests/DatabaseRepositoryIntegrationTests.swift"

echo "✅ Removed DatabaseRepositoryIntegrationTests.swift"
```

**Verification:**
```bash
# Verify file is gone
ls "Edge Debug Helper Tests/" | grep -i "DatabaseRepositoryIntegrationTests"
# Should return nothing
```

### Phase 3: Remove SecureCacheService (2 minutes)

**Goal:** Delete the legacy cache service.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Remove legacy service
rm "Edge Debug Helper/Data/SecureCacheService.swift"

echo "✅ Removed SecureCacheService.swift"
```

**Verification:**
```bash
# Verify no references remain in code
grep -r "SecureCacheService" "Edge Debug Helper" --include="*.swift" | grep -v "MIGRATION"
# Should return nothing (except migration docs)
```

### Phase 4: Build Verification (3 minutes)

**Goal:** Ensure project builds successfully.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Clean build
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean

# Build project
xcodebuild build \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64"
```

**Success Criteria:**
- ✅ Build succeeds with no errors
- ✅ No "undefined symbol" errors for SecureCacheService
- ✅ No import errors

### Phase 5: Full Test Suite (5 minutes)

**Goal:** Verify all tests still pass.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI

# Run all tests
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64"
```

**Success Criteria:**
- ✅ All remaining tests pass
- ✅ No test failures introduced
- ✅ Test count reduced by 9 (removed tests)

### Phase 6: Update Documentation (5 minutes)

**Goal:** Document the removal in migration docs.

**Update:** `SwiftUI/SQLCIPHER_MIGRATION_COMPLETE.md`

Add to the end of the file:

```markdown
## Legacy Code Cleanup (February 17, 2026)

### Removed Files

1. **SecureCacheService.swift**
   - Location: `Data/SecureCacheService.swift` (358 lines)
   - Reason: Replaced by SQLCipherService, no longer used in production
   - Last used by: DatabaseRepositoryIntegrationTests (test only)

2. **DatabaseRepositoryIntegrationTests.swift**
   - Location: `Edge Debug Helper Tests/DatabaseRepositoryIntegrationTests.swift` (332 lines)
   - Reason: Tested legacy SecureCacheService implementation
   - Superseded by: RepositorySQLCipherIntegrationTests (SQLCipher-based)

### Test Coverage Confirmation

All test scenarios from DatabaseRepositoryIntegrationTests are covered by:
- RepositorySQLCipherIntegrationTests (integration tests)
- SQLCipherServiceTests (unit tests)
- Individual repository tests

**Migration Status:** ✅ 100% COMPLETE - No legacy JSON cache code remains
```

### Phase 7: Periphery Verification (3 minutes)

**Goal:** Confirm SecureCacheService is now flagged as removed.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio

# Run Periphery scan
periphery scan \
    --project "SwiftUI/Edge Debug Helper.xcodeproj" \
    --schemes "Edge Studio" \
    --format xcode

# Should show: "No unused code detected"
# AND SecureCacheService should not exist in scan
```

**Success Criteria:**
- ✅ Periphery scan completes successfully
- ✅ No errors about missing SecureCacheService
- ✅ Scan result: "No unused code detected"

### Phase 8: Update Periphery Report (5 minutes)

**Goal:** Regenerate Periphery baseline after cleanup.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio

# Regenerate baseline
periphery scan \
    --project "SwiftUI/Edge Debug Helper.xcodeproj" \
    --schemes "Edge Studio" \
    --format json \
    > reports/periphery/baselines/periphery-baseline-20260217-post-cleanup.json

# Update active baseline
cp reports/periphery/baselines/periphery-baseline-20260217-post-cleanup.json \
   .periphery_baseline.json

echo "✅ Baseline updated after SecureCacheService removal"
```

**Update:** `reports/periphery/UNUSED_CODE_REPORT_2026-02-17.md`

Add addendum:

```markdown
---

## Addendum: Post-Cleanup Scan (February 17, 2026)

### Files Removed

Following the initial scan, a manual code review identified legacy code that was only used in outdated tests:

1. **SecureCacheService.swift** (358 lines)
   - Production code migrated to SQLCipherService
   - Only referenced by legacy test file
   - Periphery correctly retained it due to XCTestRetainer

2. **DatabaseRepositoryIntegrationTests.swift** (332 lines)
   - Tested legacy JSON cache implementation
   - Superseded by RepositorySQLCipherIntegrationTests

**Total Lines Removed:** 690 lines

### Post-Cleanup Scan Results

**New Codebase Metrics:**
- **Files Analyzed:** 79 Swift files (was 80)
- **Lines of Code:** ~21,325 lines (was ~22,015)
- **Unused Declarations:** 0 (confirmed)

**Lesson Learned:**

Periphery's XCTestRetainer correctly marks test-only code as "used," but it cannot detect:
- Tests that are **outdated** (testing old implementations)
- Tests that are **redundant** (superseded by better tests)

**Solution:** Combine automated scans with:
- Manual code reviews during refactoring
- Test coverage analysis
- Migration documentation review
```

---

## Verification Checklist

Use this checklist to validate each phase:

### Phase 0: Test Isolation Fix 🚨 REQUIRED FIRST
- [ ] Noted production database timestamp before tests
- [ ] Edited Xcode scheme to add UI-TESTING argument
- [ ] Cleaned test directories (ditto_cache_test, ditto_cache_unit_test)
- [ ] Ran single test successfully
- [ ] Production database timestamp UNCHANGED after test
- [ ] Test database created in ditto_cache_test/
- [ ] Scheme change committed to git
- [ ] ⚠️ ALL CHECKS PASSED - SAFE TO PROCEED TO PHASE 1

### Phase 1: Verification
- [ ] RepositorySQLCipherIntegrationTests runs successfully
- [ ] All test cases pass (no failures)
- [ ] Test output shows successful CRUD operations

### Phase 2: Remove Outdated Test
- [ ] DatabaseRepositoryIntegrationTests.swift deleted
- [ ] File no longer appears in project navigator
- [ ] File no longer in git status

### Phase 3: Remove SecureCacheService
- [ ] SecureCacheService.swift deleted
- [ ] No grep matches for "SecureCacheService" in source code
- [ ] Only migration docs reference the old service

### Phase 4: Build Verification
- [ ] Clean build succeeds
- [ ] No compiler errors
- [ ] No "undefined symbol" linker errors

### Phase 5: Full Test Suite
- [ ] All tests pass
- [ ] Test count reduced (9 fewer tests)
- [ ] No new test failures introduced

### Phase 6: Update Documentation
- [ ] SQLCIPHER_MIGRATION_COMPLETE.md updated
- [ ] Removal reasons documented
- [ ] Test coverage confirmation added

### Phase 7: Periphery Verification
- [ ] Periphery scan runs successfully
- [ ] No errors about SecureCacheService
- [ ] Result: "No unused code detected"

### Phase 8: Update Periphery Report
- [ ] New baseline generated
- [ ] Active baseline updated
- [ ] Report addendum added
- [ ] New metrics documented (79 files, ~21,325 lines)

---

## Rollback Plan

If issues are discovered after removal:

### Emergency Rollback

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio

# Restore files from git
git checkout HEAD -- "SwiftUI/Edge Debug Helper/Data/SecureCacheService.swift"
git checkout HEAD -- "SwiftUI/Edge Debug Helper Tests/DatabaseRepositoryIntegrationTests.swift"

# Rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean build -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio"
```

**When to rollback:**
- Build fails with unresolved errors
- Tests fail that were previously passing
- Production code references are discovered

**After rollback:**
- Investigate root cause
- Update this plan with additional verification steps
- Re-attempt removal after fixing issues

---

## Timeline

**Total Estimated Time:** 45 minutes (was 30 minutes - added Phase 0)

| Phase | Duration | Cumulative |
|-------|----------|------------|
| **0. Test Isolation Fix** 🚨 | **15 min** | **15 min** |
| 1. Verification | 5 min | 20 min |
| 2. Remove Test | 2 min | 22 min |
| 3. Remove Service | 2 min | 24 min |
| 4. Build Verification | 3 min | 27 min |
| 5. Full Test Suite | 5 min | 32 min |
| 6. Update Documentation | 5 min | 37 min |
| 7. Periphery Verification | 3 min | 40 min |
| 8. Update Report | 5 min | 45 min |

---

## Success Criteria

### Phase 0: Test Isolation (MUST PASS FIRST)
- ✅ Xcode scheme configured with UI-TESTING argument
- ✅ Production database NOT touched during test runs
- ✅ Test database created in separate directory (ditto_cache_test/)
- ✅ Scheme change committed to git

### Phases 1-8: Code Removal (After Phase 0 Passes)
- ✅ SecureCacheService.swift removed from codebase
- ✅ DatabaseRepositoryIntegrationTests.swift removed from test suite
- ✅ All remaining tests pass
- ✅ Project builds successfully
- ✅ No references to SecureCacheService in source code
- ✅ Periphery scan shows "No unused code detected"
- ✅ Documentation updated with removal notes
- ✅ New baseline generated
- ✅ Codebase reduced by 690 lines

---

## Related Documentation

- **Migration Docs:**
  - `SwiftUI/SQLCIPHER_MIGRATION_COMPLETE.md` - SQLCipher migration details
  - `SwiftUI/PHASE_2_COMPLETE.md` - Phase 2 completion notes

- **Test Files:**
  - `RepositorySQLCipherIntegrationTests.swift` - Current integration tests (KEEP)
  - `SQLCipherServiceTests.swift` - SQLCipher unit tests (KEEP)
  - `DatabaseRepositoryIntegrationTests.swift` - Legacy tests (DELETE)

- **Periphery Reports:**
  - `reports/periphery/UNUSED_CODE_REPORT_2026-02-17.md` - Initial scan report
  - `.periphery_baseline.json` - Active baseline (to be updated)

---

## Notes

### Why This Happened

1. **SQLCipher migration completed** (Jan-Feb 2026) - production code moved to encrypted DB
2. **Test suite not updated** - DatabaseRepositoryIntegrationTests still used old cache
3. **Periphery correctly retained it** - XCTestRetainer marks test-only code as "used"
4. **Manual review caught it** - User questioned why SecureCacheService still existed

### Critical Discovery (February 17, 2026)

**During plan development, a CRITICAL issue was discovered:**

Unit tests were NOT using a separate database directory from production:
- ❌ Unit tests used `ditto_cache` (PRODUCTION directory)
- ✅ UI tests used `ditto_cache_test` (properly isolated)

**Root Cause:** Xcode test scheme did not pass "UI-TESTING" launch argument to unit tests.

**Impact:** Tests could contaminate production database, leaving test data in user's app.

**Resolution:** Added Phase 0 to configure proper test isolation BEFORE code removal.

**Deep Research:** See `TEST_ISOLATION_RESEARCH.md` for complete analysis (120+ lines).

### Lessons Learned

1. **Update tests during migrations** - don't leave test suite on old implementation
2. **Periphery has limitations** - can't detect outdated/redundant tests
3. **Manual review is essential** - automated tools complement, don't replace, code review
4. **Test coverage analysis helps** - compare old vs new test coverage during refactoring
5. **🚨 VERIFY TEST ISOLATION** - Always ensure tests use separate data from production
6. **Check Xcode schemes** - Launch arguments and environment variables affect test behavior
7. **Document test setup** - Make test isolation requirements explicit

### Future Prevention

1. **Migration checklist item** - "Update all tests to use new implementation"
2. **Post-migration verification** - grep for old service names in test files
3. **Quarterly test review** - identify redundant/outdated tests
4. **Document superseded tests** - note when tests are replaced by better versions
5. **🚨 Test isolation validation** - Add automated tests that verify test/production separation
6. **Scheme configuration review** - Audit test schemes for proper isolation setup

---

**Plan Created:** February 17, 2026
**Status:** ✅ READY FOR EXECUTION
**Estimated Effort:** 30 minutes
**Risk Level:** LOW (tests confirm coverage, easy rollback)

