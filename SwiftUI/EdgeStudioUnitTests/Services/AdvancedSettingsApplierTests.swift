import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Records every statement it is asked to run, so the apply order and the failure
/// policies can be asserted without a live Ditto instance or credentials.
/// A lock-guarded class rather than an actor: `DQLExecuting` passes
/// `[String: Any?]`, which isn't `Sendable`, so an actor implementation can't accept
/// it across isolation. The real conformance (`Ditto`) is nonisolated for the same
/// reason.
private final class RecordingExecutor: DQLExecuting, @unchecked Sendable {
    struct Call {
        let query: String
        let arguments: [String: Any?]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    /// Queries whose prefix should throw, simulating an SDK rejection.
    private let failingPrefixes: [String]
    /// Result rows returned for a `SHOW` query.
    private let showRows: [[String: Any?]]

    init(failingPrefixes: [String] = [], showRows: [[String: Any?]] = []) {
        self.failingPrefixes = failingPrefixes
        self.showRows = showRows
    }

    struct SimulatedFailure: LocalizedError {
        var errorDescription: String? {
            "simulated SDK rejection"
        }
    }

    func runDQL(_ query: String, arguments: [String: Any?]) async throws -> [[String: Any?]] {
        // `withLock` rather than lock()/unlock(): the latter is unavailable from an
        // async context.
        lock.withLock { _calls.append(Call(query: query, arguments: arguments)) }

        if failingPrefixes.contains(where: { query.hasPrefix($0) }) {
            throw SimulatedFailure()
        }
        return query.hasPrefix("SHOW") ? showRows : []
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    var queries: [String] {
        calls.map(\.query)
    }
}

/// Records non-DQL side effects (transport config, readback, sync start) in order.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.withLock { events.append(event) }
    }

    var recorded: [String] {
        lock.withLock { events }
    }
}

/// A scope map read-back row shaped the way `SHOW <parameter>` returns values.
private func showRow(_ map: [String: String]) -> [[String: Any?]] {
    [[AdvancedSettingsDQL.syncScopesReadParameter: map]]
}

