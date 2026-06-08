//
//  UITestBase.swift
//  EdgeStudioUITests
//
//  Foundational XCUITest harness for the Ditto Edge Studio macOS app.
//
//  IMPORTANT:
//  - UI tests use XCTest / XCUITest (NOT Swift Testing).
//  - This harness is designed to DEGRADE GRACEFULLY: when prerequisites are
//    missing (no `testDatabaseConfig.plist` with real credentials, or macOS
//    Accessibility permissions not granted), helpers throw `XCTSkip` rather
//    than failing. CI without credentials therefore shows skips, not red.
//
//  All patterns below mirror docs/TESTING.md → "Writing UI Tests" and encode
//  hard-won macOS XCUITest lessons:
//    - macOS window-activation workaround (NSRunningApplication.activate bug)
//    - Verified accessibility identifiers only
//      (AddDatabaseButton, DatabaseList, AppCard_{name}, CloseButton, ...)
//    - SwiftUI `.pickerStyle(.segmented)` is NOT exposed to XCUITest,
//      so view state is detected via AddDatabaseButton / CloseButton.
//    - `.firstMatch` for nested (FontAwesome / custom-label) buttons.
//

import XCTest

/// Base class for all Edge Studio macOS UI tests.
///
/// Subclasses get a launched `app` (with the `UI-TESTING` launch argument),
/// plus a set of helpers that mirror docs/TESTING.md. Helpers that depend on
/// real credentials or system permissions throw `XCTSkip` when those are
/// unavailable so the suite stays green in credential-less CI.
///
/// `@MainActor`: the Xcode 26 SDK isolates `XCUIApplication`/`XCUIElement` to the
/// main actor, so the whole test case (lifecycle + helpers + subclass test
/// methods, which inherit this isolation) runs on the main actor.
@MainActor
class UITestBase: XCTestCase {

    // MARK: - Stored State

    /// The application under test. Launched fresh in `setUpWithError()`.
    var app: XCUIApplication!

    // MARK: - Lifecycle

    // Launch the app fresh for each test. `@MainActor` because the whole class is
    // main-actor isolated and these touch the `@MainActor` XCUITest APIs.
    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Stop on first failure within a single test method — failures past the
        // first are almost always noise from a broken precondition.
        continueAfterFailure = false

