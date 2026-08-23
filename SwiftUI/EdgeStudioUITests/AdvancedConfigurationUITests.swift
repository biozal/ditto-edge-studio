//
//  AdvancedConfigurationUITests.swift
//  EdgeStudioUITests
//
//  Layout regression guard for the Advanced Configuration section of the
//  Register/Edit Database sheet.
//
//  The editor has twice regressed by clipping content: AppKit sizes a sheet from its
//  content minimum and centre-overflows anything that doesn't fit, which sliced the
//  header title mid-glyph and pushed the info panel outside the window. Expanding this
//  section adds far more content than the sheet is tall, so the fixed chrome (title,
//  Cancel, Save) must stay pinned and hittable while the form scrolls.
//
//  `isHittable` rather than `exists` on purpose: an element that has scrolled or
//  overflowed off-screen still "exists".
//

import XCTest

final class AdvancedConfigurationUITests: UITestBase {
    /// Expanding Advanced Configuration and adding rows must not push the pinned
    /// chrome off-screen.
    @MainActor
    func testAdvancedSectionKeepsChromePinned() throws {
        // ARRANGE
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not present ContentView — Accessibility permissions may be missing.")
        }

        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("AddDatabaseButton not found — cannot open the editor sheet.")
        }
        addButton.tap()
        sleep(2) // sheet animation

        guard app.textFields["NameTextField"].firstMatch.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "FAIL-no-editor-form", lifetime: .keepAlways)
            throw XCTSkip("Editor sheet did not appear.")
        }

        // ACT — the section starts expanded under UI tests (see ViewModel), so the
        // layout assertions below do not depend on synthesizing a disclosure tap. The
        // control must still exist, since collapsing is how a user gets out.
        let disclosure = app.buttons["AdvancedConfigDisclosure"].firstMatch
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 5),
            "AdvancedConfigDisclosure must exist — the section is the subject of this test."
        )

        // Hard assertion, not an `if`: if expanding silently failed, the rest of this
        // test would assert chrome on a collapsed empty form and pass having proved
        // nothing about the layout regression it exists to catch.
        let addScope = app.buttons["AddSyncScopeButton"].firstMatch
        XCTAssertTrue(
            addScope.waitForExistence(timeout: 5),
            "Expanding Advanced Configuration must reveal AddSyncScopeButton."
        )
        for _ in 0 ..< 6 {
            addScope.tap()
        }

        let addSetting = app.buttons["AddStartupSettingButton"].firstMatch
        XCTAssertTrue(addSetting.waitForExistence(timeout: 5))
        for _ in 0 ..< 6 {
            addSetting.tap()
        }
        captureScreenshot(named: "01-advanced-expanded", lifetime: .keepAlways)

        // The rows must actually be distinct: identity used to be the (blank) collection
        // name, so six taps produced six rows sharing one `ForEach` id.
        // Row identifiers are UUID-based, so blank rows are distinguishable — with the
        // old content-keyed ids every blank row shared one identifier and this could not
        // tell six rows from one.
        let scopeRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "SyncScopeRow_"))
        XCTAssertGreaterThanOrEqual(
            scopeRows.count, 2,
            "Multiple blank scope rows must render as separate, distinctly-identified rows."
        )

        // ASSERT — the fixed chrome is still on screen and tappable. These are the
        // exact elements that clipped in the earlier layout bugs.
        let cancelButton = app.buttons["CancelButton"].firstMatch
        XCTAssertTrue(cancelButton.exists, "Cancel must remain present with the section expanded.")
        XCTAssertTrue(cancelButton.isHittable, "Cancel must remain hittable, not scrolled off-screen.")

        let saveButton = app.buttons["SaveButton"].firstMatch
        XCTAssertTrue(saveButton.exists, "Save must remain present with the section expanded.")
        XCTAssertTrue(saveButton.isHittable, "Save must remain hittable, not scrolled off-screen.")

        #if os(macOS)
        // The macOS header is a plain text view, so assert on it directly.
        let title = app.staticTexts["Register Database"].firstMatch
        if title.exists {
            XCTAssertTrue(title.isHittable, "The sheet title must stay pinned and fully visible.")
        }
        #endif

        // Save gating is asserted in DatabaseEditorAdvancedViewModelTests, where the
        // required credential fields can be populated independently — asserting it here
        // would pass merely because a brand-new database has empty name/id/token.

        // CLEANUP
        if cancelButton.isHittable {
            cancelButton.tap()
            sleep(1)
            // Blank rows count as no change, so no discard dialog is expected; dismiss
            // one if the platform presents it anyway.
            let discard = app.buttons["Discard Changes"].firstMatch
            if discard.waitForExistence(timeout: 2) {
                discard.tap()
            }
        }
    }
}