@Suite("AdvancedSettingsApplier — startup settings")
struct AdvancedSettingsApplierStartupTests {
    @Test(.tags(.service, .fast))
    func `each valid setting is applied with its value bound as an argument`() async {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(parameter: "example_parameter", type: .integer, value: "42"),
            StartupSetting(parameter: "example_bool_parameter", type: .boolean, value: "True")
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings == ["example_parameter", "example_bool_parameter"])
        #expect(result.skippedSettings.isEmpty)
        let calls = executor.calls
        #expect(calls.count == 2)
        #expect(calls[0].query == "ALTER SYSTEM SET example_parameter = :value")
        #expect(calls[0].arguments["value"] as? Int == 42)
        #expect(calls[1].arguments["value"] as? Bool == true)
    }

    /// Best-effort by design: a typo in one parameter must not lock the user out of
    /// their database. The failure has to be reported, not just logged.
    @Test(.tags(.service, .fast))
    func `a rejected setting is skipped and reported while the rest apply`() async {
        // ARRANGE
        let executor = RecordingExecutor(failingPrefixes: ["ALTER SYSTEM SET bogus_parameter"])
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(parameter: "bogus_parameter", type: .integer, value: "1"),
            StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings == ["example_parameter"])
        #expect(result.skippedSettings.count == 1)
        #expect(result.skippedSettings.first?.name == "bogus_parameter")
        #expect(result.hasFailures)
    }

    /// Validation is re-run in the apply path because configs can arrive without
    /// passing through the editor (seeded plists, imports).
    @Test(.tags(.service, .fast))
    func `invalid and reserved settings never reach the SDK`() async {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(parameter: "ok; DROP", type: .string, value: "x"),
            StartupSetting(parameter: "dql_strict_mode", type: .boolean, value: "True"),
            StartupSetting(parameter: "example_parameter", type: .integer, value: "not-an-int")
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings.isEmpty)
        #expect(result.skippedSettings.count == 3)
        let queries = executor.queries
        #expect(queries.isEmpty, "no statement should have been executed")
    }

    /// The persisted acknowledgement must gate the APPLY path, not just the editor —
    /// settings arrive from seeded plists and hand-edited databases too.
    @Test(.tags(.service, .fast))
    func `an unacknowledged sensitive parameter is never executed`() async {
        // ARRANGE — opens a listening socket on every interface.
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "0.0.0.0:9000",
                isAcknowledged: false
            )
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings.isEmpty)
        #expect(result.skippedSettings.count == 1)
        #expect(executor.queries.isEmpty, "no DQL may be issued for an unacknowledged risky parameter")
    }

    @Test(.tags(.service, .fast))
    func `an acknowledged sensitive parameter is applied`() async {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(
                parameter: "metrics_exporter_prometheus_http_listener_addr",
                type: .string,
                value: "127.0.0.1:9000",
                isAcknowledged: true
            )
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings.count == 1)
        #expect(executor.queries.count == 1)
    }

    /// Duplicates must be rejected on the apply path, where `validateSetting(others: [])`
    /// alone cannot see them.
    @Test(.tags(.service, .fast))
    func `duplicate parameters are rejected rather than last-wins`() async {
        // ARRANGE — same DQL key, different case.
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = [
            StartupSetting(parameter: "example_parameter", type: .integer, value: "1"),
            StartupSetting(parameter: "Example_Parameter", type: .integer, value: "2")
        ]

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings == ["example_parameter"])
        #expect(result.skippedSettings.count == 1)
        #expect(executor.queries.count == 1)
    }

    /// The row cap has to hold on the apply path too, or a hand-edited config issues
    /// thousands of statements on every open.
    @Test(.tags(.service, .fast))
    func `the row cap is enforced when applying`() async {
        // ARRANGE — one more than the cap.
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let settings = (0 ... AdvancedSettingsValidator.maxRowCount).map {
            StartupSetting(parameter: "example_parameter_\($0)", type: .integer, value: "1")
        }

        // ACT
        let result = await applier.applyStartupSettings(settings)

        // ASSERT
        #expect(result.appliedSettings.count == AdvancedSettingsValidator.maxRowCount)
        #expect(result.skippedSettings.count == 1)
        #expect(executor.queries.count == AdvancedSettingsValidator.maxRowCount)
    }
}

