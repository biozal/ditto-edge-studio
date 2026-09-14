//
//  QueryResultsUITests.swift
//  EdgeStudioUITests
//
//  E2E coverage for the query RESULTS surface (the #1 feature):
//    - Pagination: INSERT >pageSize docs → SELECT → Next/Prev change the page.
//    - Table view: switch the results view to Table and assert the inserted
//      value renders as a cell.
//
//  All data is created/torn down via DQL (deterministic, no cloud dependency),
//  keyed by a unique per-run token so residue can't affect assertions. Degrades
//  gracefully (XCTSkip) when preconditions are missing.
//
//  Verified production identifiers used here:
//    - QueryResultsView, ResultsViewModeToggle, ResultTableView
//    - PaginationNextButton, PaginationPrevButton, PaginationPageIndicator
//

import XCTest

@MainActor
final class QueryResultsUITests: UITestBase {
    private let pageCollection = "e2e_page"
    private let tableCollection = "e2e_table"

    // MARK: - Pagination (no view-mode toggle needed — shown in the query bottom bar)

    /// Inserts 12 documents (pageSize defaults to 10 → 2 pages), selects them,
    /// and asserts the page indicator + Next/Prev move between pages.
    @MainActor
    func testPaginationMovesBetweenPages() throws {
        try openStudio()

        let token = "E2E\(UUID().uuidString.prefix(8))"

        // 12 docs in one INSERT. DQL multi-document syntax wraps EACH document
        // in its own parentheses: DOCUMENTS ({...}), ({...}), … — NOT one shared
        // paren list (that's invalid DQL and pops the "query is invalid" alert).
        let docLiterals = (1 ... 12).map { i in
            "({ \"_id\": \"\(token)-\(i)\", \"run\": \"\(token)\" })"
        }.joined(separator: ", ")
        try runDQL("INSERT INTO \(pageCollection) DOCUMENTS \(docLiterals)")

        // Select exactly this run's docs → 12 results → 2 pages at pageSize 10.
        try runDQL("SELECT * FROM \(pageCollection) WHERE run = '\(token)'")

        guard app.descendants(matching: .any)["QueryResultsView"].firstMatch.waitForExistence(timeout: 15) else {
            captureScreenshot(named: "SKIP-no-results", lifetime: .keepAlways)
            throw XCTSkip("Results pane did not appear.")
        }

        guard waitForPageIndicator("1 of 2", timeout: 10) else {
            // XCUIElementQuery is not a Collection (no isEmpty member).
            // swiftlint:disable:next empty_count
            if app.alerts.count != 0 { XCTFail("Pagination blocked by Alert: \(app.alerts.firstMatch.label)") }
            captureScreenshot(named: "FAIL-page-1-of-2", lifetime: .keepAlways)
            XCTFail("12 results at pageSize 10 should show '1 of 2'.")
            try cleanup(token: token, collection: pageCollection)
            return
        }
        captureScreenshot(named: "01-page-1-of-2", lifetime: .deleteOnSuccess)

        // Next → page 2.
        let next = app.buttons["PaginationNextButton"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Next button should exist.")
        next.tap()
        reactivateAfterTransition()
        XCTAssertTrue(waitForPageIndicator("2 of 2", timeout: 10), "Tapping Next should move to '2 of 2'.")
        captureScreenshot(named: "02-page-2-of-2", lifetime: .deleteOnSuccess)

        // Prev → back to page 1.
        let prev = app.buttons["PaginationPrevButton"].firstMatch
        XCTAssertTrue(prev.waitForExistence(timeout: 5), "Prev button should exist.")
        prev.tap()
        reactivateAfterTransition()
        XCTAssertTrue(waitForPageIndicator("1 of 2", timeout: 10), "Tapping Prev should return to '1 of 2'.")

        try cleanup(token: token, collection: pageCollection)
    }

    // MARK: - Table view

    /// Inserts a uniquely-marked doc, selects it, switches the results view to
    /// Table, and asserts the value renders as a cell.
    ///
    /// NOTE: the view-mode toggle is a SwiftUI `.segmented` Picker. On macOS that
    /// is an NSSegmentedControl whose segments are addressable; if XCUITest can't
    /// reach the segment in this environment the test XCTSkips with a screenshot
    /// rather than failing (we'd then add an explicit per-segment hook).
    @MainActor
    func testResultsRenderInTableView() throws {
        try openStudio()

        let token = "E2E\(UUID().uuidString.prefix(8))"
        try runDQL(#"INSERT INTO \#(tableCollection) DOCUMENTS ({ "_id": "id-\#(token)", "marker": "\#(token)" })"#)
        try runDQL("SELECT * FROM \(tableCollection) WHERE marker = '\(token)'")

        guard app.descendants(matching: .any)["QueryResultsView"].firstMatch.waitForExistence(timeout: 15) else {
            throw XCTSkip("Results pane did not appear.")
        }

        // Diagnostic gate: the data must show in the default (Raw) view FIRST.
        // If this fails, the SELECT returned nothing (a query/editor-clearing
        // problem) — which is a different bug than table rendering.
        let rawValue = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", token))
            .firstMatch
        guard rawValue.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "FAIL-no-data-in-raw", lifetime: .keepAlways)
            try cleanup(token: token, collection: tableCollection)
            XCTFail("SELECT returned no rows in the Raw view — the query produced no data (clearing/typing issue), not a table problem.")
            return
        }

        // Switch the results view to Table (segments surface as radioButtons).
        guard selectResultViewMode("Table") else {
            dumpAccessibilityTree(named: "results-toggle-hierarchy")
            captureScreenshot(named: "FAIL-cannot-select-table", lifetime: .keepAlways)
            try cleanup(token: token, collection: tableCollection)
            XCTFail("Could not select the Table view-mode segment — see attached 'results-toggle-hierarchy'.")
            return
        }
        reactivateAfterTransition()

        // The inserted value renders as a table cell.
        let cell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", token, token))
            .firstMatch
        if !cell.waitForExistence(timeout: 10) {
            dumpAccessibilityTree(named: "table-view-hierarchy")
            captureScreenshot(named: "FAIL-no-table-cell", lifetime: .keepAlways)
            try cleanup(token: token, collection: tableCollection)
            XCTFail("Data was present in Raw view but did NOT render as a table cell — table-renderer issue. See attached 'table-view-hierarchy'.")
            return
        }
        captureScreenshot(named: "01-table-shows-data", lifetime: .deleteOnSuccess)

        try cleanup(token: token, collection: tableCollection)
    }

