#if os(iOS)
import UIKit
import XCTest

@MainActor
class MobileUITestCase: UITestCase {
    enum HarnessError: Error {
        case missingPrerequisite, missingElement
    }

    var fixture: String {
        "empty"
    }

    private var originalOrientation = UIDeviceOrientation.portrait
    private var originalAppearance = XCUIDevice.Appearance.unspecified

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
        originalAppearance = XCUIDevice.shared.appearance
        originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait

        var environment = [
            "UI_TEST_NAMESPACE": UUID().uuidString,
            "UI_TEST_FIXTURE": fixture,
            "UNIT_TESTING": "0"
        ]
        if fixture == "workspace" {
            guard let payload = ProcessInfo.processInfo.environment["EDGE_UI_TEST_FIXTURE_BASE64"], !payload.isEmpty else {
                XCTFail("Workspace tests require an offline fixture. Run run_ui_tests.sh with --fixture; use Mobile Smoke for credential-free tests.")
                throw HarnessError.missingPrerequisite
            }
            environment["UI_TEST_FIXTURE_BASE64"] = payload
        }
        app = makeApplication(environment: environment)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if ProcessInfo.processInfo.environment["EDGE_UI_TEST_DARK_LARGE_TEXT"] == "1" {
            XCUIDevice.shared.appearance = .dark
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        }
        app.launch()
        try require(app.buttons["AddDatabaseButton"], timeout: 30)
        if fixture == "empty" {
            try require(app.staticTexts["EmptyDatabaseList"], timeout: 30)
        } else {
            try require(app.descendants(matching: .any)["AppCard_Mobile UI Test Database"].firstMatch, timeout: 30)
        }
    }

    override func tearDown() async throws {
        if let app, app.state == .runningForeground || app.state == .runningBackground {
            if (testRun?.totalFailureCount ?? 0) > 0 {
                // Avoid credential-bearing editor fields in persistent diagnostics.
                if fixture == "empty" || !app.textFields["TokenTextField"].exists {
                    logAccessibilityDiagnostics(reason: name)
                }
            }
            app.terminate()
        }
        app = nil
        XCUIDevice.shared.appearance = originalAppearance
        XCUIDevice.shared.orientation = originalOrientation == .unknown ? .portrait : originalOrientation
        try await super.tearDown()
    }

    @discardableResult
    func require(_ element: XCUIElement, timeout: TimeInterval = 10) throws -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Required UI element did not appear")
            throw HarnessError.missingElement
        }
        return element
    }

    func tap(_ element: XCUIElement) throws {
        try require(element)
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 5), "Control must be reachable")
        element.tap()
    }

    func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func openDatabaseEditor() throws {
        try tap(app.buttons["AddDatabaseButton"])
        try require(app.textFields["NameTextField"])
    }

    func openWorkspace() throws {
        let card = app.descendants(matching: .any)["AppCard_Mobile UI Test Database"].firstMatch
        try tap(card)
        try require(app.buttons["CloseButton"], timeout: 60)
    }

    func navigate(to destination: String) throws {
        let item = app.buttons["NavItem_\(destination)"]
        if !item.exists || !item.isHittable {
            try tap(app.buttons["SidebarToggleButton"])
        }
        try tap(item)
        let dismiss = app.buttons["SidebarDismissButton"]
        if !dismiss.waitForNonExistence(timeout: 2), dismiss.isHittable {
            try tap(dismiss)
            XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        }
    }

    /// Touch selection exercises the software-keyboard path, including replacement.
    func replaceText(in field: XCUIElement, with text: String) throws {
        try tap(field)
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.press(forDuration: 1.2)
            let selectAll = app.buttons["Select All"]
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            } else {
                // A second tap reveals the edit menu when the first press selected a word.
                let menuItem = app.menuItems["Select All"]
                try tap(menuItem)
            }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(text)
        XCTAssertTrue(waitForValue(field, text), "Typed text must reach the real editor")
    }

    func runQuery(_ query: String) throws {
        let editor = app.textViews["QueryEditorTextView"]
        try replaceText(in: editor, with: query)
        try tap(app.buttons["ExecuteQueryButton"])
        try require(app.descendants(matching: .any)["QueryResultsView"].firstMatch)
    }

    /// Native toolbars may move actions into the system overflow menu.
    func tapToolbar(_ identifier: String) throws {
        let action = app.buttons[identifier]
        if action.exists, action.isHittable {
            try tap(action)
            return
        }
        let hideKeyboard = app.keyboards.buttons["Hide keyboard"]
        if hideKeyboard.exists, hideKeyboard.isHittable {
            hideKeyboard.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            if action.exists, action.isHittable {
                try tap(action)
                return
            }
        }
        try tap(app.buttons["BottomOverflowBarButtonItem"])
        if action.exists, action.isHittable {
            try tap(action)
            return
        }
        // UIKit's native overflow reconstructs actions without SwiftUI IDs.
        // Plans pin English; scope the fallback to the actual overflow list.
        let labels = ["CloseButton": "Close", "Toggle Inspector": "Inspector",
                      "PresenceViewerControlsMenu": "Viewer Controls", "LogActionsToolbarMenu": "Log Actions",
                      "Next Page": "Next Page", "Previous Page": "Previous Page"]
        guard let label = labels[identifier] else { throw HarnessError.missingElement }
        let item = app.collectionViews.buttons.matching(NSPredicate(format: "label == %@", label)).element
        try tap(item)
    }

    func discardRegistrationChanges() throws {
        let matches = app.buttons.matching(identifier: "DiscardDatabaseChangesButton")
        try require(matches.firstMatch)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let visible = matches.allElementsBoundByIndex.filter(\.isHittable)
        guard let button = visible.last else { throw HarnessError.missingElement }
        // UIKit may expose nested buttons for the same native popover action.
        XCTAssertTrue(visible.allSatisfy { $0.frame == button.frame })
        button.tap()
    }

    func keepEditingRegistration() throws {
        let cancel = app.buttons["KeepEditingDatabaseButton"]
        if cancel.exists, cancel.isHittable {
            cancel.tap()
        } else {
            // Regular-width native confirmation popovers omit their cancel action.
            let regions = app.otherElements.matching(identifier: "PopoverDismissRegion").allElementsBoundByIndex
            guard let region = regions.last(where: \.isHittable) else {
                XCTFail("Native confirmation popover must expose an outside dismiss region")
                throw HarnessError.missingElement
            }
            region.tap()
        }
        XCTAssertTrue(app.buttons["DiscardDatabaseChangesButton"].firstMatch.waitForNonExistence(timeout: 5))
    }

    func revealFormField(_ field: XCUIElement, towardBeginning: Bool = false) throws {
        if !towardBeginning { try require(field) }
        for attempt in 0 ... 5 {
            let form = app.collectionViews.containing(.textField, identifier: "NameTextField").element
            let window = app.windows.firstMatch
            var visible = form.frame.intersection(window.frame)
            var unobstructedWindow = window.frame
            let obstructions = app.keyboards.allElementsBoundByIndex
                + app.otherElements.matching(identifier: "SystemInputAssistantView").allElementsBoundByIndex
                + app.otherElements.matching(identifier: "inputView").allElementsBoundByIndex
            for obstruction in obstructions where obstruction.frame.intersects(visible) {
                visible.size.height = max(0, min(visible.maxY, obstruction.frame.minY) - visible.minY)
                unobstructedWindow.size.height = max(0, obstruction.frame.minY - unobstructedWindow.minY)
            }
            if field.exists {
                // AX can briefly report hittable while the keyboard accessory covers a field.
                let available = field.elementType == .button ? unobstructedWindow : visible
                if available.contains(field.frame), field.isHittable { return }
            }
            if attempt == 5 { break }
            XCTAssertGreaterThan(visible.height, 100, "Form must have a visible scrolling area")
            let origin = window.coordinate(withNormalizedOffset: .zero)
            // Drag in the form's leading padding so text fields don't open an edit menu.
            let dragX = visible.minX + visible.width * 0.02 - window.frame.minX
            let start = origin.withOffset(CGVector(dx: dragX,
                                                   dy: visible.minY + visible.height * 0.85 - window.frame.minY))
            let end = origin.withOffset(CGVector(dx: dragX,
                                                 dy: visible.minY + visible.height * 0.3 - window.frame.minY))
            if towardBeginning {
                end.press(forDuration: 0.1, thenDragTo: start)
            } else {
                start.press(forDuration: 0.1, thenDragTo: end)
            }
        }
        XCTFail("Form control must be visible above the keyboard and reachable after scrolling")
        throw HarnessError.missingElement
    }

    func dismissInspector() throws {
        let grabber = app.buttons["Sheet Grabber"]
        if grabber.exists, grabber.isHittable {
            let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: end)
        } else {
            try tapToolbar("Toggle Inspector")
        }
        XCTAssertTrue(app.descendants(matching: .any)["QueryInspectorView"].firstMatch.waitForNonExistence(timeout: 5))
    }

    func attachGeometry(_ name: String) {
        captureScreenshot(named: name, lifetime: .keepAlways)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
#endif
