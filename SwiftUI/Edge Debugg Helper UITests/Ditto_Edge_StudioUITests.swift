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
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    @MainActor
    func testAppLaunches() throws {
        // Verify the app launches successfully
        XCTAssertTrue(app.exists, "App should launch successfully")

        // Verify we're on the database list screen or main studio view
        let databaseListExists = app.staticTexts["Ditto Apps"].exists
        let navigationExists = app.buttons["MenuItem_Subscriptions"].exists

        XCTAssertTrue(
            databaseListExists || navigationExists,
            "Either database list or main studio view should be visible after launch"
        )
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
        // If we're already in MainStudioView, skip this test
        guard app.staticTexts["Ditto Apps"].exists else {
            throw XCTSkip("Already in MainStudioView, skipping database list test")
        }

        // Verify we're on the database list screen by checking for the navigation title
        XCTAssertTrue(
            app.staticTexts["Ditto Apps"].exists,
            "Database list screen with 'Ditto Apps' title should be visible"
        )

        // The app may show either:
        // 1. A list of apps (DatabaseList element)
        // 2. An empty state (when no apps are configured)
        // Both are valid states for the database list screen

        // Just verify we're not stuck in an error state or loading forever
        // by checking that the title is still visible after a brief wait
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(
            app.staticTexts["Ditto Apps"].exists,
            "App should remain on database list screen"
        )
    }

    @MainActor
    func testSelectFirstApp() throws {
        // If we're already in MainStudioView, skip this test
        guard app.staticTexts["Ditto Apps"].exists else {
            throw XCTSkip("Already in MainStudioView, skipping app selection test")
        }

        // Wait for database list
        let databaseList = app.otherElements["DatabaseList"]
        guard databaseList.waitForExistence(timeout: 5) else {
            throw XCTSkip("No apps configured - cannot test app selection")
        }

        // Find and tap the first app card
        // App cards are identified by "AppCard_<name>" but we need to find any card
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstAppCard = databaseList.descendants(matching: .any).matching(predicate).firstMatch

        guard firstAppCard.exists else {
            throw XCTSkip("No app cards found - cannot test app selection")
        }

        // Tap the first app
        firstAppCard.tap()

        // Verify MainStudioView appears
        let navigationPicker = app.segmentedControls["NavigationSegmentedPicker"]
        XCTAssertTrue(
            navigationPicker.waitForExistence(timeout: 10),
            "MainStudioView navigation should appear after selecting an app"
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
}
