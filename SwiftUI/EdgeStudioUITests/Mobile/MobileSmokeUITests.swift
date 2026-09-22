#if os(iOS)
import XCTest

@MainActor
final class MobileSmokeUITests: MobileUITestCase {
    func testFreshLaunchHasNoDatabases() {
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'AppCard_'"))
        XCTAssertEqual(cards.count, 0, "Smoke must not load bundled developer credentials or previous tests")
        XCTAssertTrue(app.buttons["AddDatabaseButton"].isHittable)
    }

    func testRegisterValidationAndCancel() throws {
        // ARRANGE / ACT: use the production registration form and software keyboard.
        try openDatabaseEditor()
        let save = try require(app.buttons["SaveButton"])
        XCTAssertFalse(save.isEnabled)
        try tap(app.textFields["NameTextField"])
        app.textFields["NameTextField"].typeText("Mobile draft")

        // ASSERT: a name alone cannot save, and cancel returns to an empty list.
        XCTAssertFalse(save.isEnabled)
        try tap(app.buttons["CancelButton"])
        try keepEditingRegistration()
        XCTAssertTrue(waitForValue(app.textFields["NameTextField"], "Mobile draft"))
        try tap(app.buttons["CancelButton"])
        try discardRegistrationChanges()
        XCTAssertTrue(app.textFields["NameTextField"].waitForNonExistence(timeout: 5))
        try require(app.staticTexts["EmptyDatabaseList"])
        XCTAssertFalse(app.buttons["CloseButton"].exists)
    }

    func testRegistrationDraftSurvivesRotation() throws {
        try openDatabaseEditor()
        let field = app.textFields["NameTextField"]
        try tap(field)
        field.typeText("Rotation draft")
        attachGeometry("01-registration-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForValue(field, "Rotation draft"))
        XCTAssertTrue(app.buttons["CancelButton"].isHittable)
        attachGeometry("02-registration-landscape")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForValue(field, "Rotation draft"))
        try tap(app.buttons["CancelButton"])
        try discardRegistrationChanges()
        try require(app.staticTexts["EmptyDatabaseList"])
    }

    func testRegisterAndEditDatabaseWithTouch() throws {
        try openDatabaseEditor()
        try tap(app.textFields["NameTextField"])
        app.textFields["NameTextField"].typeText("Touch Database")
        try tap(app.textFields["DatabaseIdTextField"])
        app.textFields["DatabaseIdTextField"].typeText(UUID().uuidString)
        try revealFormField(app.textFields["TokenTextField"])
        try tap(app.textFields["TokenTextField"])
        // This test saves configuration only; it never opens Ditto or connects.
        app.textFields["TokenTextField"].typeText("synthetic-ui-test-token")
        try revealFormField(app.buttons["SaveButton"], towardBeginning: true)
        try tap(app.buttons["SaveButton"])
        let card = app.descendants(matching: .any)["AppCard_Touch Database"].firstMatch
        try require(card)
        card.press(forDuration: 1.2)
        try tap(app.buttons["EditDatabaseMenuItem"])
        let databaseID = try require(app.textFields["DatabaseIdTextField"])
        XCTAssertFalse(databaseID.isEnabled, "Editing a configuration must not change its storage identity")
        try replaceText(in: app.textFields["NameTextField"], with: "Renamed Database")
        try tap(app.buttons["SaveButton"])
        try require(app.descendants(matching: .any)["AppCard_Renamed Database"].firstMatch)
        XCTAssertFalse(card.exists)
    }
}
#endif
