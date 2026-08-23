import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers the JSON bridging and its two deliberately-different failure policies, which
/// had no tests: sync scopes are containment configuration (a corrupt block must not
/// silently become "no scopes"), startup settings are tuning knobs (a corrupt block
/// must not block access to the database).
@Suite("DatabaseRepository — advanced settings decoding", .serialized)
struct DatabaseRepositoryAdvancedTests {
    /// Writes raw JSON straight into a stored row, bypassing the encoder.
    private func corrupt(
        column: String,
        to value: String,
        databaseId: String,
        service: SQLCipherService
    ) async throws {
        try await service.executeRawForTesting(
            "UPDATE databaseConfigs SET \(column) = ? WHERE databaseId = ?",
            [value, databaseId]
        )
    }

    /// Unreadable containment configuration marks the config unopenable — it must never
    /// quietly load as "no scopes", which would start syncing a collection the user had
    /// marked device-local.
    @Test(.tags(.repository, .database))
    func `A corrupt sync-scope column marks the config unopenable`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            config.collectionSyncScopes = [
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
            ]
            try await repo.addDittoAppConfig(config)
            try await corrupt(
                column: "collectionSyncScopes",
                to: "{{{not json",
                databaseId: config.databaseId,
                service: SQLCipherContext.current
            )

