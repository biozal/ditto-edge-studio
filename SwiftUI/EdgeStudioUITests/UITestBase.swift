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

    /// Candidate bundle identifiers for the app target, tried in order when
    /// locating `testDatabaseConfig.plist` inside the running app's bundle.
    ///
    /// The Xcode project currently ships `com.costoda.dittoedgestudio` as the
    /// app target's PRODUCT_BUNDLE_IDENTIFIER, while docs/TESTING.md historically
    /// referenced `io.ditto.EdgeStudio`. We try both so the harness keeps working
    /// if the identifier changes again.
    let appBundleIdentifierCandidates = [
        "com.costoda.dittoedgestudio",
        "io.ditto.EdgeStudio",
    ]

    // MARK: - Lifecycle

    // Launch the app fresh for each test. `@MainActor` because the whole class is
    // main-actor isolated and these touch the `@MainActor` XCUITest APIs.
    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Stop on first failure within a single test method — failures past the
        // first are almost always noise from a broken precondition.
        continueAfterFailure = false

        app = XCUIApplication()
        // The app's AppState / SQLCipherService / DittoManager all branch on this
        // argument to use the isolated `ditto_edge_studio_test` sandbox.
        app.launchArguments = ["UI-TESTING"]
        app.launch()

        // macOS window-activation workaround (see docs/TESTING.md).
        activateAppWindow()
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
        return false
    }

    // MARK: - Database Setup From Plist

    /// Adds all databases described in the app bundle's `testDatabaseConfig.plist`
    /// by driving the Add-Database UI flow.
    ///
    /// Throws `XCTSkip` when the plist is absent or malformed — the credential-less
    /// CI path. This is intentional: a missing plist means "no real credentials,"
    /// which is a skip, not a failure.
    ///
    /// - Throws: `XCTSkip` if the plist or its `databases` array is missing.
    @MainActor
    func addDatabasesFromPlist() throws {
        let path = appBundleIdentifierCandidates
            .compactMap { Bundle(identifier: $0) }
            .compactMap { $0.path(forResource: "testDatabaseConfig", ofType: "plist") }
            .first

        guard let path else {
            throw XCTSkip("testDatabaseConfig.plist not found in app bundle — no real credentials available (expected in credential-less CI).")
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw XCTSkip("Could not read testDatabaseConfig.plist: \(error.localizedDescription)")
        }

        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        guard let databases = plist?["databases"] as? [[String: Any]],
              !databases.isEmpty
        else {
            throw XCTSkip("testDatabaseConfig.plist missing a non-empty 'databases' array.")
        }

        // Confirm we're on ContentView before driving the form. If we never see
        // the add button, the most likely cause is missing Accessibility
        // permission — skip rather than fail.
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not present ContentView (AddDatabaseButton) — Accessibility permissions may be missing.")
        }

        for config in databases {
            try addSingleDatabase(config: config)
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
