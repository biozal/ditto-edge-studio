//
//  DatabaseIdImmutabilityUITests.swift
//  EdgeStudioUITests
//
//  Shipping-path guard for C1: the Database ID must be editable when REGISTERING a
//  database and read-only when EDITING one.
//
//  Why this exists at the UI layer rather than only in the view model:
//  `updateDatabaseConfig` no longer writes the `databaseId` column (it is a parent
//  foreign key with no `ON UPDATE`, referenced by four child tables, and it names the
//  on-disk Ditto store directory). If the field were still editable, the user's edit
//  would be silently discarded — which is worse than the loud `FOREIGN KEY constraint
//  failed` it replaced. The only mechanical proof that the field is actually disabled in
//  the shipping UI is to look at the shipping UI.
//
//  CREDENTIAL-FREE BY CONSTRUCTION. Registering a database is a pure local store write
//  (`DatabaseEditorView.save` → `addDittoAppConfig`); nothing calls `Ditto.open`. So this
//  test never touches `openStudio()` / `addDatabasesFromPlist()`, which `XCTSkip` when
//  `testDatabaseConfig.plist` is absent — a skipped test that reports green would prove
//  nothing. It follows the same pattern as `AdvancedConfigurationUITests`, which is the
//  one existing UI test that runs without credentials.
//
//  SELF-CLEANING. The dummy config is written to the persisted UI-test sandbox
//  (`ditto_edge_studio_test`). Left behind, it makes `addDatabasesFromPlist()` stop
//  skipping in every OTHER UI-test class — those would then tap the card, fail to open a
//  database with a bogus URL, and go red. So the config is deleted in `tearDown` (which
//  runs even when the test body fails), the id is unique per run so a hard crash cannot
//  poison the next run via the `UNIQUE` index, and the final assertion is that no card
//  remains.
//
//  Manual recovery if a run is killed mid-test:
//    rm -rf "~/Library/Application Support/ditto_edge_studio_test"
//

import XCTest

final class DatabaseIdImmutabilityUITests: UITestBase {
    /// Unique per run so a crashed run cannot collide with the next one on the
    /// `databaseId` UNIQUE index.
    private let dummyName = "UITest-ID-Lock-\(UUID().uuidString.prefix(8))"
    private lazy var dummyDatabaseId = "uitest-\(UUID().uuidString.lowercased())"

    override func tearDown() async throws {
        // Best-effort cleanup BEFORE super tears the app down. Runs on the failure path
        // too, which is the point — a leftover config breaks six other test classes.
        deleteDummyDatabaseIfPresent()
        try await super.tearDown()
    }

    func testDatabaseIdIsEditableWhenRegisteringAndLockedWhenEditing() throws {
        guard waitForAppToFinishLoading(timeout: 20) else {
            throw XCTSkip("App did not present ContentView — Accessibility permissions may be missing.")
        }

        let addButton = app.buttons["AddDatabaseButton"].firstMatch
        guard addButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("AddDatabaseButton not found — cannot open the editor sheet.")
        }

        // ── ARRANGE / ACT 1: the REGISTER case ────────────────────────────────────
        addButton.tap()
        sleep(2) // sheet animation

