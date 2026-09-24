#if os(macOS)
import XCTest

/// Exercises the real SDK reader through the dashboard's start/refresh callers.
/// Requires the same configured database fixture as the desktop query tests.
final class SystemMetricsUITests: UITestBase {
    @MainActor
    func testLiveMetricsPollRefreshAndReturn() throws {
        try openStudio()

        let metrics = navItem("systemMetrics")
        XCTAssertTrue(metrics.waitForExistence(timeout: 10), "System Metrics must be available in the sidebar.")
        metrics.click()
        try requireSuccessfulPoll()

        let updated = app.staticTexts["SystemMetricsLastUpdated"].firstMatch
        let updateValue = updated.value as? String
        let updateProperty = updateValue?.isEmpty == false ? "value" : "label"
        let previousUpdate = updateProperty == "value" ? (updateValue ?? "") : updated.label
        XCTAssertFalse(previousUpdate.isEmpty, "The successful poll timestamp must be readable.")
        let refresh = app.buttons["SystemMetricsRefreshButton"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.click()

        // The displayed clock has second precision. Allow the next regular poll
        // as well when an immediate refresh lands within the same second.
        let newerPoll = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "exists == true AND %K != nil AND %K != '' AND %K != %@",
                updateProperty, updateProperty, updateProperty, previousUpdate
            ),
            object: updated
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [newerPoll], timeout: 10),
            .completed,
            "A successful later SDK read must update the dashboard timestamp."
        )
        try requireSuccessfulPoll()

        let query = navItem("query")
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.click()
        XCTAssertTrue(app.textViews["QueryEditorTextView"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(refresh.waitForNonExistence(timeout: 5), "Leaving Metrics must remove its dashboard.")

        metrics.click()
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        try requireSuccessfulPoll()
        captureScreenshot(named: "system-metrics-live-after-return", lifetime: .deleteOnSuccess)
    }

    @MainActor
    private func requireSuccessfulPoll() throws {
        // polledAt is published only by the ready path, never idle, disabled,
        // disconnected or error. A real metric row also proves that SDK items
        // passed through serialization and accumulation, not just an empty read.
        let updated = app.staticTexts["SystemMetricsLastUpdated"].firstMatch
        let ready = updated.waitForExistence(timeout: 15)
        if !ready {
            captureScreenshot(named: "FAIL-system-metrics-poll", lifetime: .keepAlways)
            logAccessibilityDiagnostics(reason: "System Metrics did not publish a successful poll")
        }
        let status = app.staticTexts["SystemMetricsStatusNote"].firstMatch
        _ = try XCTUnwrap(
            ready ? updated : nil,
            "Expected a successful SDK metrics poll. Status: \(status.exists ? displayedText(status) : "unavailable")"
        )

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "SystemMetricsInfoButton_")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The live SDK fixture must report at least one metric series.")
        XCTAssertFalse(status.exists && displayedText(status).contains("read failed"), "The metrics reader must not report an error.")
    }

    @MainActor
    private func displayedText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }
}
#endif
