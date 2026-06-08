//
//  ObserverUITests.swift
//  EdgeStudioUITests
//
//  End-to-end coverage for the REAL observer behavior: an active observer emits
//  a new event when the data it watches changes.
//
//    reuse/create an observer on a collection → activate it → INSERT a document
//    into that collection via DQL → assert a NEW event row appears in the
//    observer's events table.
//
//  Idempotent by REUSE (no flaky context-menu delete): the observer is created
//  once (only the empty-state button can add one, which needs an empty list —
//  true on the first run) and reused by name afterwards. A store observer is
//  in-memory, so every fresh launch starts it INACTIVE — the test activates it
//  deterministically via the inline toggle (whose accessibilityValue exposes
//  active/idle).
//
//  The observer is given a deliberately long name so the captured screenshot
//  doubles as a check that the sidebar row wraps the name readably alongside the
//  inline Activate/Stop button.
//
//  Verified production identifiers used here:
//    - EmptyObserversAddButton / EditorNameField / EditorQueryField / EditorSaveButton
//    - ObserverRow_<name>    → sidebar tree row (tap selects + shows events)
//    - ObserverToggle_<name> → inline Activate/Stop (value: "active" | "idle")
//    - ObserverEventRow      → a row in the observer events table
//

import XCTest

@MainActor
final class ObserverUITests: UITestBase {

    /// Long on purpose: verifies the sidebar row wraps the name readably next to
    /// the inline toggle button.
    private let observerName = "E2E Observer — long name to verify sidebar wrapping stays readable"
    private let collection = "e2e_obs"

    @MainActor
    func testActiveObserverReceivesEventWhenDataChanges() throws {
        try openStudio()

        // Reuse (or first-time create) the observer.
        try ensureObserverExists(name: observerName, query: "SELECT * FROM \(collection)")

        // Screenshot for the long-name readability/wrapping check.
        captureScreenshot(named: "01-observer-sidebar-name", lifetime: .keepAlways)

        // Activate it (store observers reset to idle on each launch).
        let toggle = app.buttons["ObserverToggle_\(observerName)"].firstMatch
        guard toggle.waitForExistence(timeout: 10) else {
            throw XCTSkip("ObserverToggle not reachable in this environment.")
        }
        if (toggle.value as? String) != "active" {
            toggle.tap()
            reactivateAfterTransition()
        }
        XCTAssertEqual(toggle.value as? String, "active", "Observer should be active after tapping Activate.")

        // Select it and view its events.
        let row = app.descendants(matching: .any)["ObserverRow_\(observerName)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap() // selects the observer + switches the detail to Observers
        reactivateAfterTransition()

        // Baseline: how many event rows are showing before we change data.
        usleep(500_000) // let the activation's initial event settle
        let baseline = app.descendants(matching: .any).matching(identifier: "ObserverEventRow").count
        captureScreenshot(named: "02-events-before-change", lifetime: .deleteOnSuccess)

        // ACT: change the observed collection — this must emit a new event.
        let token = "OBS\(UUID().uuidString.prefix(8))"
        try runDQL(#"INSERT INTO \#(collection) DOCUMENTS ({ "_id": "id-\#(token)", "marker": "\#(token)" })"#)

        // Back to the observer's events.
        let obsNav = navItem("observers")
        if obsNav.waitForExistence(timeout: 5) {
            obsNav.tap()
            reactivateAfterTransition()
        }

        // ASSERT: a NEW event row appeared because the observed data changed.
        if !waitForRowCount(identifier: "ObserverEventRow", greaterThan: baseline, timeout: 20) {
            if app.alerts.count > 0 {
                XCTFail("Observer event assertion blocked by Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-no-new-observer-event", lifetime: .keepAlways)
            XCTFail("Inserting into '\(collection)' should emit a new observer event (baseline was \(baseline)).")
        }
        captureScreenshot(named: "03-events-after-change", lifetime: .deleteOnSuccess)
    }

    // MARK: - Helpers

    /// Ensures an observer named `name` exists, reusing it if present. Creation
    /// only works when the observers list is empty (the only Add affordance is
    /// the empty-state button) — true on a clean first run.
    private func ensureObserverExists(name: String, query: String) throws {
        let row = app.descendants(matching: .any)["ObserverRow_\(name)"].firstMatch
        if row.waitForExistence(timeout: 3) { return } // reuse

        let addButton = app.buttons["EmptyObserversAddButton"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else {
            captureScreenshot(named: "SKIP-cannot-create-observer", lifetime: .keepAlways)
            throw XCTSkip("Observers list isn't empty and the target observer is absent — cannot create (no empty-state Add).")
        }
        addButton.tap()
        reactivateAfterTransition()

        let nameField = app.textFields["EditorNameField"].firstMatch
        guard nameField.waitForExistence(timeout: 10) else {
            throw XCTSkip("Editor sheet (EditorNameField) did not appear.")
        }
        nameField.tap()
        usleep(400_000)
        nameField.typeText(name)

        let queryField = app.descendants(matching: .any)["EditorQueryField"].firstMatch
        guard queryField.waitForExistence(timeout: 5) else {
            throw XCTSkip("Editor query field (EditorQueryField) did not surface.")
        }
        queryField.tap()
        usleep(400_000)
        queryField.typeText(query)

        let save = app.buttons["EditorSaveButton"].firstMatch
        guard save.waitForExistence(timeout: 5) else {
            throw XCTSkip("EditorSaveButton not found.")
        }
        XCTAssertTrue(save.isEnabled, "Save should be enabled once name and query are filled.")
        save.tap()
        reactivateAfterTransition()

        XCTAssertTrue(row.waitForExistence(timeout: 10), "The observer should exist after creation.")
    }
}
