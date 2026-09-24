#if os(iOS)
import XCTest

@MainActor
final class MobileAccessibilityUITests: MobileUITestCase {
    func testDatabaseListAccessibility() throws {
        captureScreenshot(named: "database-list-before-accessibility-audit", lifetime: .keepAlways)
        try app.performAccessibilityAudit()
    }

    func testRegistrationAccessibility() throws {
        try openDatabaseEditor()
        XCTAssertFalse(app.buttons["SaveButton"].isEnabled)
        captureScreenshot(named: "registration-before-accessibility-audit", lifetime: .keepAlways)
        try app.performAccessibilityAudit { issue in
            // WCAG 1.4.3 exempts inactive controls. Keep this limited to the
            // verified native disabled Save button; all other issues still fail.
            guard issue.auditType == .contrast,
                  let element = issue.element,
                  element.identifier == "SaveButton",
                  !element.isEnabled else { return false }
            return true
        }
    }

    func testEnabledSaveAccessibility() throws {
        try openDatabaseEditor()
        for (identifier, text) in [
            ("NameTextField", "Accessibility test"),
            ("DatabaseIdTextField", UUID().uuidString),
            ("TokenTextField", "synthetic-ui-test-token")
        ] {
            let field = app.textFields[identifier]
            try revealFormField(field)
            try tap(field)
            field.typeText(text)
        }
        let save = app.buttons["SaveButton"]
        try revealFormField(save, towardBeginning: true)
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        captureScreenshot(named: "enabled-save-before-accessibility-audit", lifetime: .keepAlways)
        // Nothing is saved or opened; an enabled Save gets the full audit.
        try app.performAccessibilityAudit()
    }

    /// The accessibility plan runs this at both default and AXXXL text sizes.
    func testAuthenticationModesRemainReachable() throws {
        try openDatabaseEditor()
        attachGeometry("authentication-mode-controls")

        for (mode, placeholder) in [
            ("Small Peer Only", "Offline Token"),
            ("Development", "Development token")
        ] {
            let option = app.buttons[mode].firstMatch
            try revealFormField(option, towardBeginning: true)
            try tap(option)
            XCTAssertTrue(option.isSelected, "The tapped authentication mode must be selected")

            let token = app.textFields["TokenTextField"]
            try revealFormField(token)
            XCTAssertEqual(
                token.placeholderValue,
                placeholder,
                "Selecting a mode must update the actual registration form"
            )
        }
    }
}
#endif