@Suite("AdvancedSettingsApplier — sync scopes are fail-closed")
struct AdvancedSettingsApplierScopeTests {
    @Test(.tags(.service, .fast))
    func `scopes are applied and then verified with a read back`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: showRow(["orders": "LocalPeerOnly"]))
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT
        #expect(outcome.applied == 1)
        #expect(outcome.verified)
        let queries = executor.queries
        #expect(queries == [
            AdvancedSettingsDQL.setSyncScopesQuery,
            AdvancedSettingsDQL.showSyncScopesQuery
        ])
        let calls = executor.calls
        #expect(calls[0].arguments["scopes"] as? [String: String] == ["orders": "LocalPeerOnly"])
    }

    /// The whole point of the read-back: if the SDK accepted the statement but stored
    /// something else, the user's containment choice is not in force.
    @Test(.tags(.service, .fast))
    func `a read back that disagrees throws`() async throws {
        // ARRANGE — asked for LocalPeerOnly, the store reports AllPeers.
        let executor = RecordingExecutor(showRows: showRow(["orders": "AllPeers"]))
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await applier.applySyncScopes([
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
            ])
        }
    }

    @Test(.tags(.service, .fast))
    func `a rejected scope statement throws instead of continuing`() async throws {
        // ARRANGE
        // Reference the production constant rather than duplicating the statement text:
        // a hardcoded copy can drift from what the applier actually sends, and this test
        // would then pass by failing on nothing.
        let executor = RecordingExecutor(failingPrefixes: [AdvancedSettingsDQL.setSyncScopesQuery])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await applier.applySyncScopes([
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
            ])
        }
    }

    @Test(.tags(.service, .fast))
    func `duplicate collections throw rather than resolving to one scope`() async throws {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await applier.applySyncScopes([
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly),
                CollectionSyncScope(collection: "orders", scope: .allPeers)
            ])
        }
        let queries = executor.queries
        #expect(queries.isEmpty, "nothing should be sent when the scope list is contradictory")
    }

    /// Removing the last scope row must actually CLEAR the live setting. Returning early
    /// on an empty list meant the SDK kept enforcing the old `LocalPeerOnly` while the UI
    /// showed none, and the re-apply reported success having sent nothing.
    @Test(.tags(.service, .fast))
    func `an empty scope list still issues a clearing statement`() async throws {
        // ARRANGE — the instance reports no scopes after the clear.
        let executor = RecordingExecutor(showRows: showRow([:]))
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([])

        // ASSERT
        #expect(outcome.applied == 0)
        #expect(outcome.verified)
        #expect(executor.queries.first == AdvancedSettingsDQL.setSyncScopesQuery)
        #expect(executor.calls.first?.arguments["scopes"] as? [String: String] == [:])
    }

    /// If a scope survives a clear, some other writer set it — report it rather than
    /// claim our own success.
    @Test(.tags(.service, .fast))
    func `a scope surviving a clear is reported as unverified`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: showRow(["orders": "LocalPeerOnly"]))
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([])

        // ASSERT
        #expect(outcome.applied == 0)
        #expect(outcome.verified == false)
    }

    @Test(.tags(.service, .fast))
    func `too many scopes is rejected before any statement`() async throws {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)
        let scopes = (0 ... AdvancedSettingsValidator.maxRowCount).map {
            CollectionSyncScope(collection: "c\($0)", scope: .localPeerOnly)
        }

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await applier.applySyncScopes(scopes)
        }
        #expect(executor.queries.isEmpty)
    }

    /// A name the editor would reject must fail closed here too — otherwise it becomes a
    /// scope key matching no collection, which then "verifies" successfully.
    @Test(.tags(.service, .fast))
    func `a collection name needing quoting is rejected`() async throws {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await applier.applySyncScopes([
                CollectionSyncScope(collection: "order items", scope: .localPeerOnly)
            ])
        }
        #expect(executor.queries.isEmpty)
    }

    /// An unrecognized read-back shape must not block the open — the write itself
    /// would have thrown for an unknown parameter — but it must not silently claim
    /// verification either.
    @Test(.tags(.service, .fast))
    func `an unreadable read back does not block the open`() async throws {
        // ARRANGE — SHOW returns nothing useful.
        let executor = RecordingExecutor(showRows: [])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT — the write happened, but we must not claim verification.
        #expect(outcome.applied == 1)
        #expect(outcome.verified == false)
    }

    /// A read-back that reports MORE scopes than this config set (e.g. one applied by a
    /// query the user ran) must still verify: demanding exact equality made the database
    /// refuse to open over an unrelated entry.
    @Test(.tags(.service, .fast))
    func `a read back containing extra scopes still verifies ours`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(
            showRows: showRow(["orders": "LocalPeerOnly", "somethingElse": "AllPeers"])
        )
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT
        #expect(outcome.applied == 1)
        #expect(outcome.verified)
    }

    /// A failing `SHOW` must not brick every database that uses scopes — the SET
    /// already succeeded, so this is "unverified", not "broken".
    @Test(.tags(.service, .fast))
    func `a failing read back query does not throw`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(failingPrefixes: ["SHOW"])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT
        #expect(outcome.applied == 1)
        #expect(outcome.verified == false)
    }

    /// Read-back parsing must not depend on dictionary ordering. A row with several
    /// columns and no scope map used to hit `row.values.first`, picking an arbitrary
    /// element — so verification passed or threw depending on the process hash seed.
    @Test(.tags(.service, .fast))
    func `an unrelated multi column row is unverified, not randomly matched`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: [[
            "some_other_parameter": "AllPeers",
            "another_column": ["orders": "AllPeers"]
        ]])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT — deterministic: unverified, never a spurious mismatch throw.
        #expect(outcome.verified == false)
    }

    /// Shape B: a name/value row.
    @Test(.tags(.service, .fast))
    func `a name value row shape is parsed`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: [[
            "name": AdvancedSettingsDQL.syncScopesReadParameter,
            "value": ["orders": "LocalPeerOnly"]
        ]])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT
        #expect(outcome.verified)
    }

    /// Shape C: the value arrives as JSON text.
    @Test(.tags(.service, .fast))
    func `a JSON string value is parsed`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: [[
            AdvancedSettingsDQL.syncScopesReadParameter: #"{"orders":"LocalPeerOnly"}"#
        ]])
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        let outcome = try await applier.applySyncScopes([
            CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
        ])

        // ASSERT
        #expect(outcome.verified)
    }
}

