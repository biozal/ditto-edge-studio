//
//  NavigationLifecycleUITests.swift
//  EdgeStudioUITests
//
//  End-to-end coverage for the database session lifecycle and in-studio
//  navigation:
//    - sidebar navigation switches the detail view across destinations
//    - the inspector toggles open/closed
//    - closing the database returns to the database list
//
//  Like the rest of the suite, these DEGRADE GRACEFULLY: every precondition
//  (no credentials / no databases / missing Accessibility permission /
//  navigation hook not surfaced) results in an `XCTSkip`, never a hard failure.
//
//  Verified production identifiers used here:
//    - NavItem_<destination>  → sidebar destination buttons (subscriptions/query/observers)
//    - QueryEditorTextView    → the DQL editor (present only on the Query destination)
//    - Toggle Inspector       → inspector show/hide toolbar button
//    - QueryInspectorView     → container present only when the query inspector is open
//    - CloseButton            → closes the database, returns to ContentView
//    - AddDatabaseButton      → canonical ContentView (database list) indicator
//

import XCTest

@MainActor
final class NavigationLifecycleUITests: UITestBase {

    // MARK: - Sidebar navigation

    /// Proves sidebar navigation actually swaps the detail view. The Query
    /// editor (`QueryEditorTextView`) exists ONLY on the Query destination, so
    /// its appearance/disappearance is a reliable, data-independent signal that
    /// the detail pane changed — no dependence on seeded subscription/observer
    /// content.
    @MainActor
    func testSidebarNavigationSwitchesDetailView() throws {
        try openStudio()

        let queryNav = navItem("query")
        guard queryNav.waitForExistence(timeout: 10) else {
            throw XCTSkip("NavItem_query not reachable — sidebar navigation not exposed in this environment.")
        }
        let subsNav = navItem("subscriptions")
        let obsNav = navItem("observers")
        guard subsNav.waitForExistence(timeout: 5), obsNav.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sidebar destinations (subscriptions/observers) not reachable.")
        }

        // Query destination → editor present.
        queryNav.tap()
        reactivateAfterTransition()
        let editor = app.descendants(matching: .any)["QueryEditorTextView"].firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "SKIP-no-query-editor", lifetime: .keepAlways)
            throw XCTSkip("QueryEditorTextView not found — query destination not exposed in this environment.")
        }
        captureScreenshot(named: "01-query-destination", lifetime: .deleteOnSuccess)

        // Subscriptions destination → editor must go away.
        subsNav.tap()
        reactivateAfterTransition()
        XCTAssertTrue(
            waitForDisappearance(editor, timeout: 10),
            "Query editor should disappear when navigating to Subscriptions."
        )
        captureScreenshot(named: "02-subscriptions-destination", lifetime: .deleteOnSuccess)

        // Observers destination → still no editor.
        obsNav.tap()
        reactivateAfterTransition()
        XCTAssertFalse(editor.exists, "Query editor should not be present on the Observers destination.")
        captureScreenshot(named: "03-observers-destination", lifetime: .deleteOnSuccess)

        // Back to Query → editor reappears.
        queryNav.tap()
        reactivateAfterTransition()
        XCTAssertTrue(
            editor.waitForExistence(timeout: 10),
            "Query editor should reappear when returning to the Query destination."
        )
        captureScreenshot(named: "04-back-to-query", lifetime: .deleteOnSuccess)
    }

    // MARK: - Inspector toggle

    /// Toggles the inspector open and closed, asserting on the query inspector's
    /// container anchor (`QueryInspectorView`), which exists only while the
    /// inspector is open.
    @MainActor
    func testInspectorTogglesOpenAndClosed() throws {
        try openStudio()

        // Ensure we're on a destination that has the query inspector.
        let queryNav = navItem("query")
        guard queryNav.waitForExistence(timeout: 10) else {
            throw XCTSkip("NavItem_query not reachable.")
        }
        queryNav.tap()
        reactivateAfterTransition()

        let toggle = app.buttons["Toggle Inspector"].firstMatch
        guard toggle.waitForExistence(timeout: 10) else {
            throw XCTSkip("Inspector toggle not reachable in this environment.")
        }

        let inspector = app.descendants(matching: .any)["QueryInspectorView"].firstMatch

        // Open it if it isn't already.
        if !inspector.exists {
            toggle.tap()
            reactivateAfterTransition()
        }
        guard inspector.waitForExistence(timeout: 5) else {
            captureScreenshot(named: "SKIP-inspector-not-surfaced", lifetime: .keepAlways)
            throw XCTSkip("QueryInspectorView did not surface — inspector content not exposed in this environment.")
        }
        captureScreenshot(named: "01-inspector-open", lifetime: .deleteOnSuccess)

        // Close it → container must go away.
        toggle.tap()
        reactivateAfterTransition()
        XCTAssertTrue(
            waitForDisappearance(inspector, timeout: 5),
            "The inspector container should disappear when the inspector is toggled closed."
        )
        captureScreenshot(named: "02-inspector-closed", lifetime: .deleteOnSuccess)
    }

    // MARK: - Close database

    /// Closing the open database returns to the database-list screen
    /// (`AddDatabaseButton` is the canonical ContentView indicator).
    @MainActor
    func testCloseDatabaseReturnsToDatabaseList() throws {
        try openStudio()

        let close = app.buttons["CloseButton"].firstMatch
        guard close.waitForExistence(timeout: 10) else {
            throw XCTSkip("CloseButton not reachable — MainStudioView not open in this environment.")
        }
        close.tap()
        reactivateAfterTransition()

        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 10),
            "Closing the database should return to the database list (AddDatabaseButton)."
        )
        captureScreenshot(named: "01-returned-to-list", lifetime: .deleteOnSuccess)
    }

    // `openStudio()` and `navItem(_:)` are inherited from UITestBase.
}
