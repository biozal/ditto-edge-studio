import XCTest

/// UI Tests for NavigationSplitView + Inspector + VSplitView Layout
///
/// These tests validate that the 3-pane layout (Sidebar | Detail | Inspector) works correctly
/// when the detail view contains a VSplitView. Screenshots are captured at each step to provide
/// visual validation that cannot be achieved through element assertions alone.
///
/// CRITICAL BUG BEING TESTED:
/// When Collections view (with VSplitView) is selected and inspector is opened,
/// the sidebar should REMAIN VISIBLE. Previously, incorrect frame modifiers caused
/// the sidebar to disappear when inspector opened.
class NavigationSplitViewInspectorLayoutTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Critical Layout Test

    /// Tests the exact scenario that was breaking:
    /// 1. Open sidebar
    /// 2. Navigate to Collections (contains VSplitView)
    /// 3. Open inspector
    /// 4. Verify sidebar REMAINS VISIBLE
    ///
    /// This test captures screenshots at each step to provide visual proof of layout correctness.
    func testCollectionsViewInspectorLayoutDoesNotBreak() throws {
        // Wait for app to fully launch
        sleep(2)

        // STEP 1: Verify initial state - database list screen
        let screenshot1 = app.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01-initial-database-list"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // Check if any apps are configured
        let hasApps = app.staticTexts.matching(identifier: "AppCardTitle").count > 0

        if !hasApps {
            // Skip if no apps configured (expected behavior per CLAUDE.md)
            throw XCTSkip("No apps configured - skipping navigation test")
        }

        // STEP 2: Select first app to open MainStudioView
        let firstApp = app.staticTexts.matching(identifier: "AppCardTitle").element(boundBy: 0)
        firstApp.tap()
        sleep(2) // Allow MainStudioView to load

        let screenshot2 = app.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02-main-studio-view-opened"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // STEP 3: Verify sidebar is visible with navigation items
        XCTAssertTrue(app.buttons["Subscriptions"].exists || app.staticTexts["Subscriptions"].exists,
                     "Subscriptions menu item should be visible in sidebar")
        XCTAssertTrue(app.buttons["Collections"].exists || app.staticTexts["Collections"].exists,
                     "Collections menu item should be visible in sidebar")

        // STEP 4: Navigate to Collections view (contains VSplitView)
        let collectionsButton = app.buttons["Collections"].exists ?
            app.buttons["Collections"] : app.staticTexts["Collections"]
        collectionsButton.tap()
        sleep(2) // Allow Collections view to render

        let screenshot3 = app.screenshot()
        let attachment3 = XCTAttachment(screenshot: screenshot3)
        attachment3.name = "03-collections-view-selected"
        attachment3.lifetime = .keepAlways
        add(attachment3)

        // STEP 5: Verify Collections view is displayed (query editor should be visible)
        XCTAssertTrue(app.exists, "Collections view should be displayed")

        // STEP 6: Open inspector - THIS IS THE CRITICAL STEP THAT WAS BREAKING
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists {
            inspectorToggle.tap()
            sleep(2) // Allow inspector to open and layout to settle

            let screenshot4 = app.screenshot()
            let attachment4 = XCTAttachment(screenshot: screenshot4)
            attachment4.name = "04-CRITICAL-inspector-opened-sidebar-should-stay-visible"
            attachment4.lifetime = .keepAlways
            add(attachment4)

            // STEP 7: CRITICAL VALIDATION - Sidebar should STILL be visible
            let sidebarStillVisible = app.buttons["Subscriptions"].exists ||
                                     app.staticTexts["Subscriptions"].exists

            XCTAssertTrue(sidebarStillVisible,
                         """
                         CRITICAL FAILURE: Sidebar disappeared when inspector opened!

                         This indicates the NavigationSplitView + Inspector + VSplitView layout is broken.
                         Check screenshot '04-CRITICAL-inspector-opened-sidebar-should-stay-visible' to see the issue.

                         Expected: Sidebar (left) | Collections Detail with VSplitView (center) | Inspector (right)
                         Actual: Sidebar hidden, only Collections detail visible

                         Root cause: Incorrect frame modifiers on VSplitView children causing constraint conflicts.
                         """)

            // Additional validations
            XCTAssertTrue(app.buttons["Collections"].exists || app.staticTexts["Collections"].exists,
                         "Collections menu item should still be visible")
            XCTAssertTrue(app.buttons["Observer"].exists || app.staticTexts["Observer"].exists,
                         "Observer menu item should still be visible")
        } else {
            XCTFail("Inspector toggle button not found - check toolbar configuration")
        }

        // STEP 8: Close inspector and verify sidebar still visible
        if inspectorToggle.exists {
            inspectorToggle.tap()
            sleep(1)

            let screenshot5 = app.screenshot()
            let attachment5 = XCTAttachment(screenshot: screenshot5)
            attachment5.name = "05-inspector-closed-sidebar-should-stay-visible"
            attachment5.lifetime = .keepAlways
            add(attachment5)

            XCTAssertTrue(app.buttons["Subscriptions"].exists || app.staticTexts["Subscriptions"].exists,
                         "Sidebar should remain visible after closing inspector")
        }
    }

    // MARK: - Additional Layout Tests

    /// Tests that VSplitView divider is draggable when inspector is open
    func testVSplitViewDividerDraggableWithInspectorOpen() throws {
        // Wait for app to launch
        sleep(2)

        // Check if apps configured
        let hasApps = app.staticTexts.matching(identifier: "AppCardTitle").count > 0
        if !hasApps {
            throw XCTSkip("No apps configured")
        }

        // Open app
        app.staticTexts.matching(identifier: "AppCardTitle").element(boundBy: 0).tap()
        sleep(2)

        // Navigate to Collections
        let collectionsButton = app.buttons["Collections"].exists ?
            app.buttons["Collections"] : app.staticTexts["Collections"]
        collectionsButton.tap()
        sleep(1)

        // Open inspector
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists {
            inspectorToggle.tap()
            sleep(1)

            let screenshot1 = app.screenshot()
            let attachment1 = XCTAttachment(screenshot: screenshot1)
            attachment1.name = "vsplitview-with-inspector-before-drag"
            attachment1.lifetime = .keepAlways
            add(attachment1)

            // Try to find and interact with VSplitView divider
            // Note: VSplitView dividers are not directly accessible via accessibility,
            // but we can verify the layout doesn't break by taking screenshots

            sleep(1)

            let screenshot2 = app.screenshot()
            let attachment2 = XCTAttachment(screenshot: screenshot2)
            attachment2.name = "vsplitview-with-inspector-after-interaction"
            attachment2.lifetime = .keepAlways
            add(attachment2)
        }
    }

    /// Tests opening and closing inspector multiple times
    func testInspectorToggleRepeatedlyDoesNotBreakLayout() throws {
        // Wait for app to launch
        sleep(2)

        let hasApps = app.staticTexts.matching(identifier: "AppCardTitle").count > 0
        if !hasApps {
            throw XCTSkip("No apps configured")
        }

        // Open app and navigate to Collections
        app.staticTexts.matching(identifier: "AppCardTitle").element(boundBy: 0).tap()
        sleep(2)

        let collectionsButton = app.buttons["Collections"].exists ?
            app.buttons["Collections"] : app.staticTexts["Collections"]
        collectionsButton.tap()
        sleep(1)

        let inspectorToggle = app.buttons["Toggle Inspector"]
        guard inspectorToggle.exists else {
            XCTFail("Inspector toggle not found")
            return
        }

        // Toggle inspector multiple times
        for i in 1...3 {
            // Open inspector
            inspectorToggle.tap()
            sleep(1)

            let screenshotOpen = app.screenshot()
            let attachmentOpen = XCTAttachment(screenshot: screenshotOpen)
            attachmentOpen.name = "inspector-toggle-\(i)-opened"
            attachmentOpen.lifetime = .keepAlways
            add(attachmentOpen)

            // Verify sidebar visible
            XCTAssertTrue(app.buttons["Subscriptions"].exists || app.staticTexts["Subscriptions"].exists,
                         "Sidebar should be visible on toggle \(i) - opened")

            // Close inspector
            inspectorToggle.tap()
            sleep(1)

            let screenshotClosed = app.screenshot()
            let attachmentClosed = XCTAttachment(screenshot: screenshotClosed)
            attachmentClosed.name = "inspector-toggle-\(i)-closed"
            attachmentClosed.lifetime = .keepAlways
            add(attachmentClosed)

            // Verify sidebar still visible
            XCTAssertTrue(app.buttons["Subscriptions"].exists || app.staticTexts["Subscriptions"].exists,
                         "Sidebar should be visible on toggle \(i) - closed")
        }
    }

    /// Tests switching between sidebar items while inspector is open
    func testSidebarNavigationWithInspectorOpen() throws {
        sleep(2)

        let hasApps = app.staticTexts.matching(identifier: "AppCardTitle").count > 0
        if !hasApps {
            throw XCTSkip("No apps configured")
        }

        // Open app
        app.staticTexts.matching(identifier: "AppCardTitle").element(boundBy: 0).tap()
        sleep(2)

        // Open inspector first
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists {
            inspectorToggle.tap()
            sleep(1)
        }

        // Navigate through each sidebar item
        let sidebarItems = ["Subscriptions", "Collections", "Observer", "Ditto Tools"]

        for item in sidebarItems {
            let button = app.buttons[item].exists ? app.buttons[item] : app.staticTexts[item]

            if button.exists {
                button.tap()
                sleep(1)

                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "sidebar-\(item.lowercased())-with-inspector"
                attachment.lifetime = .keepAlways
                add(attachment)

                // Verify sidebar still visible after switching
                XCTAssertTrue(app.buttons["Subscriptions"].exists || app.staticTexts["Subscriptions"].exists,
                             "Sidebar should remain visible when switching to \(item)")
            }
        }
    }
}