@Suite("AdvancedSettingsApplier.OpenSequence — the real database-open order")
struct OpenSequenceTests {
    /// Builds the sequence the way `DittoManager.hydrateDittoSelectedDatabase` does,
    /// recording every side effect in order.
    private func makeSequence(
        executor: RecordingExecutor,
        events: EventLog,
        isStrictModeEnabled: Bool = false,
        meshMaxWlanClients: Int? = 12
    ) -> AdvancedSettingsApplier.OpenSequence {
        AdvancedSettingsApplier.OpenSequence(
            applier: AdvancedSettingsApplier(executor: executor),
            applyTransportConfig: { events.record("transportConfig") },
            isStrictModeEnabled: isStrictModeEnabled,
            meshMaxWlanClients: meshMaxWlanClients,
            beforeSync: { events.record("transportReadback") },
            startSync: { events.record("syncStarted") }
        )
    }

    /// The SDK requires sync scopes before `start_sync()` — its own error string says
    /// so. This drives the PRODUCTION sequence, so moving the scope statement after
    /// sync start fails here rather than leaking LocalPeerOnly data silently.
    @Test(.tags(.service, .fast))
    func `sync starts only after settings, transports and scopes are applied`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(showRows: showRow(["orders": "LocalPeerOnly"]))
        let events = EventLog()
        let sequence = makeSequence(executor: executor, events: events)

        // ACT
        let result = try await sequence.run(
            startupSettings: [StartupSetting(parameter: "example_parameter", type: .integer, value: "42")],
            syncScopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)]
        )

        // ASSERT — ordering, from the executor and the side-effect log combined.
        let queries = executor.queries
        let userSetting = try #require(queries.firstIndex { $0.hasPrefix("ALTER SYSTEM SET example_parameter") })
        let strictMode = try #require(queries.firstIndex { $0.hasPrefix("ALTER SYSTEM SET DQL_STRICT_MODE") })
        let mesh = try #require(queries.firstIndex { $0.hasPrefix("ALTER SYSTEM SET mesh_chooser_max_wlan_clients") })
        let scopes = try #require(queries.firstIndex(of: AdvancedSettingsDQL.setSyncScopesQuery))

        #expect(userSetting < strictMode, "user settings must apply first so app-managed values win")
        #expect(strictMode < mesh)
        #expect(mesh < scopes)
        #expect(events.recorded == ["transportConfig", "transportReadback", "syncStarted"])
        #expect(events.recorded.last == "syncStarted", "sync must be the final step")
        #expect(result.appliedScopeCount == 1)
        #expect(result.scopesUnverified == false)
    }

    /// The fail-closed guarantee, asserted where it matters: not merely that a function
    /// throws, but that `startSync` is NEVER reached.
    @Test(.tags(.service, .fast))
    func `a scope failure prevents sync from starting at all`() async throws {
        // ARRANGE — the scope statement is rejected by the SDK. Keyed off the production
        // constant, not a copy of its text, so it cannot drift out of sync.
        let executor = RecordingExecutor(
            failingPrefixes: [AdvancedSettingsDQL.setSyncScopesQuery]
        )
        let events = EventLog()
        let sequence = makeSequence(executor: executor, events: events)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await sequence.run(
                startupSettings: [],
                syncScopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)]
            )
        }
        #expect(events.recorded.contains("syncStarted") == false, "sync must not start")
    }

    /// Same guarantee for a read-back that positively disagrees.
    @Test(.tags(.service, .fast))
    func `a verification mismatch prevents sync from starting`() async throws {
        // ARRANGE — asked for LocalPeerOnly, the store reports AllPeers.
        let executor = RecordingExecutor(showRows: showRow(["orders": "AllPeers"]))
        let events = EventLog()
        let sequence = makeSequence(executor: executor, events: events)

        // ACT / ASSERT
        await #expect(throws: AdvancedSettingsApplier.ApplyError.self) {
            try await sequence.run(
                startupSettings: [],
                syncScopes: [CollectionSyncScope(collection: "orders", scope: .localPeerOnly)]
            )
        }
        #expect(events.recorded.contains("syncStarted") == false)
    }

    /// A bad startup setting is best-effort: reported, but the open continues.
    @Test(.tags(.service, .fast))
    func `a rejected startup setting still lets the database open`() async throws {
        // ARRANGE
        let executor = RecordingExecutor(failingPrefixes: ["ALTER SYSTEM SET bogus_parameter"])
        let events = EventLog()
        let sequence = makeSequence(executor: executor, events: events)

        // ACT
        let result = try await sequence.run(
            startupSettings: [StartupSetting(parameter: "bogus_parameter", type: .integer, value: "1")],
            syncScopes: []
        )

        // ASSERT
        #expect(result.skippedSettings.count == 1)
        #expect(events.recorded.contains("syncStarted"), "an unknown parameter must not block the open")
    }

    @Test(.tags(.service, .fast))
    func `the mesh statement is omitted when no cap is configured`() async throws {
        // ARRANGE — the non-macOS case.
        let executor = RecordingExecutor()
        let events = EventLog()
        let sequence = makeSequence(executor: executor, events: events, meshMaxWlanClients: nil)

        // ACT
        try await sequence.run(startupSettings: [], syncScopes: [])

        // ASSERT
        #expect(executor.queries.contains { $0.contains("mesh_chooser_max_wlan_clients") } == false)
    }

    @Test(.tags(.service, .fast))
    func `reset issues RESET ALL`() async throws {
        // ARRANGE
        let executor = RecordingExecutor()
        let applier = AdvancedSettingsApplier(executor: executor)

        // ACT
        try await applier.resetAllToDefaults()

        // ASSERT
        #expect(executor.queries == ["ALTER SYSTEM RESET ALL"])
    }
}