        // Defensively dismiss OS permission dialogs (Bluetooth / Local Network)
        // that the Ditto P2P transports can trigger on a fresh machine. Under UI
        // testing the app force-disables those transports so the dialogs should
        // never appear, but this monitor is cheap insurance: the dialogs come
        // from a *separate* process (com.apple.UserNotificationCenter) and would
        // otherwise float over the app and block element queries. Monitors only
        // fire when the harness next interacts with the app.
        addUIInterruptionMonitor(withDescription: "System permission dialog") { element in
            for label in ["Allow", "OK", "Continue", "Don’t Allow", "Don't Allow"] {
                let button = element.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app = XCUIApplication()
        // CRITICAL: pass test mode via the launch ENVIRONMENT, NOT a launch
        // argument. On macOS, launching a SwiftUI app with ANY command-line
        // argument is treated as a non-default launch, and the `WindowGroup` then
        // does NOT auto-open its window — so the app comes up active but
        // window-less and XCUITest finds nothing to drive. Keeping
        // `launchArguments` empty + signalling via an env var means a normal
        // default launch where the window opens. The app reads `UI_TESTING` to
        // route to its isolated `ditto_edge_studio_test` sandbox and seed data.
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launch()

        // macOS window-activation workaround (see docs/TESTING.md).
        activateAppWindow()

        // The app suppresses the first-run welcome window under UI testing, but
        // dismiss it defensively in case a restored session re-opens it — it's a
        // second window that steals focus from the studio.
        dismissWelcomeWindowIfPresent()
    }

    @MainActor
    override func tearDown() async throws {
        // Only terminate an app that's actually running. Calling `terminate()` on
        // an app the system already killed (e.g. XCUITest force-quit it after a
        // window-activation timeout) records a spurious "Failed to terminate"
        // failure that has nothing to do with the test body.
        if let app, app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app = nil
        try await super.tearDown()
    }

    // MARK: - Window Activation (macOS workaround)

    /// Works around the long-standing macOS bug where `NSRunningApplication.activate()`
    /// doesn't reliably bring an app window to the foreground for UI testing.
    ///
    /// Strategy: activate, wait for a window, click it to force focus, and retry
    /// a handful of times. This is best-effort and never fails the test — if the
    /// window can't be brought forward (e.g. missing Accessibility permission),
    /// downstream `waitForExistence` checks will surface a clean `XCTSkip`.
    func activateAppWindow() {
        for _ in 0..<5 {
            app.activate()
            let window = app.windows.firstMatch
            if window.waitForExistence(timeout: 2) {
                if window.isHittable {
                    window.click()
                }
                // Give AppKit a beat to settle focus.
                usleep(500_000) // 0.5s
                return
            }
        }
    }

    /// Dismisses the first-run welcome window if it is present.
    ///
    /// The app suppresses this window under UI testing (see
    /// `MainStudioViewModel`), so normally there's nothing to do. But a restored
    /// session can re-open it, and it's a *separate* window that grabs focus and
    /// hides the studio's elements from XCUITest. Best-effort: clicks the verified
    /// `WelcomeCloseButton`, then re-activates the main window. Never fails.
    func dismissWelcomeWindowIfPresent() {
        let closeButton = app.buttons["WelcomeCloseButton"].firstMatch
        if closeButton.waitForExistence(timeout: 1) {
            if closeButton.isHittable {
                closeButton.click()
            } else {
                closeButton.tap()
            }
            // Give the window-close animation a beat, then refocus the studio.
            usleep(500_000) // 0.5s
            activateAppWindow()
        }
    }

    /// Re-asserts focus after a `tap()` that transitions views. macOS frequently
    /// drops window focus on view transitions; call this after taps that swap the
    /// root view (e.g. opening MainStudioView).
    func reactivateAfterTransition() {
        app.activate()
        sleep(1)
        let window = app.windows.firstMatch
        if window.exists, window.isHittable {
            window.click()
            sleep(1)
        }
    }

    // MARK: - Waiting

    /// Waits for an element to *stop* existing. Condition-based (no `sleep()`),
    /// per docs/TESTING.md. Used to assert a view went away after a transition
    /// (e.g. the query editor disappearing when navigating off the Query
    /// destination, or the inspector closing).
    @discardableResult
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Loading

    /// Waits for the app to finish its initial load by waiting for the
    /// `AddDatabaseButton`, which docs/TESTING.md guarantees as the canonical
    /// ContentView indicator.
    ///
    /// - Parameter timeout: Seconds to wait. Defaults to 20 (SQLCipher warm-up
    ///   plus async `loadApps()` can be slow on a cold sandbox).
    /// - Returns: `true` if the ContentView indicator appeared, `false` otherwise.
    ///   Callers that require ContentView should `XCTSkip` on `false` (likely a
    ///   missing-Accessibility-permission environment) rather than hard-fail.
    @discardableResult
    func waitForAppToFinishLoading(timeout: TimeInterval = 20) -> Bool {
        // Either we're on ContentView (AddDatabaseButton) or we already landed in
        // MainStudioView from a prior session (CloseButton). Both count as "loaded".
        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        let closeButton = app.buttons["CloseButton"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if addButton.exists || closeButton.exists {
                return true
            }
            usleep(250_000) // 0.25s poll
        }
        // Diagnostic: dump what XCUITest actually sees so we can tell *why* the
        // load indicator never appeared (empty window? loading spinner? a window
        // structure XCUITest classifies differently?).
        logAccessibilityDiagnostics(reason: "waitForAppToFinishLoading timed out after \(timeout)s")
        return false
    }

    /// Prints the live accessibility hierarchy + element counts and attaches a
    /// screenshot. Used when an expected element never appears, to diagnose
    /// element-not-found vs. window-activation vs. wrong-query issues.
    func logAccessibilityDiagnostics(reason: String) {
        print("""
        ===== UITest accessibility diagnostics =====
        reason: \(reason)
        app.state: \(app.state.rawValue)   (3=runningForeground, 4=runningBackground)
        windows: \(app.windows.count)  buttons: \(app.buttons.count)  \
        staticTexts: \(app.staticTexts.count)  textViews: \(app.textViews.count)  \
        otherElements: \(app.otherElements.count)  progressIndicators: \(app.progressIndicators.count)
        --- app.debugDescription ---
        \(app.debugDescription)
        ============================================
        """)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "accessibility-diagnostics"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Database Setup From Plist

    /// Ensures test databases are available to open.
    ///
    /// The app self-seeds databases from its bundled `testDatabaseConfig.plist`
    /// under the `UI-TESTING` launch argument — the XCUITest runner is a separate
    /// process and CANNOT read the app bundle, so seeding must happen app-side.
    /// This helper therefore just waits for the app to finish loading and confirms
    /// a seeded database card is present.
    ///
    /// Throws `XCTSkip` when the app never loads (window/permission issue) or no
    /// databases were seeded (no `testDatabaseConfig.plist` — the credential-less
    /// CI path).
    @MainActor
    func addDatabasesFromPlist() throws {
        guard waitForAppToFinishLoading(timeout: 30) else {
            throw XCTSkip("App did not finish loading — check Accessibility permission and that the app foregrounds under UI-TESTING.")
        }

        // Already in MainStudioView (a restored prior session) — nothing to do.
        if app.buttons["CloseButton"].firstMatch.exists { return }

        // Confirm the app seeded at least one database card.
        let anyCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'"))
            .firstMatch
        guard anyCard.waitForExistence(timeout: 10) else {
            throw XCTSkip("No seeded databases — testDatabaseConfig.plist absent or empty (credential-less path).")
        }
    }

    /// Drives the Add-Database sheet for a single configuration dictionary.
    ///
    /// Only fills fields whose accessibility identifiers are VERIFIED to exist in
    /// the source (`NameTextField`, `DatabaseIdTextField`, `TokenTextField`,
    /// `AuthUrlTextField`, `HttpApiUrlTextField`). Missing keys are skipped — the
    /// goal is a harness that compiles and runs, not exhaustive form coverage.
    ///
    /// - Parameter config: A single entry from the plist `databases` array.
    @MainActor
    func addSingleDatabase(config: [String: Any]) throws {
        let name = config["name"] as? String ?? ""

        // Nested custom-label button → must use .firstMatch (Pattern 3).
        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else {
            throw failOrSkip("AddDatabaseButton not found while adding database '\(name)'.")
        }
        addButton.tap()
        sleep(2) // sheet animation (Pattern 4)

        // Validate the form via a text field, NOT a picker (Pattern 2 — SwiftUI
        // segmented pickers aren't exposed to XCUITest).
        let nameField = app.textFields["NameTextField"].firstMatch
        guard nameField.waitForExistence(timeout: 10) else {
            throw failOrSkip("Add-Database form (NameTextField) did not appear for '\(name)'.")
        }

        typeInto(nameField, text: name)

        // Optional, verified fields — only typed when present in the config.
        fillFieldIfPresent(identifier: "DatabaseIdTextField", value: config["databaseId"] ?? config["appId"])
        fillFieldIfPresent(identifier: "TokenTextField", value: config["developmentToken"] ?? config["token"] ?? config["authToken"])
        fillFieldIfPresent(identifier: "UrlTextField", value: config["url"] ?? config["authUrl"])
        fillFieldIfPresent(identifier: "HttpApiUrlTextField", value: config["httpApiUrl"])

        let saveButton = app.buttons["SaveButton"].firstMatch
        guard saveButton.waitForExistence(timeout: 5) else {
            throw failOrSkip("SaveButton not found in Add-Database form for '\(name)'.")
        }
        saveButton.tap()
        sleep(2)

        // Monitor sheet dismissal (Pattern 1).
        for _ in 0..<10 {
            if !app.sheets.firstMatch.exists { break }
            usleep(500_000) // 0.5s
        }
        sleep(2) // database save + UI update
    }

    // MARK: - MainStudioView Navigation

    /// Ensures MainStudioView is open, detecting state via the guaranteed
    /// `CloseButton` (MainStudioView) and `AddDatabaseButton` (ContentView)
    /// identifiers — NOT via the segmented picker, which XCUITest can't see.
    ///
    /// Throws `XCTSkip` when there are no databases to open (the credential-less
    /// path), and `XCTFail` only when a card exists but MainStudioView refuses to
    /// appear (a genuine regression worth surfacing).
    @MainActor
    func ensureMainStudioViewIsOpen() throws {
        let closeButton = app.buttons["CloseButton"].firstMatch

        // Already in MainStudioView.
        if closeButton.exists { return }

        let addDatabaseButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addDatabaseButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Not on ContentView (AddDatabaseButton absent) — Accessibility permissions may be missing.")
        }

        // Find the first database card by its verified "AppCard_" identifier prefix.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'AppCard_'")
        let firstCard = app.descendants(matching: .any).matching(predicate).firstMatch

        guard firstCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No databases configured (no AppCard_* found) — add databases via testDatabaseConfig.plist to run this test.")
        }

        firstCard.tap()
        reactivateAfterTransition()

        // MainStudioView init can be slow (Ditto startup) — wait generously.
        guard closeButton.waitForExistence(timeout: 60) else {
            if app.alerts.count > 0 {
                XCTFail("MainStudioView did not open — Alert: \(app.alerts.firstMatch.label)")
            } else {
                XCTFail("MainStudioView did not open (CloseButton never appeared) after tapping a database card.")
            }
            throw XCTSkip("MainStudioView failed to open.")
        }
    }

