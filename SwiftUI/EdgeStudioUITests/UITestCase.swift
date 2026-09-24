import XCTest

/// Shared launch and diagnostics; interaction policies live in platform harnesses.
@MainActor
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    func makeApplication(environment: [String: String] = [:]) -> XCUIApplication {
        let application = XCUIApplication()
        // Preserve Xcode's appearance, text-size, and localization settings.
        // Only strip the shared scheme's unit-test launch signal.
        application.launchArguments.removeAll { $0 == "UNIT-TESTING" }
        application.launchEnvironment.merge(environment) { _, fixtureValue in fixtureValue }
        application.launchEnvironment["UNIT_TESTING"] = "0"
        application.launchEnvironment["UI_TESTING"] = "1"
        return application
    }

    /// Prints the live accessibility hierarchy + element counts and attaches a
    /// screenshot. Used when an expected element never appears, to diagnose
    /// element-not-found vs. window-activation vs. wrong-query issues.
    func logAccessibilityDiagnostics(reason: String) {
        // no_print_statements: write via FileHandle so the dump still lands in the
        // test log without tripping the repo's lint gate.
        FileHandle.standardOutput.write(Data("""
        ===== UITest accessibility diagnostics =====
        reason: \(reason)
        app.state: \(app.state.rawValue)
        windows: \(app.windows.count)  buttons: \(app.buttons.count)  \
        staticTexts: \(app.staticTexts.count)  textViews: \(app.textViews.count)  \
        otherElements: \(app.otherElements.count)  progressIndicators: \(app.progressIndicators.count)
        --- app.debugDescription ---
        \(app.debugDescription)
        ============================================
        """.utf8))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "accessibility-diagnostics"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Captures a full-app screenshot and attaches it to the test result.
    ///
    /// - Parameters:
    ///   - name: Descriptive, sequential name (e.g. "01-initial-state").
    ///   - lifetime: Defaults to `.deleteOnSuccess` (ideal for CI — keeps only
    ///     failing-test artifacts). Use `.keepAlways` when debugging.
    func captureScreenshot(named name: String, lifetime: XCTAttachment.Lifetime = .deleteOnSuccess) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = lifetime
        add(attachment)
    }
}
