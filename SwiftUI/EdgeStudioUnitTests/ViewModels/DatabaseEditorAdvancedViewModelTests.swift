import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers the Advanced Configuration logic in `DatabaseEditorView.ViewModel`, which
/// previously had no tests at all — Save gating, row identity, what actually gets
/// persisted, and the reset affordance.
@MainActor
@Suite("DatabaseEditorView.ViewModel — advanced configuration")
struct DatabaseEditorAdvancedViewModelTests {
    private func makeViewModel(
        scopes: [CollectionSyncScope] = [],
        settings: [StartupSetting] = [],
        databaseId: String = "db-1"
    ) -> DatabaseEditorView.ViewModel {
        let config = DittoConfigForDatabase(
            UUID().uuidString,
            name: "Test",
            databaseId: databaseId,
            developmentToken: "token",
            url: "https://example.ditto.live",
            httpApiUrl: "",
            httpApiKey: "",
            collectionSyncScopes: scopes,
            startupSettings: settings
        )
        return DatabaseEditorView.ViewModel(config)
    }

    // MARK: Row identity

    /// Two freshly added rows must be distinct. When identity was the collection name,
    /// both were `""` — a duplicate `ForEach` id, so they could not both render.
    @Test(.tags(.model, .fast))
    func `two added scope rows have distinct identities`() {
        // ARRANGE
        let viewModel = makeViewModel()

        // ACT
        viewModel.addSyncScope()
        viewModel.addSyncScope()

        // ASSERT
        #expect(viewModel.collectionSyncScopes.count == 2)
        #expect(viewModel.collectionSyncScopes[0].id != viewModel.collectionSyncScopes[1].id)
    }

    /// Removal must delete exactly one row. Keying removal on the collection name meant
    /// `removeAll` deleted every blank row — or both rows of a transient duplicate.
    @Test(.tags(.model, .fast))
    func `removing one of two blank scope rows leaves the other`() {
        // ARRANGE
        let viewModel = makeViewModel()
        viewModel.addSyncScope()
        viewModel.addSyncScope()
        let firstID = viewModel.collectionSyncScopes[0].id

        // ACT
        viewModel.removeSyncScope(id: firstID)

        // ASSERT
        #expect(viewModel.collectionSyncScopes.count == 1)
        #expect(viewModel.collectionSyncScopes[0].id != firstID)
    }

    @Test(.tags(.model, .fast))
    func `removing a duplicate named scope keeps the original`() {
        // ARRANGE — validation blocks Save on duplicates, but both rows still exist.
        let viewModel = makeViewModel(scopes: [
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
            CollectionSyncScope(collection: "orders", scope: .allPeers)
        ])

        // ACT — remove the second.
        viewModel.removeSyncScope(id: viewModel.collectionSyncScopes[1].id)

        // ASSERT
        #expect(viewModel.collectionSyncScopes.count == 1)
        #expect(viewModel.collectionSyncScopes[0].scope == .localPeerOnly)
    }