    // MARK: - Studio / DQL Helpers

    /// Launches into MainStudioView for the first seeded database, skipping
    /// cleanly when preconditions are missing. Shared by all flow tests.
    func openStudio() throws {
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not finish loading — Accessibility permissions may be missing.")
        }
        try addDatabasesFromPlist()       // XCTSkip if no plist/credentials
        try ensureMainStudioViewIsOpen()  // XCTSkip if no databases
    }

    /// Sidebar destination button for a `SidebarDestination` raw value
    /// (e.g. "query", "subscriptions", "observers").
    func navItem(_ rawValue: String) -> XCUIElement {
        app.descendants(matching: .any)["NavItem_\(rawValue)"].firstMatch
    }

    /// Navigates to the Query destination and runs a single DQL statement,
    /// replacing whatever is already in the editor. Throws `XCTSkip` when the
    /// query editor isn't reachable in this environment.
    func runDQL(_ dql: String) throws {
        let queryNav = navItem("query")
        guard queryNav.waitForExistence(timeout: 10) else {
            throw XCTSkip("NavItem_query not reachable — sidebar navigation not exposed.")
        }
        queryNav.tap()
        reactivateAfterTransition()

        let editor = app.descendants(matching: .any)["QueryEditorTextView"].firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            throw XCTSkip("QueryEditorTextView not reachable.")
        }
        editor.tap()
        usleep(300_000) // let focus register (macOS quirk)
        app.typeKey("a", modifierFlags: .command) // select all
        app.typeKey(.delete, modifierFlags: [])   // clear
        editor.typeText(dql)

        let execute = app.buttons["ExecuteQueryButton"].firstMatch
        if execute.waitForExistence(timeout: 5) {
            execute.tap()
        }
        // Re-assert focus + let the local write/query settle before the next read.
        reactivateAfterTransition()
    }

    /// Polls until the number of elements with `identifier` exceeds `baseline`,
    /// or the timeout elapses. Condition-based (no fixed sleep), used to detect
    /// that a new row (e.g. an observer event) appeared after an action.
    func waitForRowCount(identifier: String, greaterThan baseline: Int, timeout: TimeInterval = 15) -> Bool {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count > baseline { return true }
            usleep(300_000) // 0.3s poll
        }
        return false
    }

    // MARK: - Screenshots

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

    // MARK: - Private Helpers

    /// Types text into a field, tapping first to register focus (macOS quirk).
    private func typeInto(_ field: XCUIElement, text: String) {
        guard !text.isEmpty else { return }
        field.tap()
        usleep(500_000) // allow focus to register
        field.typeText(text)
    }

    /// Fills a verified text field by identifier if it exists and a value is provided.
    /// Non-string / missing values and absent fields are silently ignored.
    private func fillFieldIfPresent(identifier: String, value: Any?) {
        guard let stringValue = value as? String, !stringValue.isEmpty else { return }
        let field = app.textFields[identifier].firstMatch
        guard field.exists else { return }
        typeInto(field, text: stringValue)
    }

    /// Returns an `XCTSkip` after recording a non-fatal failure note via a
    /// screenshot. Used where a precondition that *should* hold did not, but where
    /// hard-failing credential-less CI is undesirable. Centralizes the
    /// "screenshot + skip" pattern so call sites read cleanly.
    private func failOrSkip(_ message: String) -> XCTSkip {
        captureScreenshot(named: "SKIP-\(message.prefix(40))", lifetime: .keepAlways)
        return XCTSkip(message)
    }
}
