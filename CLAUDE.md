# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when worki:wng with code in this repository.

## Project Overview

Edge Debug Helper is a comprehensive SwiftUI application for macOS and iPadOS, providing a production-ready GUI for querying and managing Ditto databases.
## Screenshots

From time to time to debug or design new features screenshots or design mock ups will always be stored in the screens folder of the repository.  If you are told
there is a screenshot named and then a filename always asssume it's in the screens folder.

## Testing Requirements

**CRITICAL RULE: All tests MUST be runnable in Xcode and MUST pass after any code changes.**

### General Testing Rules
- Tests must be properly configured to compile and run in the Xcode test target
- Tests must NOT be moved to temporary directories or locations outside the project
- If tests produce warnings about being in the wrong target, fix the Xcode project configuration (using `membershipExceptions` in project.pbxproj for File System Synchronized targets)
- Tests that cannot be run in Xcode are not acceptable and the configuration must be fixed
- Use Swift Testing framework (`import Testing`) for all new unit tests, not XCTest
- Use XCTest for UI tests (XCUITest framework)

### Running Tests After Changes

**CRITICAL: Always run tests after making changes to validate the app still works.**

```bash
# Run all tests (unit + UI tests)
cd SwiftUI
./run_ui_tests.sh

# Or run via Xcode
# Product → Test (⌘U)

# Or run via command line
xcodebuild test -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64"
```

### UI Tests

Comprehensive UI tests validate:
- App launches successfully
- Database list screen displays correctly
- App selection opens MainStudioView
- All navigation menu items (Subscriptions, Collections, Observer, Ditto Tools) work
- Each sidebar and detail view renders properly

**Note:** Navigation tests will skip if no apps are configured (expected behavior).

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

    // ACT: Select first database
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
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")).count
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

/// Adds a single database by automating the AppEditorView form
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
        .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'"))
        .firstMatch
    firstCard.tap()

    // ... rest of test
}
```

**Benefits:**
- ✅ Works reliably with sandboxing
- ✅ Tests the real user experience
- ✅ Easy to debug visually
- ✅ No app initialization changes needed

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

**Example 1: AuthModePicker in AppEditorView**
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

**Documentation:** See `ADDBUTTON_FIRSTMATCH_FIX.md`

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

    // Find and tap first database
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
  - `DittoManager_LocalSubscription.swift`: Local database subscriptions for app state
  - `DittoManager_DittoAppConfig.swift`: App configuration management
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
  - `ContentView.swift`: Root view with app selection
  - `MainStudioView.swift`: Primary interface with navigation sidebar and detail views
    - Sync detail view uses native TabView with three tabs: Peers List, Presence Viewer, Settings
    - Tab selection persists when navigating between menu items
    - Threading optimizations for cleanup operations using TaskGroup
  - `AppEditorView.swift`: App configuration editor
  - **Tabs/**: Tab-specific views like `ObserversTabView.swift`
  - **Tools/**: Utility views (presence, disk usage, peers, permissions)
  
- **Components** (`Components/` folder): Reusable UI components
  - Query editor and results viewers
  - App and subscription cards/lists
  - Pagination controls and secure input fields
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
- Multi-app connection management with local storage
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
  ├─ onAppear: loadApps() - loads database configurations
  │
  ├──→ DATABASE LIST SCREEN (when isMainStudioViewPresented = false)
  │    │
  │    ├─ Component: DatabaseList
  │    │  └─ Accessibility ID: "DatabaseList" (macOS only)
  │    │
  │    ├─ Loading State: ProgressView("Loading Database Configs...")
  │    ├─ Empty State: ContentUnavailableView("No Database Configurations")
  │    │
  │    └─ Normal State: List of database cards
  │       ├─ Each card: DatabaseCard component
  │       ├─ Accessibility ID: "AppCard_{name}" (macOS only)
  │       └─ User taps card →
  │          ├─ showMainStudio(dittoApp) called
  │          ├─ selectedDittoAppConfig = dittoApp
  │          ├─ hydrateDittoSelectedApp() - async setup
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
| Individual Database Card | `"AppCard_{name}"` | macOS only | Each selectable database |
| Sidebar Navigation Picker | `"NavigationSegmentedPicker"` | Both | Sidebar menu switcher |
| Inspector Toggle Button | `"Toggle Inspector"` | Both | Show/hide inspector |
| Inspector Navigation Picker | `"InspectorSegmentedPicker"` | Both | Inspector menu |

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

   // 3. Find and tap a database card
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

- macOS 15+ with Xcode 26.2+ or Xcode 16.5+ with Swift 6.2
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
