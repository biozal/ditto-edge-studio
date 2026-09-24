#if os(iOS)
import XCTest

@MainActor
final class MobileWorkspaceUITests: MobileUITestCase {
    override var fixture: String {
        "workspace"
    }

    func testQueryRoundTripAndPagination() throws {
        try openWorkspace()
        try navigate(to: "query")
        let documents = (1 ... 12).map { "({\"_id\":\"mobile-\($0)\",\"marker\":\"mobile-result-\($0)\"})" }.joined(separator: ",")
        try runQuery("INSERT INTO mobile_ui DOCUMENTS \(documents)")
        try runQuery("SELECT * FROM mobile_ui ORDER BY _id")
        try require(app.staticTexts["Pg 1"])
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'mobile-result-'")).firstMatch
        try require(result)
        try tapToolbar("Next Page")
        try require(app.staticTexts["Pg 2"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'mobile-result-8'")).firstMatch)
        try tapToolbar("Previous Page")
        try require(app.staticTexts["Pg 1"])
    }

    func testSidebarInspectorAndClose() throws {
        try openWorkspace()
        try navigate(to: "query")
        try require(app.textViews["QueryEditorTextView"])
        try tapToolbar("Toggle Inspector")
        try require(app.descendants(matching: .any)["QueryInspectorView"].firstMatch)
        try dismissInspector()
        try navigate(to: "subscriptions")
        XCTAssertTrue(app.textViews["QueryEditorTextView"].waitForNonExistence(timeout: 5))
        try tapToolbar("CloseButton")
        try require(app.buttons["AddDatabaseButton"])
    }

    func testQueryDraftSurvivesRotationAndBackground() throws {
        try openWorkspace()
        try navigate(to: "query")
        let draft = "SELECT * FROM mobile_draft WHERE marker = 'kept'"
        try replaceText(in: app.textViews["QueryEditorTextView"], with: draft)
        attachGeometry("01-query-portrait")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(waitForValue(app.textViews["QueryEditorTextView"], draft))
        attachGeometry("02-query-landscape")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(waitForValue(app.textViews["QueryEditorTextView"], draft))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["ExecuteQueryButton"].wait(for: \.isHittable, toEqual: true, timeout: 10))
    }

    func testDatabaseAndDocumentsPersistAcrossRelaunch() throws {
        try openWorkspace()
        try navigate(to: "query")
        try runQuery("INSERT INTO mobile_persistence DOCUMENTS ({\"_id\":\"kept\",\"marker\":\"persisted-mobile-value\"})")
        try tapToolbar("CloseButton")
        try require(app.buttons["AddDatabaseButton"])
        app.terminate()
        // Same namespace, same real store; other test cases receive a fresh UUID.
        app.launch()
        try require(app.buttons["AddDatabaseButton"])
        try openWorkspace()
        try navigate(to: "query")
        try runQuery("SELECT * FROM mobile_persistence")
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'persisted-mobile-value'")).firstMatch)
    }

    func testInvalidQueryShowsErrorAndEditorRemainsUsable() throws {
        try openWorkspace()
        try navigate(to: "query")
        try replaceText(in: app.textViews["QueryEditorTextView"], with: "SELECT FROM")
        try tap(app.buttons["ExecuteQueryButton"])
        let alert = try require(app.alerts.firstMatch)
        try tap(alert.buttons["OK"])
        XCTAssertTrue(waitForValue(app.textViews["QueryEditorTextView"], "SELECT FROM"))
        try runQuery("INSERT INTO mobile_errors DOCUMENTS ({\"_id\":\"recovered\"})")
        try runQuery("SELECT * FROM mobile_errors")
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'recovered'")).firstMatch)
    }

    func testPresenceAndLogActionsAreReachable() throws {
        try openWorkspace()
        try navigate(to: "subscriptions")
        let viewer = app.buttons.matching(identifier: "SyncTabPicker")
            .matching(NSPredicate(format: "label == %@", "Viewer")).element
        try tap(viewer)
        XCTAssertTrue(viewer.isSelected)
        try tapToolbar("PresenceViewerControlsMenu")
        try tap(app.buttons["PresenceResetViewButton"])
        try navigate(to: "logging")
        try tapToolbar("LogActionsToolbarMenu")
        let pause = try require(app.buttons["LogPauseToolbarButton"])
        let originalLabel = pause.label
        try tap(pause)
        try tapToolbar("LogActionsToolbarMenu")
        XCTAssertNotEqual(try require(app.buttons["LogPauseToolbarButton"]).label, originalLabel)
        try tap(app.buttons["LogPauseToolbarButton"])
        try tapToolbar("CloseButton")
        try require(app.buttons["AddDatabaseButton"])
    }
}
#endif