/// Pins the sync-scope statements to **literals**.
///
/// Raised by the pre-commit adversarial review: every other scope test compares the
/// statement to `AdvancedSettingsDQL`'s own constants, and the recording fake keys its
/// read-back row off the same constant. So a typo in `USER_COLLECTION_SYNC_SCOPES` — the
/// parameter that carries the containment control — passed the whole suite, read-back
/// "verification" included, while the real SDK silently applied nothing. These are the
/// spellings proven against SDK 5.1.0 by a scratch SPM probe (`docs/ADVANCED_DATABASE_CONFIG.md`);
/// if the SDK ever changes them, this test is where it must be re-proven, not quietly followed.
@Suite("AdvancedSettingsDQL — statement spelling")
struct AdvancedSettingsDQLSpellingTests {
    @Test(.tags(.fast))
    func `the sync-scope statements match the spellings proven against the SDK`() {
        // ACT / ASSERT — written out, not composed from the constants under test.
        //
        // The disable is the point, not a workaround: `sync_scopes_via_applier` exists to stop
        // anyone writing that parameter outside the applier, and it fired on this line — a
        // fatal build error — which is the rule proving itself. This occurrence is an equality
        // assertion about the spelling, not a write path; there is no executor here.
        // swiftlint:disable:next sync_scopes_via_applier
        #expect(AdvancedSettingsDQL.setSyncScopesQuery == "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes")
        #expect(AdvancedSettingsDQL.showSyncScopesQuery == "SHOW user_collection_sync_scopes")
        #expect(AdvancedSettingsDQL.resetAllQuery == "ALTER SYSTEM RESET ALL")
    }

    /// The write parameter is upper-case and the read parameter lower-case on purpose — DQL
    /// parameter names are case-insensitive on write and come back lowercased from `SHOW`,
    /// which is what `coerceScopeMap` parses. Collapsing them to one constant would look like
    /// a tidy-up and break the read-back.
    @Test(.tags(.fast))
    func `the read parameter is the lowercased write parameter`() {
        #expect(AdvancedSettingsDQL.syncScopesParameter == "USER_COLLECTION_SYNC_SCOPES")
        #expect(AdvancedSettingsDQL.syncScopesReadParameter == "user_collection_sync_scopes")
        #expect(
            AdvancedSettingsDQL.syncScopesReadParameter
                == AdvancedSettingsDQL.syncScopesParameter.lowercased()
        )
    }
}
