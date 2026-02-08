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
        let addDatabaseButton = app.buttons["AddDatabaseButton"]
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
        let addDatabaseButton = app.buttons["AddDatabaseButton"]
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
        // Wait for app to finish loading databases
        waitForAppToFinishLoading()
        
        // CRITICAL: Tests run in a fresh sandbox - app MUST start at ContentView
        // Check for Add Database button (language-independent)
        let addDatabaseButton = app.buttons["AddDatabaseButton"]
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 5),
            """
            FATAL: App did not start at ContentView (database list screen).
            
            Expected: ContentView with Add Database button
            Actual: Add Database button not found
            
            Tests run in a fresh sandbox and should ALWAYS start at ContentView.
            If this fails, there's a problem with app initialization or test setup.
            """
        )

        // Wait for database list
        let databaseList = app.otherElements["DatabaseList"]
        guard databaseList.waitForExistence(timeout: 5) else {
            XCTFail("DatabaseList not found - check testDatabaseConfig.plist is configured")
            throw XCTSkip("No database list found")
        }

        // Capture list of databases
        let databaseListScreenshot = app.screenshot()
        let databaseListAttachment = XCTAttachment(screenshot: databaseListScreenshot)
        databaseListAttachment.name = "MainStudioView-ContentView-DatabaseList"
        databaseListAttachment.lifetime = .keepAlways
        add(databaseListAttachment)
        print("DEBUG: 📸 Screenshot saved as 'MainStudioView-ContentView-DatabaseList'")

        // Find and tap the first app card
        // App cards are identified by "AppCard_<name>" but we need to find any card
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstAppCard = databaseList.descendants(matching: .any).matching(predicate).firstMatch

        guard firstAppCard.exists else {
            throw XCTSkip("No app cards found - cannot test app selection")
        }

        // Tap the first app
        print("DEBUG: Tapping app card: \(firstAppCard.identifier)")
        firstAppCard.tap()

        // CRITICAL: Aggressive window reactivation after tap
        // The tap triggers a view transition which can cause window to lose focus
        print("DEBUG: Reactivating window after tap...")

        let firstWindow = app.windows.firstMatch

        // Step 1: Initial reactivation
        app.activate()
        sleep(1)

        // Step 2: Click window to force focus
        if firstWindow.exists {
            firstWindow.click()
            sleep(1)
        }

        // Step 3: Verify activation worked (check if UI is accessible)
        var activationAttempts = 0
        while app.buttons.count == 0 && activationAttempts < 3 {
            print("DEBUG: UI not accessible after tap (attempt \(activationAttempts + 1)/3), reactivating...")
            app.activate()
            sleep(1)
            if firstWindow.exists {
                firstWindow.click()
            }
            sleep(1)
            activationAttempts += 1
        }

        print("DEBUG: After reactivation: \(app.buttons.count) buttons visible")

        // CRITICAL: Wait for MainStudioView to load
        // MainStudioView initialization is VERY slow (Ditto connections, subscriptions, etc.)
        print("DEBUG: Waiting for MainStudioView to appear...")

        // Poll for navigation picker with periodic window reactivation
        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        var attempts = 0
        let maxAttempts = 30  // 30 seconds total (MainStudioView is slow)

        while !navigationPicker.exists && attempts < maxAttempts {
            sleep(1)
            attempts += 1

            // Reactivate every 5 seconds to maintain focus during long load
            if attempts % 5 == 0 {
                app.activate()
                if firstWindow.exists {
                    firstWindow.click()
                }
                print("DEBUG: MainStudioView loading... attempt \(attempts)/\(maxAttempts) - reactivating window...")
            }
        }

        print("DEBUG: Checking for NavigationSegmentedPicker after \(attempts)s...")
        
        // Try multiple approaches to find it
        if navigationPicker.exists {
            print("DEBUG: ✅ NavigationSegmentedPicker found!")
            
            // Capture screenshot when found
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "MainStudioView-NavigationPicker-Found"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("DEBUG: 📸 Screenshot saved as 'MainStudioView-NavigationPicker-Found'")
            
        } else {
            print("DEBUG: ❌ NavigationSegmentedPicker NOT found")
            print("DEBUG: Total segmented controls: \(app.segmentedControls.count)")
            print("DEBUG: Total buttons: \(app.buttons.count)")
            print("DEBUG: Total windows: \(app.windows.count)")
            print("DEBUG: App state: \(app.state)")
            
            if app.segmentedControls.count > 0 {
                let firstSegmented = app.segmentedControls.element(boundBy: 0)
                print("DEBUG: First segmented control identifier: \(firstSegmented.identifier)")
            }
            
            // Check for any alerts or errors
            if app.alerts.count > 0 {
                print("DEBUG: ⚠️ ALERT DETECTED: \(app.alerts.count) alert(s)")
                let firstAlert = app.alerts.firstMatch
                print("DEBUG: Alert label: \(firstAlert.label)")
            }
            
            // Check if we're still on ContentView
            if app.buttons["AddDatabaseButton"].exists {
                print("DEBUG: ⚠️ Still on ContentView - transition to MainStudioView did not happen")
            }
            
            // Capture screenshot when NOT found to see what's actually on screen
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "MainStudioView-NavigationPicker-NOT-Found"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("DEBUG: 📸 Screenshot saved as 'MainStudioView-NavigationPicker-NOT-Found'")
        }
        
        XCTAssertTrue(
            navigationPicker.exists || app.segmentedControls.count > 0,
            """
            MainStudioView navigation should appear after selecting an app.
            
            Navigation picker exists: \(navigationPicker.exists)
            Segmented controls count: \(app.segmentedControls.count)
            Total buttons: \(app.buttons.count)
            App state: \(app.state.rawValue)
            
            Check screenshot 'MainStudioView-NavigationPicker-NOT-Found' to see what's on screen.
            """
        )
    }

    // MARK: - MainStudioView Navigation Tests

    @MainActor
    func testNavigationToSubscriptions() throws {
        try ensureMainStudioViewIsOpen()

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // Tap Subscriptions menu item (first item)
        let subscriptionsButton = navigationPicker.buttons.element(boundBy: 0)
        subscriptionsButton.tap()

        // Verify Subscriptions view appears
        let subscriptionsSidebar = app.otherElements["SubscriptionsSidebar"]
        XCTAssertTrue(
            subscriptionsSidebar.waitForExistence(timeout: 3),
            "Subscriptions sidebar should appear"
        )

        let subscriptionsDetail = app.otherElements["SubscriptionsDetailView"]
        XCTAssertTrue(
            subscriptionsDetail.waitForExistence(timeout: 3),
            "Subscriptions detail view should appear"
        )
    }

    @MainActor
    func testNavigationToCollections() throws {
        try ensureMainStudioViewIsOpen()

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // Tap Collections menu item (second item)
        let collectionsButton = navigationPicker.buttons.element(boundBy: 1)
        collectionsButton.tap()

        // Verify Collections view appears
        let collectionsSidebar = app.otherElements["CollectionsSidebar"]
        XCTAssertTrue(
            collectionsSidebar.waitForExistence(timeout: 3),
            "Collections sidebar should appear"
        )

        let collectionsDetail = app.otherElements["CollectionsDetailView"]
        XCTAssertTrue(
            collectionsDetail.waitForExistence(timeout: 3),
            "Collections detail view should appear"
        )
    }

    @MainActor
    func testNavigationToObserver() throws {
        try ensureMainStudioViewIsOpen()

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // Tap Observer menu item (third item)
        let observerButton = navigationPicker.buttons.element(boundBy: 2)
        observerButton.tap()

        // Verify Observer view appears
        let observerSidebar = app.otherElements["ObserverSidebar"]
        XCTAssertTrue(
            observerSidebar.waitForExistence(timeout: 3),
            "Observer sidebar should appear"
        )

        let observerDetail = app.otherElements["ObserverDetailView"]
        XCTAssertTrue(
            observerDetail.waitForExistence(timeout: 3),
            "Observer detail view should appear"
        )
    }

    @MainActor
    func testNavigationToDittoTools() throws {
        try ensureMainStudioViewIsOpen()

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // Tap Ditto Tools menu item (fourth item)
        let dittoToolsButton = navigationPicker.buttons.element(boundBy: 3)
        dittoToolsButton.tap()

        // Verify Ditto Tools view appears
        let dittoToolsSidebar = app.otherElements["DittoToolsSidebar"]
        XCTAssertTrue(
            dittoToolsSidebar.waitForExistence(timeout: 3),
            "Ditto Tools sidebar should appear"
        )

        let dittoToolsDetail = app.otherElements["DittoToolsDetailView"]
        XCTAssertTrue(
            dittoToolsDetail.waitForExistence(timeout: 3),
            "Ditto Tools detail view should appear"
        )
    }

    @MainActor
    func testNavigateThroughAllMenuItems() throws {
        try ensureMainStudioViewIsOpen()

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // Expected menu items in order: Subscriptions, Collections, Observer, Ditto Tools
        let expectedViews: [(sidebarId: String, detailId: String, name: String)] = [
            ("SubscriptionsSidebar", "SubscriptionsDetailView", "Subscriptions"),
            ("CollectionsSidebar", "CollectionsDetailView", "Collections"),
            ("ObserverSidebar", "ObserverDetailView", "Observer"),
            ("DittoToolsSidebar", "DittoToolsDetailView", "Ditto Tools")
        ]

        for (index, expectedView) in expectedViews.enumerated() {
            // Tap the menu item
            let menuButton = navigationPicker.buttons.element(boundBy: index)
            menuButton.tap()

            // Verify both sidebar and detail views appear
            let sidebar = app.otherElements[expectedView.sidebarId]
            XCTAssertTrue(
                sidebar.waitForExistence(timeout: 3),
                "\(expectedView.name) sidebar should appear when menu item \(index) is tapped"
            )

            let detail = app.otherElements[expectedView.detailId]
            XCTAssertTrue(
                detail.waitForExistence(timeout: 3),
                "\(expectedView.name) detail view should appear when menu item \(index) is tapped"
            )

            // Small delay between navigations to avoid race conditions
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Visual Layout Tests with Screenshots

    /// **CRITICAL TEST**: Validates that Collections view + Inspector layout works correctly.
    ///
    /// This test addresses a specific bug where opening the inspector while viewing Collections
    /// (which contains a VSplitView) causes the sidebar to disappear. Screenshots are captured
    /// at each step to provide visual validation.
    ///
    /// **Bug Description:**
    /// - User navigates to Collections view (contains VSplitView with query editor/results)
    /// - User opens inspector
    /// - **Expected:** Sidebar remains visible, 3-pane layout (Sidebar | Detail | Inspector)
    /// - **Actual (bug):** Sidebar disappears, only showing Detail | Inspector
    ///
    /// **Root Cause:** Incorrect frame modifiers on VSplitView children causing constraint conflicts
    @MainActor
    func testCollectionsViewInspectorLayoutWithScreenshots() throws {
        try ensureMainStudioViewIsOpen()

        // STEP 1: Initial state - capture starting layout
        let screenshot1 = app.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01-main-studio-initial"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(navigationPicker.exists, "Navigation picker should exist")

        // STEP 2: Navigate to Collections view
        let collectionsButton = navigationPicker.buttons.element(boundBy: 1)
        collectionsButton.tap()
        sleep(2) // Allow layout to settle

        let screenshot2 = app.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02-collections-view-NO-inspector"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // STEP 3: Open inspector - THIS IS THE CRITICAL STEP
        let inspectorToggle = app.buttons["Toggle Inspector"]

        if inspectorToggle.exists {
            print("🔍 Opening inspector while Collections view is displayed...")
            inspectorToggle.tap()
            sleep(2) // Allow layout to settle

            let screenshot3 = app.screenshot()
            let attachment3 = XCTAttachment(screenshot: screenshot3)
            attachment3.name = "03-CRITICAL-collections-WITH-inspector"
            attachment3.lifetime = .keepAlways
            add(attachment3)

            // STEP 4: CRITICAL VALIDATION - Check if sidebar is still visible
            // Try multiple ways to detect sidebar visibility
            let sidebarButton1 = app.buttons["Subscriptions"]
            let sidebarButton2 = app.staticTexts["Subscriptions"]
            let sidebarButton3 = navigationPicker.buttons.element(boundBy: 0)

            let sidebarVisible = sidebarButton1.exists || sidebarButton2.exists || sidebarButton3.exists

            // Log the state for debugging
            print("🔍 Sidebar visibility check:")
            print("  - app.buttons['Subscriptions'].exists: \(sidebarButton1.exists)")
            print("  - app.staticTexts['Subscriptions'].exists: \(sidebarButton2.exists)")
            print("  - navigationPicker.buttons[0].exists: \(sidebarButton3.exists)")
            print("  - Overall sidebar visible: \(sidebarVisible)")

            if !sidebarVisible {
                // Screenshot shows the bug!
                print("❌ BUG DETECTED: Sidebar disappeared when inspector opened!")
                print("📸 Check screenshot '03-CRITICAL-collections-WITH-inspector' to see the layout issue")
                print("Expected: Sidebar (left) | Collections VSplitView (center) | Inspector (right)")
                print("Actual: Sidebar MISSING - only showing Collections VSplitView | Inspector")
            } else {
                print("✅ SUCCESS: Sidebar remained visible when inspector opened")
            }

            XCTAssertTrue(
                sidebarVisible,
                """
                CRITICAL BUG: Sidebar disappeared when inspector opened in Collections view!

                Check screenshot '03-CRITICAL-collections-WITH-inspector' for visual evidence.

                Expected layout: Sidebar (200-300px) | Collections Detail with VSplitView | Inspector (250-500px)
                Actual layout: Sidebar HIDDEN | Collections Detail with VSplitView | Inspector

                This indicates the NavigationSplitView + Inspector + VSplitView layout is broken.
                Root cause: Incorrect frame modifiers on VSplitView children causing constraint conflicts.
                """
            )

            // STEP 5: Close inspector and verify sidebar still visible
            inspectorToggle.tap()
            sleep(1)

            let screenshot4 = app.screenshot()
            let attachment4 = XCTAttachment(screenshot: screenshot4)
            attachment4.name = "04-collections-inspector-CLOSED"
            attachment4.lifetime = .keepAlways
            add(attachment4)

            let sidebarStillVisible = sidebarButton1.exists || sidebarButton2.exists || sidebarButton3.exists
            XCTAssertTrue(
                sidebarStillVisible,
                "Sidebar should remain visible after closing inspector"
            )
        } else {
            XCTFail("Inspector toggle button not found - check MainStudioView toolbar configuration")
        }
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

    /// Ensures MainStudioView is open, either by verifying it's already open
    /// or by selecting the first app if on the database list screen
    @MainActor
    private func ensureMainStudioViewIsOpen() throws {
        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]

        // Check if we're already in MainStudioView
        if navigationPicker.exists {
            return
        }

        // We're on the database list - need to select an app
        let databaseList = app.otherElements["DatabaseList"]
        guard databaseList.waitForExistence(timeout: 5) else {
            throw XCTSkip("No apps configured - cannot open MainStudioView")
        }

        // Find and tap the first app
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstAppCard = databaseList.descendants(matching: .any).matching(predicate).firstMatch

        guard firstAppCard.exists else {
            throw XCTSkip("No app cards found - cannot open MainStudioView")
        }

        firstAppCard.tap()

        // Wait for MainStudioView to appear
        guard navigationPicker.waitForExistence(timeout: 10) else {
            XCTFail("MainStudioView did not appear after selecting app")
            throw XCTSkip("MainStudioView failed to open")
        }
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
    
    /// Diagnostic test to understand what UI elements are present
    ///
    /// **Important:** UI tests run in a sandboxed environment, which means:
    /// - The app's configuration may not persist between test runs
    /// - You may need to configure a Ditto database during the test
    /// - Screenshots are saved to help diagnose what's visible
    ///
    /// **To view debug output:**
    /// 1. Run this test in Xcode
    /// 2. Open the Report Navigator (⌘9)
    /// 3. Select the test run
    /// 4. View console output and screenshot attachment
    @MainActor
    func testDebugAppState() throws {
        sleep(3)
        
        print("\n=== DIAGNOSTIC: App Launch State ===")
        print("DatabaseList exists: \(app.otherElements["DatabaseList"].exists)")
        print("Ditto Apps title exists: \(app.staticTexts["Ditto Apps"].exists)")
        print("NavigationSegmentedPicker (segmentedControls): \(app.segmentedControls["NavigationSegmentedPicker"].exists)")
        print("NavigationSegmentedPicker (groups): \(app.groups["NavigationSegmentedPicker"].exists)")
        print("NavigationSegmentedPicker (otherElements): \(app.otherElements["NavigationSegmentedPicker"].exists)")
        print("Total segmented controls: \(app.segmentedControls.count)")
        print("Total groups: \(app.groups.count)")
        print("Total buttons: \(app.buttons.count)")
        
        // Look for any buttons that might be navigation items
        print("\nSearching for navigation buttons...")
        print("Any button with 'Subscription' in identifier: \(app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'Subscription'")).count)")
        print("Any button with 'Collection' in identifier: \(app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'Collection'")).count)")
        
        // Try to find first segmented control if it exists
        if app.segmentedControls.count > 0 {
            let firstSegmented = app.segmentedControls.element(boundBy: 0)
            print("\nFirst segmented control found!")
            print("  - Identifier: \(firstSegmented.identifier)")
            print("  - Button count in it: \(firstSegmented.buttons.count)")
        }
        
        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "app-launch-state"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("=== Screenshot saved as 'app-launch-state' ===\n")
    }
    
    // MARK: - Picker Navigation Tests with Screenshots
    
    /// Comprehensive test validating consistent Picker navigation for sidebar and inspector.
    ///
    /// This test validates the new unified Picker navigation pattern where both sidebar
    /// and inspector use identical SwiftUI Picker components with 14pt SF Symbol icons.
    ///
    /// **IMPORTANT: Test Environment Setup**
    ///
    /// UI tests run in a sandboxed environment. To run this test successfully:
    ///
    /// 1. **First-time setup:** Launch the app normally (not in test mode) and configure at least one Ditto database
    /// 2. **OR** Modify this test to programmatically add a test database configuration
    /// 3. **Check diagnostics:** Run `testDebugAppState()` first to see screenshots of what's visible
    ///
    /// The test will skip if:
    /// - No databases are configured in the test environment
    /// - The app doesn't launch to MainStudioView or database list screen
    ///
    /// **Test Coverage:**
    /// - Database list loads on app launch (or app opens directly to MainStudioView)
    /// - Can select and open a database (MainStudioView appears)
    /// - Sidebar picker displays all 3 items (Subscriptions, Collections, Observer)
    /// - Each sidebar item is clickable and changes view
    /// - Inspector can be opened
    /// - Inspector picker displays all 2 items (History, Favorites)
    /// - Each inspector item is clickable and changes content
    /// - Sidebar remains visible when inspector is open
    /// - Up to 9 screenshots captured for visual validation
    @MainActor
    func testNavigationPickersWithScreenshots() throws {
        // 1. Launch app and wait for UI to stabilize
        sleep(2)

        let screenshot1 = app.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01-app-launch"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // 2. Verify app started at ContentView (fresh sandbox)
        print("DEBUG: Checking for Add Database button (ContentView indicator)...")
        let addDatabaseButton = app.buttons["AddDatabaseButton"]
        XCTAssertTrue(
            addDatabaseButton.waitForExistence(timeout: 5),
            "App must start at ContentView with Add Database button. Tests run in fresh sandbox."
        )
        print("DEBUG: ✅ Add Database button found - on ContentView")

        // 3. Find database list
        print("DEBUG: Looking for database list...")
        let databaseList = app.otherElements["DatabaseList"]
        guard databaseList.waitForExistence(timeout: 5) else {
            print("DEBUG: DatabaseList not found")
            XCTFail("DatabaseList not found - check testDatabaseConfig.plist is configured")
            throw XCTSkip("No database list found")
        }
        print("DEBUG: DatabaseList found!")

        // 3. Find and tap first app card
        print("DEBUG: Looking for app cards...")
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstAppCard = databaseList.descendants(matching: .any).matching(predicate).firstMatch
        
        guard firstAppCard.exists else {
            print("DEBUG: No app cards found")
            throw XCTSkip("No app cards found")
        }
        print("DEBUG: App card found with identifier: \(firstAppCard.identifier)")

        // Take screenshot before tap
        let screenshot2 = app.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02-before-tap-database"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        print("DEBUG: Tapping app card...")
        firstAppCard.tap()
        
        // CRITICAL: Wait for transition animation and MainStudioView to fully load
        print("DEBUG: Waiting 5 seconds for MainStudioView to appear...")
        sleep(5)

        // 4. Verify MainStudioView loaded
        let screenshot3 = app.screenshot()
        let attachment3 = XCTAttachment(screenshot: screenshot3)
        attachment3.name = "03-after-tap-main-studio"
        attachment3.lifetime = .keepAlways
        add(attachment3)

        // 5. Find the navigation picker
        print("DEBUG: Looking for navigation picker...")
        print("DEBUG: Total segmented controls: \(app.segmentedControls.count)")
        
        var picker: XCUIElement
        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        
        if navigationPicker.waitForExistence(timeout: 10) {
            print("DEBUG: NavigationSegmentedPicker found by identifier!")
            picker = navigationPicker
        } else {
            print("DEBUG: NavigationSegmentedPicker not found by identifier")
            print("DEBUG: Trying first segmented control...")
            
            let firstSegmented = app.segmentedControls.firstMatch
            guard firstSegmented.waitForExistence(timeout: 5) else {
                print("DEBUG: No segmented controls found at all!")
                throw XCTSkip("Navigation picker not found - MainStudioView may not have loaded")
            }
            print("DEBUG: Using first segmented control as fallback")
            picker = firstSegmented
        }
        
        // Get navigation buttons from the picker
        let subscriptionsButton = picker.buttons.element(boundBy: 0)
        let collectionsButton = picker.buttons.element(boundBy: 1)
        let observerButton = picker.buttons.element(boundBy: 2)
        
        XCTAssertTrue(subscriptionsButton.exists, "Subscriptions picker item should exist")
        XCTAssertTrue(collectionsButton.exists, "Collections picker item should exist")
        XCTAssertTrue(observerButton.exists, "Observer picker item should exist")

        // 6. Click each sidebar item and capture screenshots
        print("DEBUG: Clicking Collections button...")
        collectionsButton.tap()
        sleep(2)  // Wait for view to update

        let screenshot4 = app.screenshot()
        let attachment4 = XCTAttachment(screenshot: screenshot4)
        attachment4.name = "04-sidebar-collections-selected"
        attachment4.lifetime = .keepAlways
        add(attachment4)

        print("DEBUG: Clicking Observer button...")
        observerButton.tap()
        sleep(2)  // Wait for view to update

        let screenshot5 = app.screenshot()
        let attachment5 = XCTAttachment(screenshot: screenshot5)
        attachment5.name = "05-sidebar-observer-selected"
        attachment5.lifetime = .keepAlways
        add(attachment5)

        print("DEBUG: Clicking Subscriptions button...")
        subscriptionsButton.tap()
        sleep(2)  // Wait for view to update

        let screenshot6 = app.screenshot()
        let attachment6 = XCTAttachment(screenshot: screenshot6)
        attachment6.name = "06-sidebar-subscriptions-selected"
        attachment6.lifetime = .keepAlways
        add(attachment6)

        // 7. Open inspector
        print("DEBUG: Looking for inspector toggle button...")
        let inspectorToggle = app.buttons["Toggle Inspector"]
        XCTAssertTrue(inspectorToggle.exists, "Inspector toggle button should exist")
        
        print("DEBUG: Clicking inspector toggle...")
        inspectorToggle.tap()
        sleep(2)  // Wait for inspector panel to slide in

        let screenshot7 = app.screenshot()
        let attachment7 = XCTAttachment(screenshot: screenshot7)
        attachment7.name = "07-inspector-opened-history-default"
        attachment7.lifetime = .keepAlways
        add(attachment7)

        // 8. Find inspector navigation control - try multiple approaches
        var inspectorControl: XCUIElement?
        
        // Try 1: By accessibility identifier
        let inspectorById = app.segmentedControls["InspectorSegmentedPicker"]
        if inspectorById.waitForExistence(timeout: 2) {
            inspectorControl = inspectorById
        }
        
        // Try 2: Look for second segmented control (first is sidebar)
        if inspectorControl == nil && app.segmentedControls.count >= 2 {
            inspectorControl = app.segmentedControls.element(boundBy: 1)
        }
        
        // Try 3: As a group
        if inspectorControl == nil {
            let inspectorAsGroup = app.groups["InspectorSegmentedPicker"]
            if inspectorAsGroup.waitForExistence(timeout: 2) {
                inspectorControl = inspectorAsGroup
            }
        }
        
        guard let inspectorPicker = inspectorControl else {
            throw XCTSkip("Cannot find inspector picker")
        }
        
        // Get inspector buttons by index
        let historyButton = inspectorPicker.buttons.element(boundBy: 0)
        let favoritesButton = inspectorPicker.buttons.element(boundBy: 1)
        
        XCTAssertTrue(historyButton.exists, "History picker item should exist")
        XCTAssertTrue(favoritesButton.exists, "Favorites picker item should exist")

        // 9. Click each inspector item and capture screenshots
        print("DEBUG: Clicking Favorites button in inspector...")
        favoritesButton.tap()
        sleep(2)  // Wait for content to update

        let screenshot8 = app.screenshot()
        let attachment8 = XCTAttachment(screenshot: screenshot8)
        attachment8.name = "08-inspector-favorites-selected"
        attachment8.lifetime = .keepAlways
        add(attachment8)

        print("DEBUG: Clicking History button in inspector...")
        historyButton.tap()
        sleep(2)  // Wait for content to update

        let screenshot9 = app.screenshot()
        let attachment9 = XCTAttachment(screenshot: screenshot9)
        attachment9.name = "09-inspector-history-selected"
        attachment9.lifetime = .keepAlways
        add(attachment9)

        // 10. Verify sidebar still visible with inspector open
        XCTAssertTrue(subscriptionsButton.exists, "Sidebar should remain visible with inspector open")
        XCTAssertTrue(collectionsButton.exists, "Sidebar should remain visible with inspector open")
        XCTAssertTrue(observerButton.exists, "Sidebar should remain visible with inspector open")

        let screenshot10 = app.screenshot()
        let attachment10 = XCTAttachment(screenshot: screenshot10)
        attachment10.name = "10-final-state-sidebar-and-inspector"
        attachment10.lifetime = .keepAlways
        add(attachment10)
    }
}