    // MARK: - Helpers

    /// Polls the pagination page indicator until its label/value matches.
    private func waitForPageIndicator(_ expected: String, timeout: TimeInterval = 10) -> Bool {
        let indicator = app.descendants(matching: .any)["PaginationPageIndicator"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if indicator.exists, indicator.label == expected || (indicator.value as? String) == expected {
                return true
            }
            usleep(300_000) // 0.3s poll
        }
        return false
    }

    /// Best-effort DQL cleanup of a run's documents.
    private func cleanup(token: String, collection: String) throws {
        try runDQL("DELETE FROM \(collection) WHERE run = '\(token)' OR marker = '\(token)'")
    }

    /// Selects a results view-mode segment ("Raw"/"Table"/"Profile"), trying the
    /// element types a SwiftUI `.segmented` Picker can surface as on macOS.
    @discardableResult
    private func selectResultViewMode(_ mode: String) -> Bool {
        // Prefer the ⌘1/⌘2/⌘3 keyboard shortcut — no mouse on the segmented
        // control (which beeps), and reliable regardless of element type.
        let keyForMode: [String: String] = ["Raw": "1", "Table": "2", "Profile": "3"]
        if let key = keyForMode[mode] {
            app.typeKey(key, modifierFlags: .command)
            return true
        }
        // Fallback: tap the segment (surfaces as a radioButton on macOS).
        let radio = app.radioButtons["ResultViewMode_\(mode)"].firstMatch
        if radio.waitForExistence(timeout: 2) {
            radio.tap()
            return true
        }
        return false
    }

    /// Prints + attaches the full accessibility hierarchy so we can see exactly
    /// how an element (e.g. the segmented toggle) is exposed to XCUITest.
    private func dumpAccessibilityTree(named name: String) {
        let tree = app.debugDescription
        print("===== \(name) =====\n\(tree)\n===== end \(name) =====")
        let attachment = XCTAttachment(string: tree)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