        let idField = app.textFields["DatabaseIdTextField"].firstMatch
        guard idField.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "FAIL-no-editor-form", lifetime: .keepAlways)
            throw XCTSkip("Editor sheet did not appear.")
        }

        // ASSERT 1 — editable while registering. Hard assertion: if this were false the
        // feature would be broken in the opposite direction (nobody could register).
        XCTAssertTrue(
            idField.isEnabled,
            "Database ID must be editable when registering a new database."
        )
        XCTAssertFalse(
            app.staticTexts["DatabaseIdLockedCaption"].firstMatch.exists,
            "The locked caption must not appear on the Register sheet."
        )

        // Fill the three fields the harness has verified identifiers for.
        app.textFields["NameTextField"].firstMatch.tap()
        app.textFields["NameTextField"].firstMatch.typeText(dummyName)
        idField.tap()
        idField.typeText(dummyDatabaseId)
        app.textFields["TokenTextField"].firstMatch.tap()
        app.textFields["TokenTextField"].firstMatch.typeText("uitest-token")

        let saveButton = app.buttons["SaveButton"].firstMatch
        XCTAssertTrue(saveButton.isEnabled, "Save must enable once name, id and token are filled.")
        saveButton.tap()
        reactivateAfterTransition()

        // The card must appear, otherwise there is nothing to edit and the rest of the
        // test would vacuously pass.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "AppCard_\(dummyName)"))
            .firstMatch
        guard card.waitForExistence(timeout: 10) else {
            captureScreenshot(named: "FAIL-card-not-created", lifetime: .keepAlways)
            XCTFail("Registered database did not appear in the list — cannot test the edit case.")
            return
        }

        // ── ACT 2: reopen the SAME config for EDITING ─────────────────────────────
        // The card's tap gesture OPENS the database, so the editor is reached through the
        // context menu. `EditDatabaseMenuItem` was added for exactly this.
        card.rightClick()
        let editItem = app.menuItems["EditDatabaseMenuItem"].firstMatch
        let editButton = app.buttons["EditDatabaseMenuItem"].firstMatch
        if editItem.waitForExistence(timeout: 5) {
            editItem.tap()
        } else if editButton.waitForExistence(timeout: 2) {
            editButton.tap()
        } else {
            captureScreenshot(named: "FAIL-no-edit-menu-item", lifetime: .keepAlways)
            logAccessibilityDiagnostics(reason: "EditDatabaseMenuItem not addressable")
            XCTFail("Could not reach the Edit affordance — the context menu item was not found.")
            return
        }
        sleep(2) // sheet animation

        // ── ASSERT 2: the EDIT case ───────────────────────────────────────────────
        let editIdField = app.textFields["DatabaseIdTextField"].firstMatch
        XCTAssertTrue(editIdField.waitForExistence(timeout: 10), "Edit sheet did not appear.")
        captureScreenshot(named: "01-edit-sheet-id-locked", lifetime: .keepAlways)

        XCTAssertFalse(
            editIdField.isEnabled,
            "Database ID must be READ-ONLY when editing an existing database — an edit "
                + "would otherwise be silently discarded by updateDatabaseConfig."
        )
        XCTAssertTrue(
            app.staticTexts["DatabaseIdLockedCaption"].firstMatch.exists,
            "The user must be told why the Database ID cannot be changed."
        )

        // Leave the sheet without saving.
        let cancelButton = app.buttons["CancelButton"].firstMatch
        if cancelButton.isHittable {
            cancelButton.tap()
            sleep(1)
            let discard = app.buttons["Discard Changes"].firstMatch
            if discard.waitForExistence(timeout: 2) {
                discard.tap()
            }
        }
        reactivateAfterTransition()

        // ── CLEANUP, asserted rather than hoped ───────────────────────────────────
        deleteDummyDatabaseIfPresent()
        let survivor = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "AppCard_\(dummyName)"))
            .firstMatch
        XCTAssertTrue(
            waitForDisappearance(survivor, timeout: 10),
            "The dummy database must be removed — a leftover config makes six other "
                + "UI-test classes fail instead of skipping."
        )
    }

    // MARK: - Helpers

    /// Deletes the dummy config through the context menu, if its card is on screen.
    /// Deliberately assertion-free: this runs from `tearDown` on failure paths too, where
    /// the app may already be gone.
    private func deleteDummyDatabaseIfPresent() {
        guard app?.state == .runningForeground else { return }

        // Dismiss a sheet if one is still open, or the card underneath is unreachable.
        let cancelButton = app.buttons["CancelButton"].firstMatch
        if cancelButton.exists, cancelButton.isHittable {
            cancelButton.tap()
            let discard = app.buttons["Discard Changes"].firstMatch
            if discard.waitForExistence(timeout: 2) {
                discard.tap()
            }
        }

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "AppCard_\(dummyName)"))
            .firstMatch
        guard card.waitForExistence(timeout: 3) else { return }

        card.rightClick()
        let deleteItem = app.menuItems["DeleteDatabaseMenuItem"].firstMatch
        let deleteButton = app.buttons["DeleteDatabaseMenuItem"].firstMatch
        if deleteItem.waitForExistence(timeout: 3) {
            deleteItem.tap()
        } else if deleteButton.waitForExistence(timeout: 2) {
            deleteButton.tap()
        }
        // A confirmation dialog is not currently presented for delete; dismiss one if a
        // future change adds it, so cleanup keeps working.
        let confirm = app.buttons["Delete"].firstMatch
        if confirm.waitForExistence(timeout: 2), confirm.isHittable {
            confirm.tap()
        }
        sleep(1)
    }
}