            // ACT
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded.count == 1)
            #expect(loaded[0].hasCorruptSyncScopes)
            #expect(loaded[0].collectionSyncScopes.isEmpty)
        }
    }

    /// One bad row must not hide the others. Aborting the whole load left the user with
    /// no database list at all — and the remedy was in a screen only reachable through
    /// that list.
    @Test(.tags(.repository, .database))
    func `One corrupt row does not hide the other databases`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let broken = DatabaseConfigFixtures.validServerConfig()
            let healthy = DatabaseConfigFixtures.validServerConfig2()
            try await repo.addDittoAppConfig(broken)
            try await repo.addDittoAppConfig(healthy)
            try await corrupt(
                column: "collectionSyncScopes",
                to: "[{\"collection\":}]",
                databaseId: broken.databaseId,
                service: SQLCipherContext.current
            )

            // ACT
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded.count == 2)
            let brokenLoaded = loaded.first { $0.databaseId == broken.databaseId }
            let healthyLoaded = loaded.first { $0.databaseId == healthy.databaseId }
            #expect(brokenLoaded?.hasCorruptSyncScopes == true)
            #expect(healthyLoaded?.hasCorruptSyncScopes == false)
        }
    }

    /// An unknown scope value must fail the decode rather than coerce to a default.
    @Test(.tags(.repository, .database))
    func `An unknown scope value is treated as corrupt`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            try await repo.addDittoAppConfig(config)
            try await corrupt(
                column: "collectionSyncScopes",
                to: "[{\"collection\":\"orders\",\"scope\":\"SomeFutureScope\"}]",
                databaseId: config.databaseId,
                service: SQLCipherContext.current
            )

            // ACT
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded[0].hasCorruptSyncScopes)
        }
    }

    /// Startup settings take the opposite policy: degrade and keep going.
    @Test(.tags(.repository, .database))
    func `A corrupt startup-settings column degrades to empty`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            config.startupSettings = [
                StartupSetting(parameter: "example_parameter", type: .integer, value: "42")
            ]
            try await repo.addDittoAppConfig(config)
            try await corrupt(
                column: "startupSettings",
                to: "not json at all",
                databaseId: config.databaseId,
                service: SQLCipherContext.current
            )

            // ACT
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT — still loads, still openable, just without the settings.
            #expect(loaded.count == 1)
            #expect(loaded[0].startupSettings.isEmpty)
            #expect(loaded[0].hasCorruptSyncScopes == false)
        }
    }

    /// The acknowledgement flag has to survive persistence, or the apply path would
    /// re-prompt (and refuse) a setting the user already confirmed.
    @Test(.tags(.repository, .database))
    func `The sensitive-parameter acknowledgement persists`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            config.startupSettings = [
                StartupSetting(
                    parameter: "metrics_exporter_prometheus_http_listener_addr",
                    type: .string,
                    value: "0.0.0.0:9000",
                    isAcknowledged: true
                )
            ]

            // ACT
            try await repo.addDittoAppConfig(config)
            let loaded = try await repo.loadDatabaseConfigs()

            // ASSERT
            #expect(loaded[0].startupSettings.first?.isAcknowledged == true)
        }
    }

    // MARK: Primary-key targeting

    /// A Database ID is fixed at registration: `updateDatabaseConfig` does not write the
    /// column, because it is a parent foreign key with no `ON UPDATE` (four child tables
    /// reference it) and it names the on-disk store directory. The editor disables the
    /// field for an existing config; this asserts the storage layer holds the same line
    /// even if something bypasses the UI.
    ///
    /// The rest of the save must still land — that is the whole point. Editing the ID used
    /// to raise `FOREIGN KEY constraint failed` and take the name and scope edits down
    /// with it.
    @Test(.tags(.repository, .database))
    func `A submitted Database ID change is ignored while the rest of the save lands`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let config = DatabaseConfigFixtures.validServerConfig()
            let originalId = config.databaseId
            try await repo.addDittoAppConfig(config)

            // A child row, so the foreign key is actually load-bearing. The previous
            // version of this test passed only because its fixture had none — with a
            // `history` row present, the old `SET … databaseId = ?` raised
            // `FOREIGN KEY constraint failed (19)`. Inserted through SQLCipherService
            // directly rather than HistoryRepository, which needs `loadHistory(for:)`
            // called first to establish session state this test does not otherwise need.
            try await SQLCipherContext.current.insertHistory(
                SQLCipherService.HistoryRow(
                    _id: TestHelpers.uniqueTestId(),
                    databaseId: originalId,
                    query: "SELECT * FROM orders",
                    createdDate: Date.now.ISO8601Format()
                )
            )

            // ACT — submit a new id alongside real edits.
            config.databaseId = "db-renamed"
            config.name = "Renamed"
            config.developmentToken = "rotated-token"
            config.collectionSyncScopes = [
                CollectionSyncScope(collection: "orders", scope: .localPeerOnly)
            ]
            try await repo.updateDittoAppConfig(config)

            // ASSERT — read back from storage, not the cache.
            let loaded = try await repo.loadDatabaseConfigs()
            #expect(loaded.count == 1)
            #expect(loaded[0].databaseId == originalId, "the Database ID must be immutable")
            #expect(loaded[0].name == "Renamed")
            #expect(loaded[0].developmentToken == "rotated-token")
            #expect(loaded[0].collectionSyncScopes.count == 1)

            // The child row is still joined to its parent. If the update had rewritten
            // the parent key, the FK would either have failed the whole save or orphaned
            // this row — both of which this assertion catches.
            let history = try await SQLCipherContext.current.getHistory(databaseId: originalId)
            #expect(history.count == 1, "the history child row must still reference its parent")
        }
    }

    /// One config's save must never rewrite another's row. This used to depend on the
    /// `UNIQUE` index rejecting a retargeted `databaseId`; now that the column is not in
    /// the `SET` list and the statement is keyed on the `_id` primary key, a cross-row
    /// overwrite is structurally impossible — so this asserts both rows survive intact
    /// rather than asserting a throw that no longer happens.
    @Test(.tags(.repository, .database))
    func `Editing one config never overwrites another`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let first = DatabaseConfigFixtures.validServerConfig()
            let second = DatabaseConfigFixtures.validServerConfig2()
            try await repo.addDittoAppConfig(first)
            try await repo.addDittoAppConfig(second)
            let firstId = first.databaseId
            let secondId = second.databaseId
            let secondName = second.name
            let secondToken = second.developmentToken

            // ACT — retarget the first config's id onto the second's, and rename it.
            first.databaseId = second.databaseId
            first.name = "Clobberer"
            try await repo.updateDittoAppConfig(first)

            // ASSERT — the other config is untouched…
            let loaded = try await repo.loadDatabaseConfigs()
            #expect(loaded.count == 2)
            let survivor = loaded.first { $0._id == second._id }
            #expect(survivor?.databaseId == secondId)
            #expect(survivor?.name == secondName)
            #expect(survivor?.developmentToken == secondToken)

            // …and the edited config kept its own id while taking the rename.
            let edited = loaded.first { $0._id == first._id }
            #expect(edited?.databaseId == firstId)
            #expect(edited?.name == "Clobberer")
        }
    }

    /// The `UNIQUE` index on `databaseId` is still load-bearing — just on the INSERT path
    /// now rather than the UPDATE path. Dropping the update-path throw must not quietly
    /// retire coverage of duplicate registration.
    @Test(.tags(.repository, .database))
    func `Registering a duplicate Database ID is rejected`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE
            let repo = DatabaseRepository.shared
            let first = DatabaseConfigFixtures.validServerConfig()
            try await repo.addDittoAppConfig(first)

            let duplicate = DatabaseConfigFixtures.validServerConfig2()
            duplicate.databaseId = first.databaseId

            // ACT / ASSERT
            await #expect(throws: (any Error).self) {
                try await repo.addDittoAppConfig(duplicate)
            }
        }
    }

    /// A write that matches no row must throw, not report success.
    @Test(.tags(.repository, .database))
    func `Updating a config that no longer exists throws`() async throws {
        try await TestHelpers.withFreshDatabase {
            // ARRANGE — never inserted.
            let orphan = DatabaseConfigFixtures.validServerConfig()

            // ACT / ASSERT
            await #expect(throws: (any Error).self) {
                try await DatabaseRepository.shared.updateDittoAppConfig(orphan)
            }
        }
    }
}
