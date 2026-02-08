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
