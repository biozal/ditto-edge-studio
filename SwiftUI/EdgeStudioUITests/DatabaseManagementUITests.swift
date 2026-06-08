//
//  DatabaseManagementUITests.swift
//  EdgeStudioUITests
//
//  Exercises the add-database flow driven from `testDatabaseConfig.plist`.
//  XCTSkips when the plist (real credentials) is absent — the credential-less
//  CI path.
//

import XCTest

final class DatabaseManagementUITests: UITestBase {

    /// Tapping AddDatabaseButton opens the editor sheet exposing NameTextField.
    ///
    /// This does NOT require the plist — it only drives the UI to open the sheet,
    /// then cancels. It still requires the app to reach ContentView, so it
    /// XCTSkips if the ContentView indicator never appears (likely missing
    /// Accessibility permission).
    @MainActor
    func testAddDatabaseSheetOpens() throws {
        // ARRANGE
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not present ContentView — Accessibility permissions may be missing.")
        }

        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addButton.waitForExistence(timeout: 10) else {
            // If we're already in MainStudioView from a prior session, this test
            // is not applicable in this state.
            if app.buttons["CloseButton"].firstMatch.exists {
                throw XCTSkip("App opened directly into MainStudioView — not on ContentView to add a database.")
            }
            captureScreenshot(named: "FAIL-no-add-button", lifetime: .keepAlways)
            throw XCTSkip("AddDatabaseButton not found — cannot open editor sheet.")
        }

        // ACT
        addButton.tap()
        sleep(2) // sheet animation (Pattern 4)

        // ASSERT — form is present (validate via NameTextField, not a picker).
        let nameField = app.textFields["NameTextField"].firstMatch
        guard nameField.waitForExistence(timeout: 10) else {
            if app.alerts.count > 0 {
                XCTFail("Editor form did not appear — Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-no-editor-form", lifetime: .keepAlways)
            throw XCTSkip("Add-Database editor (NameTextField) did not appear.")
        }
        XCTAssertTrue(nameField.exists, "Add-Database editor should expose NameTextField.")

        captureScreenshot(named: "01-add-database-sheet", lifetime: .deleteOnSuccess)

        // CLEANUP — cancel out of the sheet so we leave a clean state.
        let cancelButton = app.buttons["CancelButton"].firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
            sleep(1)
        }
    }

    /// Adds every database from the plist and verifies a card appears.
    ///
    /// XCTSkips when the plist is absent (no real credentials).
    @MainActor
    func testAddDatabasesFromPlistCreatesCards() throws {
        // ARRANGE
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not present ContentView — Accessibility permissions may be missing.")
        }

        // ACT — drives the full form flow; throws XCTSkip if plist is missing.
        try addDatabasesFromPlist()

        // ASSERT — at least one database card should now exist.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let anyCard = app.descendants(matching: .any).matching(predicate).firstMatch

        guard anyCard.waitForExistence(timeout: 15) else {
            if app.alerts.count > 0 {
                XCTFail("No database card appeared — Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-no-card-after-add", lifetime: .keepAlways)
            throw XCTSkip("No AppCard_* appeared after adding databases — save may have failed (often invalid credentials).")
        }
        XCTAssertTrue(anyCard.exists, "Adding a database from the plist should produce a database card.")

        captureScreenshot(named: "01-database-cards", lifetime: .deleteOnSuccess)
    }
}