    @Test(.tags(.model, .fast))
    func `removing a startup setting whose name differs only in case keeps the other`() {
        // ARRANGE — both lowercase to the same DQL key.
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "Foo", type: .string, value: "a"),
            StartupSetting(parameter: "foo", type: .string, value: "b")
        ])

        // ACT
        viewModel.removeStartupSetting(id: viewModel.startupSettings[1].id)

        // ASSERT
        #expect(viewModel.startupSettings.count == 1)
        #expect(viewModel.startupSettings[0].value == "a")
    }

    // MARK: Save gating

    @Test(.tags(.model, .fast))
    func `Save is blocked while a scope row is blank`() {
        let viewModel = makeViewModel()
        viewModel.addSyncScope()
        #expect(viewModel.hasAdvancedValidationErrors)
    }

    @Test(.tags(.model, .fast))
    func `Save is blocked while a value does not parse`() {
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "example_parameter", type: .integer, value: "not-an-int")
        ])
        #expect(viewModel.hasAdvancedValidationErrors)
    }

    @Test(.tags(.model, .fast))
    func `Save is blocked while a sensitive parameter is unacknowledged`() {
        // ARRANGE — opens a listening socket on every interface.
        let viewModel = makeViewModel(settings: [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "0.0.0.0:9000"
            )
        ])

        // ASSERT — asserted through `hasAdvancedValidationErrors`, which is what the Save
        // button reads (`DatabaseEditorView.swift:138`). The predicate these lines used to
        // call, `needsSensitiveAcknowledgement(id:)`, had no production caller at all: the
        // enforcement runs Save → `hasAdvancedValidationErrors` → `startupSettingError` →
        // `validateSetting`'s `.needsAcknowledgement`, and the apply path re-checks
        // independently via `partitionSettings`. Testing the orphan proved nothing about
        // the control.
        #expect(viewModel.hasAdvancedValidationErrors)
        let id = viewModel.startupSettings[0].id
        #expect(viewModel.startupSettingError(id: id) == .needsAcknowledgement)

        // ACT — acknowledge it.
        viewModel.setAcknowledged(true, id: id)

        // ASSERT — allowed, and the row is still recognized as sensitive so the toggle
        // stays visible and revocable.
        #expect(viewModel.hasAdvancedValidationErrors == false)
        #expect(viewModel.startupSettingError(id: id) == nil)
        #expect(viewModel.isSensitiveRow(id: id))
    }

    @Test(.tags(.model, .fast))
    func `Save is allowed once every advanced row is valid`() {
        let viewModel = makeViewModel(
            scopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
            settings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "42")]
        )
        #expect(viewModel.hasAdvancedValidationErrors == false)
    }

    @Test(.tags(.model, .fast))
    func `duplicate scope names are reported on both rows`() {
        let viewModel = makeViewModel(scopes: [
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
            CollectionSyncScope(collection: "orders", scope: .allPeers)
        ])
        #expect(viewModel.syncScopeError(id: viewModel.collectionSyncScopes[0].id) == .duplicate)
        #expect(viewModel.syncScopeError(id: viewModel.collectionSyncScopes[1].id) == .duplicate)
    }

    // MARK: Normalization / persistence

    @Test(.tags(.model, .fast))
    func `normalization trims names and drops blank rows`() {
        // ARRANGE
        let viewModel = makeViewModel(scopes: [
            CollectionSyncScope(collection: " orders ", scope: .localPeerOnly),
            CollectionSyncScope(collection: "   ", scope: .allPeers)
        ])

        // ACT
        let normalized = viewModel.normalizedSyncScopes()

        // ASSERT
        #expect(normalized == [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)])
    }

    /// A stored row with a trailing space used to make the form dirty the moment it
    /// opened, blocking clean cancel and iPad swipe-dismiss.
    @Test(.tags(.model, .fast))
    func `an untrimmed stored row does not make the form dirty on open`() {
        let viewModel = makeViewModel(scopes: [
            CollectionSyncScope(collection: "orders ", scope: .localPeerOnly)
        ])
        #expect(viewModel.hasUnsavedChanges == false)
    }

    @Test(.tags(.model, .fast))
    func `editing a scope marks the form dirty`() {
        let viewModel = makeViewModel(scopes: [
            CollectionSyncScope(collection: "orders", scope: .allPeers)
        ])
        viewModel.collectionSyncScopes[0].scope = .localPeerOnly
        #expect(viewModel.hasUnsavedChanges)
    }

    // MARK: Reset

    @Test(.tags(.model, .fast))
    func `reset clears both lists and can be undone`() {
        // ARRANGE
        let viewModel = makeViewModel(
            scopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)],
            settings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "42")]
        )

        // ACT
        viewModel.resetAdvancedToDefaults()

        // ASSERT
        #expect(viewModel.collectionSyncScopes.isEmpty)
        #expect(viewModel.startupSettings.isEmpty)
        #expect(viewModel.resetToDefaultsRequested)
        #expect(viewModel.hasUnsavedChanges)

        // ACT — undo. This used to be a one-way flag, leaving the form permanently
        // dirty with no way back.
        viewModel.undoResetToDefaults()

        // ASSERT
        #expect(viewModel.collectionSyncScopes.count == 1)
        #expect(viewModel.startupSettings.count == 1)
        #expect(viewModel.resetToDefaultsRequested == false)
        #expect(viewModel.hasUnsavedChanges == false)
    }

    // MARK: Summary

    /// The summary counts RAW rows: reporting "0 scopes" while a blank row is visible
    /// on screen reads as "my row didn't register".
    @Test(.tags(.model, .fast))
    func `the summary counts visible rows, including incomplete ones`() {
        let viewModel = makeViewModel()
        viewModel.addSyncScope()
        #expect(viewModel.advancedSummary == "1 scope · 0 startup settings")
    }

    // MARK: Acknowledgement lifecycle

    /// The acknowledgement approved a specific parameter — renaming the row must
    /// re-prompt, or a benign `foo_port` can be turned into `additional_p2p_trusted_ca_certs`
    /// while carrying the old consent.
    @Test(.tags(.model, .fast))
    func `renaming a row revokes its acknowledgement`() {
        // ARRANGE
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "some_port", type: .integer, value: "1", isAcknowledged: true)
        ])
        let id = viewModel.startupSettings[0].id

        // ACT
        viewModel.setParameter("additional_p2p_trusted_ca_certs", id: id)

        // ASSERT — and Save is blocked again, which is the part that matters.
        #expect(viewModel.startupSettings[0].isAcknowledged == false)
        #expect(viewModel.hasAdvancedValidationErrors)
    }

    /// Approving `127.0.0.1:9000` is not approval for `0.0.0.0:9000`, which listens on
    /// every interface.
    @Test(.tags(.model, .fast))
    func `editing a sensitive value revokes its acknowledgement`() {
        // ARRANGE
        let viewModel = makeViewModel(settings: [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "127.0.0.1:9000",
                isAcknowledged: true
            )
        ])
        let id = viewModel.startupSettings[0].id

        // ACT
        viewModel.setValue("0.0.0.0:9000", id: id)

        // ASSERT
        #expect(viewModel.startupSettings[0].isAcknowledged == false)
        #expect(viewModel.hasAdvancedValidationErrors)
    }

    @Test(.tags(.model, .fast))
    func `editing a benign value keeps its acknowledgement untouched`() {
        // ARRANGE
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "example_parameter", type: .integer, value: "1")
        ])
        let id = viewModel.startupSettings[0].id

        // ACT
        viewModel.setValue("2", id: id)

        // ASSERT
        #expect(viewModel.startupSettings[0].value == "2")
        #expect(viewModel.hasAdvancedValidationErrors == false)
    }

    // MARK: Type changes

    @Test(.tags(.model, .fast))
    func `changing type preserves the typed value`() {
        // ARRANGE — a long pasted blob must survive a stray picker tap; there is no undo.
        let blob = String(repeating: "x", count: 1500)
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "example_string_parameter", type: .string, value: blob)
        ])
        let id = viewModel.startupSettings[0].id

        // ACT
        viewModel.setType(.json, id: id)

        // ASSERT
        #expect(viewModel.startupSettings[0].value == blob)
        #expect(viewModel.startupSettings[0].type == .json)
    }

    /// The second assertion used to read `== "false"`, "an existing boolean is kept" — and
    /// it certified an unrenderable row: the value `Picker`'s tags are exactly
    /// `StartupSetting.booleanValues` (`AdvancedDatabaseSettings.swift:225`), so a
    /// lowercase `false` matches no tag and the control draws blank while `typedValue`
    /// still reports the row valid and Save stays enabled. The truth being kept is the
    /// *value*, not its spelling.
    @Test(.tags(.model, .fast))
    func `switching to Boolean seeds True and canonicalises an existing boolean`() {
        // ARRANGE
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "a_parameter", type: .string, value: "hello"),
            StartupSetting(parameter: "b_parameter", type: .string, value: "false")
        ])

        // ACT
        viewModel.setType(.boolean, id: viewModel.startupSettings[0].id)
        viewModel.setType(.boolean, id: viewModel.startupSettings[1].id)

        // ASSERT
        #expect(viewModel.startupSettings[0].value == "True")
        #expect(
            viewModel.startupSettings[1].value == "False",
            "an existing boolean keeps its value, spelled the way the picker tags it"
        )
        #expect(StartupSetting.booleanValues.contains(viewModel.startupSettings[1].value))
    }

    /// S1: the seeded `True` is a value change, so a sensitive row's acknowledgement must
    /// not survive it. Driven through `bindingForSettingType`'s mutator, which is the
    /// binding the type picker actually writes through.
    @Test(.tags(.model, .fast))
    func `seeding a Boolean value revokes a sensitive row's acknowledgement`() {
        // ARRANGE — acknowledged at a value the user actually approved.
        let viewModel = makeViewModel(settings: [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "127.0.0.1:9000",
                isAcknowledged: true
            )
        ])
        let id = viewModel.startupSettings[0].id

        // ACT — switching the type overwrites the approved value with `True`.
        viewModel.setType(.boolean, id: id)

        // ASSERT — approval does not carry over, and Save is blocked until it is re-given.
        #expect(viewModel.startupSettings[0].value == "True")
        #expect(viewModel.startupSettings[0].isAcknowledged == false)
        #expect(viewModel.hasAdvancedValidationErrors)
    }

    /// Re-spelling is not a value change: `true` and `True` are the same setting to
    /// `typedValue`, so canonicalising must not force a pointless re-tick.
    @Test(.tags(.model, .fast))
    func `canonicalising a boolean spelling keeps a sensitive row acknowledged`() {
        // ARRANGE
        let viewModel = makeViewModel(settings: [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "true",
                isAcknowledged: true
            )
        ])
        let id = viewModel.startupSettings[0].id

        // ACT
        viewModel.setType(.boolean, id: id)

        // ASSERT
        #expect(viewModel.startupSettings[0].value == "True")
        #expect(viewModel.startupSettings[0].isAcknowledged)
        #expect(viewModel.hasAdvancedValidationErrors == false)
    }

    /// Canonicalising on load must not look like an edit. Found by the Phase 8c readiness
    /// review: the `original` snapshot was built from the raw config while the live rows were
    /// canonicalised, so opening the editor on a stored `true` armed `hasUnsavedChanges`,
    /// `interactiveDismissDisabled` and a "Discard changes?" prompt with no user input at all.
    @Test(.tags(.model, .fast))
    func `canonicalising a stored boolean on load is not an unsaved change`() {
        // ARRANGE / ACT — construction is the load path (`DatabaseEditorView.swift:23`).
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "a_parameter", type: .boolean, value: "true"),
            StartupSetting(parameter: "b_parameter", type: .boolean, value: "FALSE")
        ])

        // ASSERT — the rows render, and the sheet opens clean.
        #expect(viewModel.startupSettings[0].value == "True")
        #expect(viewModel.startupSettings[1].value == "False")
        #expect(viewModel.hasUnsavedChanges == false, "canonicalising is not a user edit")
    }

    /// S2, the other ingress: a row already stored with a case-variant value — from an
    /// older build, or from a config edited outside this editor — must render. The editor
    /// canonicalises on load rather than waiting for the user to touch the type picker.
    @Test(.tags(.model, .fast))
    func `a stored boolean with a case-variant value is canonicalised on load`() {
        // ARRANGE / ACT
        let viewModel = makeViewModel(settings: [
            StartupSetting(parameter: "a_parameter", type: .boolean, value: "true"),
            StartupSetting(parameter: "b_parameter", type: .boolean, value: "FALSE"),
            StartupSetting(parameter: "c_parameter", type: .string, value: "true")
        ])

        // ASSERT — boolean rows are canonicalised; a String row that happens to spell a
        // boolean is left exactly as the user typed it.
        #expect(viewModel.startupSettings[0].value == "True")
        #expect(viewModel.startupSettings[1].value == "False")
        #expect(viewModel.startupSettings[2].value == "true")
    }

    // MARK: Corrupt sync scopes

    /// Save must not silently overwrite unreadable scopes with `[]` — that cleared the
    /// containment guard by following the error message's own advice.
    @Test(.tags(.model, .fast))
    func `Save is blocked while unreadable scopes are neither replaced nor discarded`() {
        // ARRANGE
        let config = DittoConfigForDatabase(
            UUID().uuidString,
            name: "Test",
            databaseId: "db-corrupt",
            developmentToken: "token",
            url: "https://example.ditto.live",
            httpApiUrl: "",
            httpApiKey: "",
            collectionSyncScopes: [],
            startupSettings: []
        )
        config.hasCorruptSyncScopes = true
        let viewModel = DatabaseEditorView.ViewModel(config)

        // ASSERT — blocked on open.
        #expect(viewModel.hasCorruptSyncScopes)
        #expect(viewModel.hasAdvancedValidationErrors)

        // ACT — re-entering a scope unblocks it.
        viewModel.collectionSyncScopes = [
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ]

        // ASSERT
        #expect(viewModel.hasAdvancedValidationErrors == false)
    }

    @Test(.tags(.model, .fast))
    func `explicitly discarding unreadable scopes unblocks Save`() {
        // ARRANGE
        let config = DittoConfigForDatabase(
            UUID().uuidString,
            name: "Test",
            databaseId: "db-corrupt",
            developmentToken: "token",
            url: "https://example.ditto.live",
            httpApiUrl: "",
            httpApiKey: "",
            collectionSyncScopes: [],
            startupSettings: []
        )
        config.hasCorruptSyncScopes = true
        let viewModel = DatabaseEditorView.ViewModel(config)

        // ACT
        viewModel.discardCorruptSyncScopes = true

        // ASSERT
        #expect(viewModel.hasAdvancedValidationErrors == false)
    }

    // MARK: Reset undo safety

    /// Undo restores a snapshot, so it must not be offered once the user has started
    /// re-entering rows — it would silently discard that work.
    @Test(.tags(.model, .fast))
    func `Undo Reset is withdrawn once new rows are entered`() {
        // ARRANGE
        let viewModel = makeViewModel(
            scopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)]
        )
        viewModel.resetAdvancedToDefaults()
        #expect(viewModel.canUndoResetToDefaults)

        // ACT — the user starts over.
        viewModel.addSyncScope()

        // ASSERT
        #expect(viewModel.canUndoResetToDefaults == false)
        viewModel.undoResetToDefaults()
        #expect(viewModel.collectionSyncScopes.count == 1, "the new row is not clobbered")
        #expect(viewModel.collectionSyncScopes[0].collection.isEmpty)
    }

    // MARK: Summary

    @Test(.tags(.model, .fast))
    func `the summary pluralizes both counts`() {
        let empty = makeViewModel()
        #expect(empty.advancedSummary == "0 scopes · 0 startup settings")

        let one = makeViewModel(
            scopes: [CollectionSyncScope(collection: "a", scope: .allPeers)],
            settings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "1")]
        )
        #expect(one.advancedSummary == "1 scope · 1 startup setting")
    }

    /// Clicking Reset a second time (which the UI allows once a row is re-entered) must
    /// not replace the original snapshot with that single new row.
    @Test(.tags(.model, .fast))
    func `a second reset does not overwrite the undo snapshot`() {
        // ARRANGE
        let viewModel = makeViewModel(
            scopes: [
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
                CollectionSyncScope(collection: "audit", scope: .smallPeersOnly)
            ]
        )

        // ACT — reset, start re-entering, then reset again.
        viewModel.resetAdvancedToDefaults()
        viewModel.addSyncScope()
        viewModel.collectionSyncScopes[0].collection = "temp"
        viewModel.resetAdvancedToDefaults()

        // ASSERT — undo restores the ORIGINAL two rows, not the discarded temp row.
        #expect(viewModel.canUndoResetToDefaults)
        viewModel.undoResetToDefaults()
        #expect(viewModel.collectionSyncScopes.count == 2)
        #expect(viewModel.collectionSyncScopes.map(\.collection).sorted() == ["audit", "orders"])
    }
}
