# Testing Guide

## Test Files

### DQLQueryParserTests.swift

The `DQLQueryParserTests.swift` file contains 38 unit tests for the `DQLQueryParser` utility that powers the hybrid pagination feature.

**Location:** `/SwiftUI/DQLQueryParserTests.swift` (root of SwiftUI directory)

**Current Status:** The test file exists but needs to be added to the test target in Xcode before it can run.

### How to Enable the Tests

1. **Open Xcode:**
   ```bash
   cd SwiftUI
   open "Edge Debug Helper.xcodeproj"
   ```

2. **Locate the Test File:**
   - In the Project Navigator (left sidebar), find `DQLQueryParserTests.swift` at the root level

3. **Add to Test Target:**
   - Select `DQLQueryParserTests.swift`
   - Open the File Inspector (View → Inspectors → File, or Cmd+Option+1)
   - Under "Target Membership" section:
     - ✅ Check "Edge Debug Helper Tests"
     - ❌ Uncheck "Edge Debug Helper" (if checked)

4. **Run Tests:**
   - Press `Cmd+U` to run all tests
   - Or right-click `DQLQueryParserTests` in the test navigator and select "Run"

### Why the Test File Is Separate

The test file is intentionally placed at the SwiftUI root (not in the test directory) to avoid build errors when it's not properly configured in the test target. This way:

- ✅ The main app builds successfully
- ✅ Tests are available when you need them
- ✅ No build errors if test target isn't configured

Once you add it to the test target in Xcode, you can optionally move it to the test directory if you prefer.

## Running Tests

### Run All Tests
```bash
cd SwiftUI
xcodebuild test -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64"
```

### Run Only DQLQueryParser Tests
```bash
cd SwiftUI
xcodebuild test -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:"Edge Debug Helper Tests/DQLQueryParserTests"
```

### Run in Xcode
- Open project in Xcode
- Press `Cmd+U` to run all tests
- Or use Test Navigator (Cmd+6) to run specific tests

## Test Coverage

### DQLQueryParserTests (38 tests)

#### Collection Name Extraction (6 tests)
- Basic SELECT queries
- Queries with COLLECTION keyword
- DELETE and UPDATE queries
- Mixed case queries
- Queries without FROM clause

#### Aggregate Query Detection (21 tests)
- COUNT, SUM, AVG, MIN, MAX functions
- GROUP BY clauses
- DISTINCT queries
- Queries with existing LIMIT/OFFSET
- Non-aggregate queries (should return false)
- Case sensitivity
- Complex queries

#### Pagination Detection (5 tests)
- LIMIT clauses
- OFFSET clauses
- Combined LIMIT and OFFSET
- Queries without pagination
- Case sensitivity

#### Edge Cases (6 tests)
- Complex subqueries
- Field names containing "count"
- Multiple aggregates
- Empty queries
- Whitespace queries
- LIMIT in WHERE clauses

#### Real-World Examples (4 tests)
- Car inventory queries
- Count by category
- Average calculations
- User list queries

## Troubleshooting

### "Compilation search paths unable to resolve module dependency: 'Testing'"

**Problem:** The test file is being compiled as part of the main app target instead of the test target.

**Solution:** Follow the "How to Enable the Tests" steps above to move it to the test target.

### Tests Don't Run

**Problem:** Test target might not be enabled in the scheme.

**Solution:**
1. Open scheme editor (Product → Scheme → Edit Scheme, or Cmd+<)
2. Select "Test" in left sidebar
3. Ensure "Edge Debug Helper Tests" is checked
4. Click "Close"

### Signing Certificate Errors

**Problem:** Tests require code signing but certificate isn't available.

**Solution:** Tests will work in Xcode with local signing. For command-line builds:
1. Disable code signing for tests in build settings, or
2. Run tests only in Xcode using Cmd+U

## Test Philosophy

The tests follow these principles:

1. **Comprehensive Coverage:** Tests cover normal cases, edge cases, and real-world scenarios
2. **Clear Naming:** Test names describe exactly what they're testing
3. **Fast Execution:** All tests are pure logic tests with no I/O or network calls
4. **Isolated:** Each test is independent and doesn't depend on other tests
5. **Documented:** Test names serve as documentation for expected behavior

## Adding New Tests

When adding new functionality to `DQLQueryParser`, follow this pattern:

```swift
@Test("Description of what this tests")
func testFeatureName() async throws {
    let input = "test input"
    let result = DQLQueryParser.methodToTest(input)
    #expect(result == expectedValue)
}
```

**Guidelines:**
- Use descriptive test names
- Test both positive and negative cases
- Include edge cases (empty strings, special characters, etc.)
- Add real-world examples when applicable
- Use `#expect()` for assertions (Swift Testing framework)

## Manual Testing

While unit tests verify the logic, also manually test the hybrid pagination:

### Test Scenario 1: Small Collection
1. Query a collection with <10,000 items
2. Expected: Console shows "Small collection (X items), using in-memory pagination"
3. Verify: Page navigation is instant

### Test Scenario 2: Large Collection
1. Query a collection with >10,000 items
2. Expected: Console shows "Large collection (X items), using server-side pagination"
3. Verify: Slight delay on page navigation

### Test Scenario 3: Aggregate Query
1. Run `SELECT COUNT(*) FROM collection`
2. Expected: No pagination messages in console
3. Verify: Single result returned instantly

### Test Scenario 4: Pre-Paginated Query
1. Run `SELECT * FROM collection LIMIT 50`
2. Expected: Query executed as-is
3. Verify: Exactly 50 results returned

## Continuous Integration

If setting up CI/CD, use this command to run tests:

```bash
#!/bin/bash
set -e

cd SwiftUI

# Clean build
xcodebuild clean -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio"

# Build
xcodebuild build \
  -project "Edge Debug Helper.xcodeproj" \
  -scheme "Edge Studio" \
  -destination "platform=macOS,arch=arm64" \
  -configuration Debug

# Run tests (requires proper signing setup)
xcodebuild test \
  -project "Edge Debug Helper.xcodeproj" \
  -scheme "Edge Studio" \
  -destination "platform=macOS,arch=arm64"
```

**Note:** CI may require additional setup for code signing and test target configuration.

## Test Metrics

After running tests, view coverage:

1. In Xcode, open the Report Navigator (Cmd+9)
2. Select the latest test run
3. Click "Coverage" tab
4. Look for `DQLQueryParser.swift` to see line coverage

**Target Coverage:** >90% for DQLQueryParser methods

## Related Documentation

- **HYBRID_PAGINATION.md** - Complete implementation guide
- **DQLQueryParser.swift** - Source code being tested
- **AppConfigTests.swift** - Example of existing tests in the project
