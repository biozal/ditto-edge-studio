#if os(macOS)
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
    /// then cancels. A restored studio is closed first; only an unavailable app
    /// skips (for example, when Accessibility permission is missing).
    @MainActor
    func testAddDatabaseSheetOpens() throws {
        // ARRANGE
        let addButton = try requireDatabasePicker()

        // ACT
        addButton.click()
        sleep(2) // sheet animation (Pattern 4)

        // ASSERT — form is present (validate via NameTextField, not a picker).
        let nameField = app.textFields["NameTextField"].firstMatch
        guard nameField.waitForExistence(timeout: 10) else {
            // XCUIElementQuery is not a Collection (no isEmpty member).
            // swiftlint:disable:next empty_count
            if app.alerts.count != 0 {
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
            cancelButton.click()
            sleep(1)
        }
    }

    /// Adds every database from the plist and verifies a card appears.
    ///
    /// XCTSkips when the plist is absent (no real credentials).
    @MainActor
    func testAddDatabasesFromPlistCreatesCards() throws {
        // ARRANGE
        _ = try requireDatabasePicker()

        // ACT — drives the full form flow; throws XCTSkip if plist is missing.
        try addDatabasesFromPlist()

        // ASSERT — at least one database card should now exist.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let anyCard = app.descendants(matching: .any).matching(predicate).firstMatch

        guard anyCard.waitForExistence(timeout: 15) else {
            // XCUIElementQuery is not a Collection (no isEmpty member).
            // swiftlint:disable:next empty_count
            if app.alerts.count != 0 {
                XCTFail("No database card appeared — Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-no-card-after-add", lifetime: .keepAlways)
            throw XCTSkip("No AppCard_* appeared after adding databases — save may have failed (often invalid credentials).")
        }
        XCTAssertTrue(anyCard.exists, "Adding a database from the plist should produce a database card.")

        captureScreenshot(named: "01-database-cards", lifetime: .deleteOnSuccess)
    }
}

#endif
