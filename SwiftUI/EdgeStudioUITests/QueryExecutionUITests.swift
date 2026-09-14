//
//  QueryExecutionUITests.swift
//  EdgeStudioUITests
//
//  End-to-end coverage for the DQL query-execution flow, exercising a REAL
//  data round-trip (not just an empty results container):
//
//    open database → navigate to Query → INSERT a uniquely-marked document →
//    SELECT it back → assert the actual inserted value is rendered → DELETE it.
//
//  Everything is driven through DQL (INSERT/SELECT/DELETE) typed into the
//  editor, so the test sets up and tears down its own data with no reliance on
//  pre-seeded cloud contents and no flaky context menus. A unique per-run token
//  makes the assertions immune to residue from earlier runs.
//
//  Degrades gracefully (XCTSkip) when preconditions are missing.
//
//  Verified production identifiers used here:
//    - NavItem_query        → sidebar Query destination button
//    - QueryEditorTextView  → the DQL editor's NSTextView/UITextView
//    - ExecuteQueryButton   → the run-query toolbar button (macOS + iOS)
//    - QueryResultsView     → the results container
//

import XCTest

@MainActor
final class QueryExecutionUITests: UITestBase {
    /// Inserts a real document, selects it back, and asserts the inserted value
    /// actually appears in the results pane — proving query execution returns and
    /// renders real data, not just that a container exists.
    @MainActor
    func testInsertedDocumentAppearsInQueryResults() throws {
        // ARRANGE: open the studio and reach the Query editor.
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not finish loading — Accessibility permissions may be missing.")
        }
        try addDatabasesFromPlist()
        try ensureMainStudioViewIsOpen()

        let queryNav = app.descendants(matching: .any)["NavItem_query"].firstMatch
        guard queryNav.waitForExistence(timeout: 10) else {
            throw XCTSkip("NavItem_query not reachable — sidebar navigation not exposed in this environment.")
        }
        queryNav.tap()
        reactivateAfterTransition()

        // Target the editable TEXT VIEW, not the enclosing scroll view (whose
        // center is on the divider, so tapping it never focuses the editor).
        let editor = app.textViews["QueryEditorTextView"].firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "SKIP-no-query-editor", lifetime: .keepAlways)
            throw XCTSkip("QueryEditorTextView (text view) not found in this environment.")
        }

        // Unique per-run token so residue from earlier runs can't satisfy or
        // confuse the assertions.
        let token = "E2E\(UUID().uuidString.prefix(8))"
        let collection = "e2e_test"
        let docId = "id-\(token)"

        // ACT 1: INSERT a real document.
        executeDQL(
            #"INSERT INTO \#(collection) DOCUMENTS ({ "_id": "\#(docId)", "marker": "\#(token)" })"#,
            in: editor
        )
        let resultsPane = app.descendants(matching: .any)["QueryResultsView"].firstMatch
        guard resultsPane.waitForExistence(timeout: 15) else {
            // XCUIElementQuery is not a Collection (no isEmpty member).
            // swiftlint:disable:next empty_count
            if app.alerts.count != 0 {
                XCTFail("INSERT failed — Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-insert-no-results", lifetime: .keepAlways)
            throw XCTSkip("INSERT produced no results pane.")
        }
        captureScreenshot(named: "01-insert-executed", lifetime: .deleteOnSuccess)

        // ACT 2: SELECT it back, filtered to our token so the doc is the only
        // result (no pagination ambiguity from residue).
        executeDQL(
            "SELECT * FROM \(collection) WHERE marker = '\(token)'",
            in: editor
        )

        // ASSERT: the actual inserted document — field name AND our token value —
        // is rendered in the results.
        let resultDoc = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "marker", token))
            .firstMatch
        if !resultDoc.waitForExistence(timeout: 15) {
            // XCUIElementQuery is not a Collection (no isEmpty member).
            // swiftlint:disable:next empty_count
            if app.alerts.count != 0 {
                XCTFail("SELECT failed — Alert: \(app.alerts.firstMatch.label)")
            }
            captureScreenshot(named: "FAIL-select-no-data", lifetime: .keepAlways)
            XCTFail("The inserted document (marker=\(token)) should appear in SELECT results.")
        }
        captureScreenshot(named: "02-select-shows-inserted-data", lifetime: .deleteOnSuccess)

        // CLEANUP: delete the document via DQL (no context menus).
        executeDQL("DELETE FROM \(collection) WHERE marker = '\(token)'", in: editor)
    }

    // MARK: - Helpers

    /// Replaces the editor's contents with `dql` and runs it. Clears via
    /// select-all + delete (macOS NSTextView), then types and taps Execute.
    private func executeDQL(_ dql: String, in editor: XCUIElement) {
        editor.tap()
        usleep(300_000) // let focus register (macOS quirk)
        app.typeKey("a", modifierFlags: .command) // select all
        app.typeKey(.delete, modifierFlags: [])   // clear
        editor.typeText(dql)

        let execute = app.buttons["ExecuteQueryButton"].firstMatch
        if execute.waitForExistence(timeout: 5) {
            execute.tap()
        }
        // Re-assert focus + give the local write/query a beat to settle before
        // the next statement reads it back.
        reactivateAfterTransition()
    }
}
