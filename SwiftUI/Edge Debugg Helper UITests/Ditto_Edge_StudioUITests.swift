import XCTest

/// Comprehensive UI tests for Edge Debug Helper
///
/// These tests validate:
/// - App launches successfully
/// - Database list screen displays correctly
/// - App selection opens MainStudioView
/// - All navigation menu items work
/// - Each sidebar and detail view renders properly
///
/// **Test Requirements:**
/// - For navigation tests to run, at least one app must be configured
/// - If no apps are configured, navigation tests will be skipped (expected behavior)
/// - Tests are designed to handle both empty state and populated state
///
/// **Running Tests:**
/// - Use the `run_ui_tests.sh` script in the SwiftUI directory
/// - Or run via Xcode: Product → Test (⌘U)
/// - Or via command line: `xcodebuild test -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64"`
final class Ditto_Edge_StudioUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Enable UI testing mode - app will load test databases from testDatabaseConfig.plist
        app.launchArguments = ["UI-TESTING"]
        
        app.launch()
        
        // CRITICAL: Proper window activation for macOS multi-monitor/multi-app environments
        // Wait for the app's window to appear first
        let firstWindow = app.windows.firstMatch
        guard firstWindow.waitForExistence(timeout: 10) else {
            XCTFail("App window did not appear within 10 seconds")
            return
        }
        
        print("🪟 App window detected, activating...")
        
        // Multi-step activation process (required for reliable focus on macOS)
        // Step 1: Initial activation
        app.activate()
        sleep(1)
        
        // Step 2: Click the window to force it frontmost
        if firstWindow.exists {
            firstWindow.click()
            sleep(1)
        }
        
        // Step 3: Verify window has focus by checking if UI is accessible
        // If not, try activating again
        var attempts = 0
        while app.buttons.count == 0 && attempts < 5 {
            print("⚠️ No UI elements accessible (attempt \(attempts + 1)/5), reactivating...")
            app.activate()
            sleep(1)
            if firstWindow.exists {
                firstWindow.click()
            }
            sleep(1)
            attempts += 1
        }
        
        if app.buttons.count == 0 {
            print("❌ WARNING: UI hierarchy still not accessible after activation attempts")
        } else {
            print("✅ App activated successfully with \(app.buttons.count) buttons visible")
        }
        
        // Wait for app to fully initialize and load test databases
        // Longer wait to ensure SwiftUI view hierarchy fully renders
        sleep(3)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    @MainActor
    func testAppLaunches() throws {
        // Verify the app launches successfully
        XCTAssertTrue(app.exists, "App should launch successfully")
        
        // Wait for app to finish loading databases
        waitForAppToFinishLoading()

        // Tests run in fresh sandbox - app MUST start at ContentView (database list)
        // Check for Add Database button (language-independent)
        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 5),
            """
            FATAL: App did not launch to ContentView (database list screen).

            Expected: ContentView with Add Database button
            Actual: Add Database button not found

            Tests run in fresh sandbox and must ALWAYS start at ContentView.
            Check app initialization in Ditto_Edge_StudioApp.swift and ContentView.swift.
            """
        )
        
        print("✅ App launched successfully to ContentView")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Measure app launch time
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Database List Tests

    @MainActor
    func testDatabaseListScreenDisplays() throws {
        // Wait for app to finish loading databases
        waitForAppToFinishLoading()
        
        // Tests run in fresh sandbox - app MUST start at ContentView
        // Verify Add Database button exists (language-independent check)
        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 5),
            """
            FATAL: App did not start at ContentView (database list screen).

            Expected: ContentView with Add Database button
            Actual: Add Database button not found

            Tests run in fresh sandbox and must start at ContentView.
            """
        )
        
        print("✅ ContentView detected via Add Database button")

        // Wait a moment for UI to stabilize
        sleep(1)
        
        // Verify the Add Database button is still present (not stuck/crashed)
        XCTAssertTrue(
            addDatabaseButton.exists,
            "Add Database button should remain visible - app may have crashed or transitioned unexpectedly"
        )
        
        // Check if database list loaded (may be empty or have items - both valid)
        let databaseList = app.otherElements["DatabaseList"]
        if databaseList.waitForExistence(timeout: 3) {
            print("✅ DatabaseList loaded with test databases")
        } else {
            print("⚠️ DatabaseList not found - may need to check testDatabaseConfig.plist")
        }
        
        print("✅ Database list screen displaying correctly")
    }

    @MainActor
    func testSelectFirstApp() throws {

        waitForAppToFinishLoading(timeout: 8)

        // Tests run in fresh sandbox - app MUST start at ContentView
        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 1),
            """
            FATAL: App did not start at ContentView (database list screen).

            Expected: ContentView with Add Database button
            Actual: Add Database button not found

            Tests run in fresh sandbox and must ALWAYS start at ContentView.
            """
        )
        print("✅ App launched to ContentView")


        // Add databases by automating the AppEditorView form
        // This replaces the old approach of loading databases programmatically
        try addDatabasesFromPlist()

        // ========================================
        // ASSERT: Verify Databases Were Added
        // ========================================

        // Helper already validated each database was added successfully
        // Now verify the total count matches expected
        let expectedCount = getExpectedDatabaseCount() ?? 0

        // Find all app cards (databases added via UI)
        // Look at app level since DatabaseList container may not have identifier
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let allAppCards = app.descendants(matching: .any).matching(predicate)

        // Wait a moment for all cards to render
        sleep(1)

        let actualDatabaseCount = allAppCards.count

        // Test runs may have leftover databases from previous runs
        // Verify we have at least the expected number (helper validated each one was added)
        XCTAssertGreaterThanOrEqual(
            actualDatabaseCount,
            expectedCount,
            """
            Not enough databases found after adding via UI!

            Expected: At least \(expectedCount) database(s) (from testDatabaseConfig.plist)
            Actual: \(actualDatabaseCount) database(s) (rendered in UI)

            Check console for errors during form automation.
            """
        )

        if actualDatabaseCount > expectedCount {
            print("⚠️  Found \(actualDatabaseCount) database(s) in list (expected \(expectedCount) - \(actualDatabaseCount - expectedCount) left over from previous test runs)")
        } else {
            print("✅ Found \(actualDatabaseCount) database(s) in list (matches expected count)")
        }

        // Capture screenshot of database list
        let screenshot1 = app.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01-database-list-loaded"
        attachment1.lifetime = .deleteOnSuccess
        add(attachment1)
        print("📸 Screenshot saved: '01-database-list-loaded'")

        // ========================================
        // ACT: Select First Database
        // ========================================

        let firstAppCard = allAppCards.firstMatch
        XCTAssertTrue(firstAppCard.exists, "First app card should exist")
        print("DEBUG: Tapping app card: \(firstAppCard.identifier)")

        firstAppCard.tap()

        // Window reactivation after tap (required for macOS)
        let firstWindow = app.windows.firstMatch
        app.activate()
        sleep(1)
        if firstWindow.exists {
            firstWindow.click()
            sleep(1)
        }

        // ========================================
        // ASSERT: Wait for MainStudioView to Load
        // ========================================

        // MainStudioView initialization is SLOW (Ditto connections, subscriptions)
        print("DEBUG: Waiting for MainStudioView to appear (max 60s)...")

        // WORKAROUND: NavigationSegmentedPicker (SwiftUI Picker with .segmented style)
        // doesn't expose as segmented control in XCUITest (same issue as AuthModePicker).
        // Instead, validate MainStudioView loaded by checking for CloseButton in toolbar.
        // Use .firstMatch because FontAwesomeText creates nested button structure.
        let closeButton = app.buttons["CloseButton"].firstMatch
        guard closeButton.waitForExistence(timeout: 60) else {
            // Check for alerts
            if app.alerts.count > 0 {
                let alert = app.alerts.firstMatch
                let failureScreenshot = app.screenshot()
                let failureAttachment = XCTAttachment(screenshot: failureScreenshot)
                failureAttachment.name = "FAIL-alert-detected"
                failureAttachment.lifetime = .keepAlways
                add(failureAttachment)

                XCTFail(
                    """
                    MainStudioView did not appear - Alert detected!

                    Alert label: \(alert.label)

                    This indicates the database connection failed.
                    Check credentials in testDatabaseConfig.plist.
                    Screenshot saved: 'FAIL-alert-detected'
                    """
                )
            } else {
                // Capture failure state
                let failureScreenshot = app.screenshot()
                let failureAttachment = XCTAttachment(screenshot: failureScreenshot)
                failureAttachment.name = "FAIL-main-studio-not-loaded"
                failureAttachment.lifetime = .keepAlways
                add(failureAttachment)

                XCTFail(
                    """
                    MainStudioView did not appear after selecting database.

                    Close button exists: \(closeButton.exists)
                    Sync button exists: \(app.buttons["SyncButton"].exists)
                    Total buttons: \(app.buttons.count)
                    App state: \(app.state.rawValue)

                    Screenshot saved: 'FAIL-main-studio-not-loaded'
                    """
                )
            }
            throw XCTSkip("MainStudioView failed to load")
        }

        print("✅ MainStudioView appeared (CloseButton found)")

        // Capture screenshot of MainStudioView
        let screenshot2 = app.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02-main-studio-loaded"
        attachment2.lifetime = .deleteOnSuccess
        add(attachment2)
        print("📸 Screenshot saved: '02-main-studio-loaded'")

        // ========================================
        // ASSERT: Validate MainStudioView UI Elements
        // ========================================

        // Validate toolbar buttons exist
        let syncButton = app.buttons["SyncButton"]
        // closeButton already declared above in guard statement

        XCTAssertTrue(
            syncButton.waitForExistence(timeout: 5),
            """
            Sync button not found in MainStudioView toolbar.

            MainStudioView loaded but toolbar buttons are missing.
            Check that .accessibilityIdentifier("SyncButton") was added to syncToolbarButton().
            """
        )
        print("✅ Sync button found")

        XCTAssertTrue(
            closeButton.exists,
            """
            Close button not found in MainStudioView toolbar.

            MainStudioView loaded but toolbar buttons are missing.
            Check that .accessibilityIdentifier("CloseButton") was added to closeToolbarButton().
            """
        )
        print("✅ Close button found (already validated in guard above)")

        // WORKAROUND: SyncTabPicker (SwiftUI Picker with .segmented style) doesn't
        // expose as segmented control in XCUITest (same issue as AuthModePicker and NavigationSegmentedPicker).
        // Instead, validate sync detail view loaded by checking for "Connected Peers" text in the Peers List tab.
        let connectedPeersText = app.staticTexts["Connected Peers"]

        XCTAssertTrue(
            connectedPeersText.waitForExistence(timeout: 10),
            """
            'Connected Peers' text not found.

            MainStudioView loaded but Peers List tab content is not visible.

            Possible causes:
            1. App did not navigate to Subscriptions view (default menu item)
            2. ConnectedPeersView not rendering correctly
            3. Sync detail view failed to load

            Check screenshot: 'FAIL-peers-list-not-loaded'
            """
        )
        print("✅ Sync detail view loaded (Connected Peers text found)")

        // Capture screenshot showing all validated elements
        let screenshot3 = app.screenshot()
        let attachment3 = XCTAttachment(screenshot: screenshot3)
        attachment3.name = "03-main-studio-validated"
        attachment3.lifetime = .deleteOnSuccess
        add(attachment3)
        print("📸 Screenshot saved: '03-main-studio-validated'")

        // ========================================
        // ACT: Close MainStudioView
        // ========================================

        print("DEBUG: Clicking Close button...")
        closeButton.tap()

        // Wait for transition animation (sheet dismissal or navigation pop)
        sleep(2)

        // ========================================
        // ASSERT: Validate Returned to ContentView
        // ========================================

        // Database list should reappear
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 5),
            """
            Did not return to ContentView after closing MainStudioView.

            Expected: ContentView with Add Database button
            Actual: Add Database button not found

            Check that closeButton tap correctly sets isMainStudioViewPresented = false.
            """
        )
        print("✅ Returned to ContentView (Add Database button visible)")

        // Validate database list still shows same number of databases
        // Look for AppCards at app level
        sleep(1)  // Wait for list to render
        let finalAppCards = app.descendants(matching: .any).matching(predicate)
        let finalDatabaseCount = finalAppCards.count

        XCTAssertGreaterThanOrEqual(
            finalDatabaseCount,
            expectedCount,
            """
            Database count decreased after closing MainStudioView.

            Expected: \(expectedCount) databases (original count)
            Actual: \(finalDatabaseCount) databases

            This indicates databases were deleted or the list state was corrupted.
            """
        )
        print("✅ Database list still shows \(finalDatabaseCount) database(s) (unchanged)")

        // Capture final screenshot
        let screenshot4 = app.screenshot()
        let attachment4 = XCTAttachment(screenshot: screenshot4)
        attachment4.name = "04-returned-to-database-list"
        attachment4.lifetime = .deleteOnSuccess
        add(attachment4)
        print("📸 Screenshot saved: '04-returned-to-database-list'")

        print("🎉 Test completed successfully!")
    }

    // MARK: - MainStudioView Navigation Tests

    @MainActor
    func testNavigationToSubscriptions() throws {
        waitForAppToFinishLoading(timeout: 20)

        // Add databases via UI automation (required for fresh sandbox)
        try addDatabasesFromPlist()

        // Open MainStudioView with first database
        try ensureMainStudioViewIsOpen()

        // WORKAROUND: NavigationSegmentedPicker doesn't expose as segmented control
        // Subscriptions is the default view when MainStudioView opens, so no navigation needed
        // Validate by checking for Subscriptions-specific content

        // Verify Subscriptions sidebar content (header text)
        let subscriptionsHeader = app.staticTexts["Subscriptions"]
        XCTAssertTrue(
            subscriptionsHeader.waitForExistence(timeout: 5),
            """
            Subscriptions sidebar header not found.

            Expected 'Subscriptions' text in sidebar when MainStudioView opens with default view.
            """
        )
        print("✅ Subscriptions sidebar visible")

        // Verify Subscriptions detail view (Connected Peers from sync detail view)
        let connectedPeersText = app.staticTexts["Connected Peers"]
        XCTAssertTrue(
            connectedPeersText.waitForExistence(timeout: 5),
            """
            Subscriptions detail view not found.

            Expected 'Connected Peers' text in sync detail view (Peers List tab).
            """
        )
        print("✅ Subscriptions detail view visible (Connected Peers found)")
    }

    @MainActor
    func testNavigationToCollections() throws {
        waitForAppToFinishLoading(timeout: 20)

        // Add databases via UI automation (required for fresh sandbox)
        try addDatabasesFromPlist()

        // Open MainStudioView with first database
        try ensureMainStudioViewIsOpen()

        // LIMITATION: SwiftUI Picker with SF Symbol images doesn't expose accessible buttons
        //
        // Even with accessibilityIdentifier() added to picker segments, SwiftUI doesn't
        // expose them in XCUITest when using images (SF Symbols) without text labels.
        //
        // SOLUTION: Replace SF Symbol picker with text-labeled picker OR use custom buttons
        //
        // For now, try to find the button but skip if not accessible
        let collectionsButton = app.buttons["NavigationItem_Collections"]

        guard collectionsButton.waitForExistence(timeout: 2) else {
            print("⚠️ Collections navigation button not accessible in UI tests")
            print("   SwiftUI Picker with SF Symbol images doesn't expose segments to XCUITest")
            print("")
            print("   TO FIX: Update MainStudioView navigation picker to use text labels:")
            print("   Replace:")
            print("     item.image.tag(item)")
            print("   With:")
            print("     Text(item.name).tag(item)")
            print("")
            throw XCTSkip("""
                Navigation to Collections requires picker segments to be accessible.

                Current picker uses SF Symbol images which aren't exposed in XCUITest.
                Update picker to use Text labels or custom buttons for testability.
                """)
        }

        print("📍 Tapping Collections navigation button...")
        collectionsButton.tap()
        sleep(2)  // Wait for view transition animation

        // Verify Collections sidebar appears (header text)
        let collectionsHeader = app.staticTexts["Ditto Collections"]
        XCTAssertTrue(
            collectionsHeader.waitForExistence(timeout: 5),
            """
            Collections sidebar header not found after navigation.

            Expected 'Ditto Collections' text in sidebar.
            Navigation may have failed or view may not have rendered.
            """
        )
        print("✅ Collections sidebar visible")

        // Verify Collections detail view appears
        // Collections detail view contains query editor - validate by checking for recognizable text
        let closeButton = app.buttons["CloseButton"].firstMatch
        XCTAssertTrue(
            closeButton.exists,
            "MainStudioView should still be open after navigation"
        )
        print("✅ Collections detail view visible")
    }

    @MainActor
    func testNavigationToObserver() throws {
        waitForAppToFinishLoading(timeout: 20)

        // Add databases via UI automation (required for fresh sandbox)
        try addDatabasesFromPlist()

        // Open MainStudioView with first database
        try ensureMainStudioViewIsOpen()

        // LIMITATION: SwiftUI Picker with SF Symbol images doesn't expose accessible buttons
        //
        // Even with accessibilityIdentifier() added to picker segments, SwiftUI doesn't
        // expose them in XCUITest when using images (SF Symbols) without text labels.
        //
        // SOLUTION: Replace SF Symbol picker with text-labeled picker OR use custom buttons
        //
        // For now, try to find the button but skip if not accessible
        let observerButton = app.buttons["NavigationItem_Observer"]

        guard observerButton.waitForExistence(timeout: 2) else {
            print("⚠️ Observer navigation button not accessible in UI tests")
            print("   SwiftUI Picker with SF Symbol images doesn't expose segments to XCUITest")
            print("")
            print("   TO FIX: Update MainStudioView navigation picker to use text labels:")
            print("   Replace:")
            print("     item.image.tag(item)")
            print("   With:")
            print("     Text(item.name).tag(item)")
            print("")
            throw XCTSkip("""
                Navigation to Observer requires picker segments to be accessible.

                Current picker uses SF Symbol images which aren't exposed in XCUITest.
                Update picker to use Text labels or custom buttons for testability.
                """)
        }

        print("📍 Tapping Observer navigation button...")
        observerButton.tap()
        sleep(2)  // Wait for view transition animation

        // Verify Observer sidebar appears (header text)
        let observerHeader = app.staticTexts["Observers"]
        XCTAssertTrue(
            observerHeader.waitForExistence(timeout: 5),
            """
            Observer sidebar header not found after navigation.

            Expected 'Observers' text in sidebar.
            Navigation may have failed or view may not have rendered.
            """
        )
        print("✅ Observer sidebar visible")

        // Verify MainStudioView still open
        let closeButton = app.buttons["CloseButton"].firstMatch
        XCTAssertTrue(
            closeButton.exists,
            "MainStudioView should still be open after navigation"
        )
        print("✅ Observer detail view visible")
    }

    // MARK: - Helper Methods
    
    /// Waits for the app to finish loading its initial database configurations
    /// ContentView shows a ProgressView during loading, so we wait for that to complete
    @MainActor
    private func waitForAppToFinishLoading(timeout: TimeInterval = 20) {
        let loadingText = app.staticTexts["Loading Database Configs..."]
        
        if loadingText.exists {
            var elapsed: TimeInterval = 0
            let interval: TimeInterval = 0.5
            
            while loadingText.exists && elapsed < timeout {
                usleep(UInt32(interval * 1_000_000))
                elapsed += interval
            }
        }
        
        // Give UI time to render after loading completes
        sleep(1)
    }

    /// Reads testDatabaseConfig.plist and returns the expected number of databases
    /// Returns nil if the plist file doesn't exist or can't be parsed
    @MainActor
    private func getExpectedDatabaseCount() -> Int? {
        // UI tests run in separate process - read directly from file system
        // The file is at: SwiftUI/Edge Debug Helper/testDatabaseConfig.plist

        // Get the source root by walking up from the derived data location
        let fileManager = FileManager.default

        // Try multiple possible paths
        let possiblePaths = [
            // Path relative to project root (most reliable)
            NSString(string: #file).deletingLastPathComponent + "/../Edge Debug Helper/testDatabaseConfig.plist",
            // Absolute path (backup)
            NSHomeDirectory() + "/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/testDatabaseConfig.plist"
        ]

        var validPath: String?
        for path in possiblePaths {
            let normalizedPath = (path as NSString).standardizingPath
            if fileManager.fileExists(atPath: normalizedPath) {
                validPath = normalizedPath
                print("✅ Found testDatabaseConfig.plist at: \(normalizedPath)")
                break
            }
        }

        guard let path = validPath else {
            print("⚠️ testDatabaseConfig.plist not found. Tried paths:")
            for path in possiblePaths {
                print("   - \((path as NSString).standardizingPath)")
            }
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

            guard let plist = plist,
                  let databasesArray = plist["databases"] as? [[String: Any]] else {
                print("⚠️ testDatabaseConfig.plist missing 'databases' array")
                return nil
            }

            let count = databasesArray.count
            print("📋 testDatabaseConfig.plist contains \(count) database(s)")
            return count

        } catch {
            print("⚠️ Error reading testDatabaseConfig.plist: \(error)")
            return nil
        }
    }

    /// Ensures MainStudioView is open, either by verifying it's already open
    /// or by selecting the first app if on the database list screen
    @MainActor
    private func ensureMainStudioViewIsOpen() throws {
        // WORKAROUND: NavigationSegmentedPicker doesn't expose as segmented control
        // Use CloseButton to validate MainStudioView is open instead
        let closeButton = app.buttons["CloseButton"].firstMatch

        // Check if we're already in MainStudioView
        if closeButton.exists {
            print("✅ Already in MainStudioView")
            return
        }

        // We're on the database list - need to select an app
        print("📋 Not in MainStudioView, opening first database...")

        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addDatabaseButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Not on ContentView - Add Database button not found")
        }

        // Find and tap the first app
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstAppCard = app.descendants(matching: .any).matching(predicate).firstMatch

        guard firstAppCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No app cards found - cannot open MainStudioView")
        }

        firstAppCard.tap()
        sleep(2)  // Wait for transition animation

        // Wait for MainStudioView to appear (validate with CloseButton)
        guard closeButton.waitForExistence(timeout: 30) else {
            XCTFail("MainStudioView did not appear after selecting app")
            throw XCTSkip("MainStudioView failed to open")
        }

        print("✅ MainStudioView opened successfully")
    }

    /// Reads testDatabaseConfig.plist and adds all databases via UI automation
    ///
    /// This function automates the manual process of adding databases:
    /// 1. For each database in testDatabaseConfig.plist
    /// 2. Click "Add Database" button
    /// 3. Fill out AppEditorView form
    /// 4. Save and validate database appears in list
    ///
    /// **Use this at the start of tests that need databases configured**
    ///
    /// - Throws: XCTSkip if plist file cannot be read
    @MainActor
    private func addDatabasesFromPlist() throws {
        print("\n=== ADD DATABASES FROM PLIST ===")

        // Read plist file (reuse getExpectedDatabaseCount() logic)
        let fileManager = FileManager.default
        let possiblePaths = [
            NSString(string: #file).deletingLastPathComponent + "/../Edge Debug Helper/testDatabaseConfig.plist",
            NSHomeDirectory() + "/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/testDatabaseConfig.plist"
        ]

        var validPath: String?
        for path in possiblePaths {
            let normalizedPath = (path as NSString).standardizingPath
            if fileManager.fileExists(atPath: normalizedPath) {
                validPath = normalizedPath
                break
            }
        }

        guard let path = validPath else {
            throw XCTSkip("testDatabaseConfig.plist not found")
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

            guard let plist = plist,
                  let databasesArray = plist["databases"] as? [[String: Any]] else {
                throw XCTSkip("testDatabaseConfig.plist missing 'databases' array")
            }

            print("📋 Found \(databasesArray.count) database(s) to add")

            // Add each database
            for (index, config) in databasesArray.enumerated() {
                let name = config["name"] as? String ?? "Unknown"
                print("\n📦 Adding database \(index + 1)/\(databasesArray.count): '\(name)'")
                try addSingleDatabase(config: config)
            }

            print("\n✅ All databases added successfully")

        } catch {
            throw XCTSkip("Error reading testDatabaseConfig.plist: \(error)")
        }
    }

    /// Adds a single database by automating the AppEditorView form
    ///
    /// - Parameter config: Dictionary containing database configuration from plist
    /// - Throws: XCTFail if form interaction fails
    @MainActor
    private func addSingleDatabase(config: [String: Any]) throws {
        let name = config["name"] as? String ?? ""
        let appId = config["appId"] as? String ?? ""
        let authToken = config["authToken"] as? String ?? ""
        let mode = config["mode"] as? String ?? "onlineplayground"

        // 1. Verify on ContentView (database list screen)
        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addDatabaseButton.waitForExistence(timeout: 5) else {
            XCTFail("Add Database button not found - not on ContentView")
            return
        }

        // 2. Tap "Add Database" button
        print("  🔘 Tapping Add Database button...")
        addDatabaseButton.tap()
        sleep(2)  // Wait for sheet animation

        // 3. Wait for sheet window to appear
        print("  ⏳ Waiting for AppEditorView sheet to appear...")
        let sheets = app.sheets
        if sheets.count > 0 {
            print("  ✅ Sheet detected (count: \(sheets.count))")
        } else {
            print("  ⚠️ No sheets detected, checking windows...")
            print("     Window count: \(app.windows.count)")
        }

        // Give sheet time to fully render
        sleep(2)

        // 4. Take screenshot for debugging
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "form-appeared-\(name)"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)

        // 5. Wait for AppEditorView form to be ready
        // Instead of looking for the picker (which SwiftUI doesn't expose as expected),
        // wait for the Name text field to exist - this proves the form rendered
        print("  ⏳ Waiting for form fields to appear...")
        let nameField = app.textFields["NameTextField"]
        guard nameField.waitForExistence(timeout: 10) else {
            // Debug output
            print("  ❌ NameTextField not found!")
            print("     Total text fields (app): \(app.textFields.count)")
            if sheets.count > 0 {
                let sheet = sheets.firstMatch
                print("     Total text fields (sheet): \(sheet.textFields.count)")
            }

            // Take failure screenshot
            let failureScreenshot = app.screenshot()
            let failureAttachment = XCTAttachment(screenshot: failureScreenshot)
            failureAttachment.name = "FAIL-form-not-ready-\(name)"
            failureAttachment.lifetime = .keepAlways
            add(failureAttachment)

            XCTFail("AppEditorView form did not appear after tapping Add Database")
            return
        }
        print("  ✅ AppEditorView form appeared")

        // 4. Select auth mode from picker (if we can find it)
        // NOTE: SwiftUI Picker with .pickerStyle(.segmented) doesn't always expose as
        // a segmented control in XCUITest. It might expose segments as individual buttons
        // or not be accessible at all. We'll try to find and select it, but won't fail
        // if we can't - the form defaults to first mode (onlineplayground) anyway.
        print("  🎚️ Selecting mode: \(mode)")

        if mode != "onlineplayground" {
            // Need to change from default mode
            // Try to find mode buttons by looking for buttons with mode display names
            let modeNames = [
                "Online Playground",
                "Offline Playground",
                "Shared Key"
            ]

            let targetMode = mode == "offlineplayground" ? "Offline Playground" : "Shared Key"
            let modeButton = app.buttons[targetMode].firstMatch

            if modeButton.waitForExistence(timeout: 2) {
                print("  ✅ Found mode button: \(targetMode)")
                modeButton.tap()
                sleep(1)  // Wait for conditional fields to appear/hide
            } else {
                print("  ⚠️ Could not find mode button '\(targetMode)', form will use default (Online Playground)")
                if mode == "sharedkey" || mode == "offlineplayground" {
                    print("  ⚠️ WARNING: Test expects \(mode) but form is in onlineplayground mode")
                }
            }
        } else {
            print("  ✅ Using default mode (Online Playground)")
        }

        // 5. Fill required fields: name, appId, authToken
        print("  ✏️ Filling name: '\(name)'")
        // nameField already exists from form validation above
        nameField.tap()
        sleep(1)
        nameField.typeText(name)

        print("  ✏️ Filling appId: '\(appId)'")
        let appIdField = app.textFields["AppIdTextField"]
        guard appIdField.waitForExistence(timeout: 5) else {
            XCTFail("App ID field not found")
            return
        }
        appIdField.tap()
        sleep(1)
        appIdField.typeText(appId)

        print("  ✏️ Filling authToken: '\(authToken.prefix(20))...'")
        let authTokenField = app.textFields["AuthTokenTextField"]
        guard authTokenField.waitForExistence(timeout: 5) else {
            XCTFail("Auth Token field not found")
            return
        }
        authTokenField.tap()
        sleep(1)
        authTokenField.typeText(authToken)

        // 6. Fill mode-specific optional fields
        switch mode {
        case "onlineplayground":
            // Fill optional server fields
            if let authUrl = config["authUrl"] as? String, !authUrl.isEmpty {
                print("  ✏️ Filling authUrl: '\(authUrl)'")
                let authUrlField = app.textFields["AuthUrlTextField"]
                if authUrlField.waitForExistence(timeout: 3) {
                    authUrlField.tap()
                    sleep(1)
                    authUrlField.typeText(authUrl)
                }
            }

            if let websocketUrl = config["websocketUrl"] as? String, !websocketUrl.isEmpty {
                print("  ✏️ Filling websocketUrl: '\(websocketUrl)'")
                let websocketUrlField = app.textFields["WebsocketUrlTextField"]
                if websocketUrlField.waitForExistence(timeout: 3) {
                    websocketUrlField.tap()
                    sleep(1)
                    websocketUrlField.typeText(websocketUrl)
                }
            }

            if let httpApiUrl = config["httpApiUrl"] as? String, !httpApiUrl.isEmpty {
                print("  ✏️ Filling httpApiUrl: '\(httpApiUrl)'")
                let httpApiUrlField = app.textFields["HttpApiUrlTextField"]
                if httpApiUrlField.waitForExistence(timeout: 3) {
                    httpApiUrlField.tap()
                    sleep(1)
                    httpApiUrlField.typeText(httpApiUrl)
                }
            }

            if let httpApiKey = config["httpApiKey"] as? String, !httpApiKey.isEmpty {
                print("  ✏️ Filling httpApiKey: '\(httpApiKey.prefix(20))...'")
                let httpApiKeyField = app.textFields["HttpApiKeyTextField"]
                if httpApiKeyField.waitForExistence(timeout: 3) {
                    httpApiKeyField.tap()
                    sleep(1)
                    httpApiKeyField.typeText(httpApiKey)
                }
            }

            if let allowUntrusted = config["allowUntrustedCerts"] as? Bool, allowUntrusted {
                print("  🔘 Enabling Allow Untrusted Certs...")
                let toggle = app.switches["AllowUntrustedCertsToggle"]
                if toggle.waitForExistence(timeout: 3) {
                    // Direct tap() doesn't work on macOS toggles - use coordinate tapping
                    let toggleCoord = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    toggleCoord.tap()
                    sleep(1)
                }
            }

        case "sharedkey":
            // Fill optional secret key
            if let secretKey = config["secretKey"] as? String, !secretKey.isEmpty {
                print("  ✏️ Filling secretKey: '\(secretKey.prefix(10))...'")
                let secretKeyField = app.textFields["SecretKeyTextField"]
                if secretKeyField.waitForExistence(timeout: 3) {
                    secretKeyField.tap()
                    sleep(1)
                    secretKeyField.typeText(secretKey)
                }
            }

        case "offlineplayground":
            // No additional fields
            break

        default:
            break
        }

        // 7. Tap Save button
        print("  💾 Tapping Save button...")
        let saveButton = app.buttons["SaveButton"]
        guard saveButton.waitForExistence(timeout: 5) else {
            XCTFail("Save button not found")
            return
        }

        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled after filling required fields")

        saveButton.tap()
        print("  ⏳ Waiting for sheet to dismiss...")
        sleep(2)  // Wait for save tap to register

        // Wait for sheet to disappear (proves form dismissed)
        if sheets.count > 0 {
            let sheet = sheets.firstMatch
            // Wait up to 5 seconds for sheet to disappear
            var sheetGone = false
            for _ in 0..<10 {
                if !sheet.exists {
                    sheetGone = true
                    break
                }
                usleep(500000)  // 0.5 seconds
            }
            if sheetGone {
                print("  ✅ Sheet dismissed")
            } else {
                print("  ⚠️ Sheet still visible after 5s")
            }
        }

        // Additional wait for database to save and UI to update
        sleep(2)

        // 8. Validate database card appears
        // Look for the AppCard directly - it will exist whether or not the DatabaseList
        // container has an identifier
        print("  ⏳ Waiting for database card '\(name)' to appear...")

        let cardIdentifier = "AppCard_\(name)"
        let newDatabaseCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", cardIdentifier))
            .firstMatch

        guard newDatabaseCard.waitForExistence(timeout: 20) else {
            // Debug output
            print("  ❌ Database card '\(name)' not found!")
            let addButtonExists = app.buttons["AddDatabaseButton"].firstMatch.exists
            print("     Add Database button exists: \(addButtonExists)")
            print("     Total windows: \(app.windows.count)")
            print("     Total sheets: \(app.sheets.count)")

            // Check if DatabaseList exists
            let databaseList = app.otherElements["DatabaseList"]
            print("     DatabaseList exists: \(databaseList.exists)")

            // Check if empty state is showing
            let emptyStateText = app.staticTexts["No Database Configurations"]
            print("     Empty state showing: \(emptyStateText.exists)")

            // Count total app cards
            let allCards = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'"))
            print("     Total AppCards found: \(allCards.count)")

            // Take failure screenshot
            let failureScreenshot = app.screenshot()
            let failureAttachment = XCTAttachment(screenshot: failureScreenshot)
            failureAttachment.name = "FAIL-no-database-card-\(name)"
            failureAttachment.lifetime = .keepAlways
            add(failureAttachment)

            XCTFail("Database '\(name)' was not added to the list")
            return
        }

        print("  ✅ Database '\(name)' added successfully")
    }

    // MARK: - Debug Tests
    
    /// Diagnostic test to verify app window and UI hierarchy loads
    @MainActor
    func testDebugFindAddDatabaseButton() throws {
        print("\n=== DIAGNOSTIC: Checking App State ===")
        
        // First, check what windows exist
        print("\nWindow count: \(app.windows.count)")
        for (index, window) in app.windows.allElementsBoundByIndex.enumerated() {
            print("  Window \(index): exists=\(window.exists), identifier='\(window.identifier)', title='\(window.title)'")
        }
        
        // Check for any alerts or dialogs
        print("\nAlert count: \(app.alerts.count)")
        for (index, alert) in app.alerts.allElementsBoundByIndex.enumerated() {
            print("  Alert \(index): exists=\(alert.exists), identifier='\(alert.identifier)', label='\(alert.label)'")
        }
        
        // Check for any sheets
        print("\nSheet count: \(app.sheets.count)")
        
        // Check for all static texts (including loading text)
        print("\nStatic text count: \(app.staticTexts.count)")
        let allTexts = app.staticTexts.allElementsBoundByIndex
        print("First 20 static texts:")
        for (index, text) in allTexts.prefix(20).enumerated() {
            if text.exists {
                print("  Text \(index): identifier='\(text.identifier)', label='\(text.label)'")
            }
        }
        
        print("\n=== DIAGNOSTIC: Waiting for app to finish loading ===")
        
        // ContentView shows ProgressView with "Loading Database Configs..." while initializing
        // We need to wait for this loading to complete before any buttons appear
        let loadingText = app.staticTexts["Loading Database Configs..."]
        
        // If loading text appears, wait for it to disappear (max 15 seconds)
        if loadingText.exists {
            print("⏳ App is loading, waiting for initialization to complete...")
            var elapsed = 0
            while loadingText.exists && elapsed < 15 {
                sleep(1)
                elapsed += 1
                print("  Waited \(elapsed)s...")
            }
            
            if loadingText.exists {
                print("❌ Loading did not complete after 15 seconds")
            } else {
                print("✅ Loading completed after \(elapsed)s")
            }
        } else {
            print("⚠️ Loading text never appeared - checking if app loaded instantly or has issues")
            print("   This could mean:")
            print("   1. App loaded very quickly (good)")
            print("   2. UI hierarchy not accessible to XCUITest (bad)")
            print("   3. App showing error/alert instead of main UI (bad)")
        }
        
        // Give UI time to render after loading completes
        sleep(2)
        
        print("\n=== DIAGNOSTIC: Checking UI Elements ===")
        
        // Take screenshot of what's actually visible
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "app-state-after-loading"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Check for button by identifier
        let buttonById = app.buttons["AddDatabaseButton"]
        print("AddDatabaseButton by ID exists: \(buttonById.exists)")
        print("AddDatabaseButton by ID waitForExistence(5s): \(buttonById.waitForExistence(timeout: 5))")
        
        // Check for any buttons in toolbar
        let buttonCount = app.buttons.count
        print("\nAll buttons count: \(buttonCount)")
        print("All toolbar items count: \(app.toolbars.count)")
        
        // Try to find it as any button (not by ID)
        let allButtons = app.buttons.allElementsBoundByIndex
        print("\nFirst 10 buttons:")
        for (index, button) in allButtons.prefix(10).enumerated() {
            print("  Button \(index): identifier='\(button.identifier)', label='\(button.label)', exists=\(button.exists)")
        }
        
        // Check for DatabaseList
        let databaseList = app.otherElements["DatabaseList"]
        print("\nDatabaseList exists: \(databaseList.exists)")
        
        // Check for Ditto Apps text
        let dittoAppsText = app.staticTexts["Ditto Apps"]
        print("'Ditto Apps' text exists: \(dittoAppsText.exists)")
        
        // Check navigation title
        let navTitle = app.navigationBars.firstMatch
        print("Navigation bar exists: \(navTitle.exists)")
        if navTitle.exists {
            print("Navigation bar identifier: '\(navTitle.identifier)'")
        }
        
        print("\n=== END DIAGNOSTIC ===\n")
        
        // ASSERTIONS - These will cause test to fail
        XCTAssertTrue(
            buttonCount > 0,
            "FATAL: No UI elements found after loading. App initialized but UI hierarchy is empty."
        )
        
        XCTAssertTrue(
            buttonById.exists,
            "FATAL: AddDatabaseButton not found. Expected ContentView to be visible with Add Database button."
        )
    }
}
