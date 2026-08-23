import Testing
@testable import Ditto_Edge_Studio

/// Test suite for CollectionsRepository
///
/// CollectionsRepository queries a live Ditto store, so full collection tests
/// require a live Ditto instance and belong in EdgeStudioIntegrationTests.
///
/// These unit tests cover:
/// - Error paths: hydrateCollections() and refreshDocumentCounts() with no
///   selected database throw or return safely (no crash)
/// - stopObserver() with no active observer is safe and idempotent
///   (crash-only smoke tests — see the suite note)
/// - Pure DQL builders: CREATE INDEX quoting/sanitisation, document-count
///   query quoting, system:indexes parsing and index-definition matching
///
/// TODO: Integration tests needed
/// Full integration tests (hydrateCollections with a real Ditto instance,
/// refreshDocumentCounts accuracy, real-time observer updates) should be
/// added to EdgeStudioIntegrationTests once a live Ditto test instance is
/// available.
///
/// Target: ~20% code coverage (error paths only).
@Suite("CollectionsRepository Tests", .serialized)
struct CollectionsRepositoryTests {
    // MARK: - Error Path Tests

    @Suite("Error Paths")
    struct ErrorPathTests {
        @Test(.tags(.repository))
        func `hydrateCollections with no selected app throws InvalidStateError`() async throws {
            // ARRANGE — No selected app (unit test environment: DittoManager.dittoSelectedApp is nil)

            let repo = CollectionsRepository.shared

            // ACT & ASSERT — should throw because dittoSelectedApp is nil
            await #expect(throws: (any Error).self) {
                _ = try await repo.hydrateCollections()
            }
        }

        @Test(.tags(.repository))
        func `refreshCollections with no selected app throws InvalidStateError`() async throws {
            // ARRANGE — No selected app

            let repo = CollectionsRepository.shared

            // ACT & ASSERT — should throw because dittoSelectedApp is nil
            await #expect(throws: (any Error).self) {
                _ = try await repo.refreshCollections()
            }
        }
    }

    // MARK: - Stop Observer Tests

    /// NOTE: these are crash-only smoke tests. stopObserver() touches
    /// actor-isolated observer state that cannot be observed from outside
    /// without a live Ditto instance, so "does not crash / is idempotent"
    /// is the only unit-testable property. Real observer-behaviour tests
    /// belong in EdgeStudioIntegrationTests.
    @Suite("Stop Observer")
    struct StopObserverTests {
        @Test(.tags(.repository))
        func `stopObserver with no active observer does not crash`() async {
            // ARRANGE — No observer has been registered
            let repo = CollectionsRepository.shared

            // ACT & ASSERT — crash-only smoke test (see suite note)
            await repo.stopObserver()
        }

        @Test(.tags(.repository))
        func `stopObserver can be called multiple times safely`() async {
            // ARRANGE
            let repo = CollectionsRepository.shared

            // ACT — call multiple times; crash-only smoke test (see suite
            // note). Reaching the end without a crash IS the assertion.
            await repo.stopObserver()
            await repo.stopObserver()
            await repo.stopObserver()
        }
    }

    // MARK: - Create Index DQL Builder Tests

    @Suite("Create Index DQL Builder")
    struct CreateIndexDQLBuilderTests {
        @Test(.tags(.repository))
        func `single field produces single-key CREATE INDEX with explicit ASC`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "tasks",
                fields: [IndexField(name: "status")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_tasks_status` ON `tasks` (`status` ASC)")
        }

        @Test(.tags(.repository))
        func `multiple fields produce a composite index preserving field order`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "tasks",
                fields: [
                    IndexField(name: "status", ascending: true),
                    IndexField(name: "createdAt", ascending: false)
                ]
            )
            #expect(
                query
                    == "CREATE INDEX IF NOT EXISTS `idx_tasks_status_createdAt` ON `tasks` (`status` ASC, `createdAt` DESC)"
            )
        }

        @Test(.tags(.repository))
        func `dots and dashes in names are sanitised to underscores`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "address.city"), IndexField(name: "last-name")]
            )
            #expect(
                query
                    == "CREATE INDEX IF NOT EXISTS `idx_users_address_city_last_name` ON `users` (`address`.`city` ASC, `last-name` ASC)"
            )
        }

        @Test(.tags(.repository))
        func `field paths are backtick-quoted per segment so spaces parse`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "last name")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_users_last_name` ON `users` (`last name` ASC)")
        }

        @Test(.tags(.repository))
        func `embedded backticks are escaped by doubling`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "we`ird")]
            )
            #expect(query.contains("(`we``ird` ASC)"))
        }

        @Test(.tags(.repository))
        func `index name is backtick-quoted so residual punctuation parses`() throws {
            // makeIndexName only sanitises ., space and dash; anything else
            // (parens, quotes) stays in the name and must be quoted — an
            // unquoted dash/paren in the name is a hard DQL parse error.
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "score(v2)")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_users_score(v2)` ON `users` (`score(v2)` ASC)")
        }

        @Test(.tags(.repository))
        func `double quote in field name stays inside the quoted index name`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "say\"hi\"")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_users_say\"hi\"` ON `users` (`say\"hi\"` ASC)")
        }

        @Test(.tags(.repository))
        func `backtick in field name is doubled inside the quoted index name`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "users",
                fields: [IndexField(name: "we`ird")]
            )
            #expect(query.hasPrefix("CREATE INDEX IF NOT EXISTS `idx_users_we``ird` ON "))
        }

        @Test(.tags(.repository))
        func `blank fields are dropped from the statement`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "tasks",
                fields: [IndexField(name: "  "), IndexField(name: " status ")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_tasks_status` ON `tasks` (`status` ASC)")
        }

        @Test(.tags(.repository))
        func `all-blank fields throw`() {
            #expect(throws: (any Error).self) {
                _ = try CollectionsRepository.makeCreateIndexQuery(
                    collection: "tasks",
                    fields: [IndexField(name: ""), IndexField(name: "   ")]
                )
            }
        }

        @Test(.tags(.repository))
        func `empty field list throws`() {
            #expect(throws: (any Error).self) {
                _ = try CollectionsRepository.makeCreateIndexQuery(
                    collection: "tasks",
                    fields: []
                )
            }
        }

        @Test(.tags(.repository))
        func `makeIndexName joins collection and field names`() {
            let name = CollectionsRepository.makeIndexName(
                collection: "tasks",
                fields: [IndexField(name: "status"), IndexField(name: "createdAt")]
            )
            #expect(name == "idx_tasks_status_createdAt")
        }

        @Test(.tags(.repository))
        func `collection name is backtick-quoted so names with spaces parse`() throws {
            let query = try CollectionsRepository.makeCreateIndexQuery(
                collection: "my collection",
                fields: [IndexField(name: "status")]
            )
            #expect(query == "CREATE INDEX IF NOT EXISTS `idx_my_collection_status` ON `my collection` (`status` ASC)")
        }

        @Test(.tags(.repository))
        func `document count query backtick-quotes the collection name`() {
            #expect(
                CollectionsRepository.makeDocumentCountQuery(collection: "tasks")
                    == "SELECT COUNT(*) as numDocs FROM `tasks`"
            )
            // Names with spaces/dashes previously failed per-collection and
            // were swallowed to nil counts.
            #expect(
                CollectionsRepository.makeDocumentCountQuery(collection: "my collection")
                    == "SELECT COUNT(*) as numDocs FROM `my collection`"
            )
            #expect(
                CollectionsRepository.makeDocumentCountQuery(collection: "we`ird")
                    == "SELECT COUNT(*) as numDocs FROM `we``ird`"
            )
        }

        @Test(.tags(.repository))
        func `unquoteSegment unwraps quoted segments and collapses escaped backticks`() {
            #expect(CollectionsRepository.unquoteSegment("`createdAt`") == "createdAt")
            #expect(CollectionsRepository.unquoteSegment("`we``ird`") == "we`ird")
            // Raw 5.1 segments pass through untouched
            #expect(CollectionsRepository.unquoteSegment("createdAt") == "createdAt")
            #expect(CollectionsRepository.unquoteSegment("we`ird") == "we`ird")
        }
    }

    // MARK: - system:indexes Parsing & Definition Matching Tests

    @Suite("Index Definition Matching")
    struct IndexDefinitionMatchingTests {
        @Test(.tags(.repository))
        func `parseIndexKeys parses SDK 5.x object format with directions`() {
            let json: [String: Any] = [
                "fields": [
                    ["direction": "asc", "key": ["status"]],
                    ["direction": "desc", "key": ["createdAt"]]
                ]
            ]
            let keys = CollectionsRepository.parseIndexKeys(from: json)
            #expect(keys == [
                IndexField(name: "status", ascending: true),
                IndexField(name: "createdAt", ascending: false)
            ])
        }

        @Test(.tags(.repository))
        func `parseIndexKeys joins nested path segments with dots`() {
            let json: [String: Any] = [
                "fields": [["direction": "asc", "key": ["properties", "engine", "type"]]]
            ]
            let keys = CollectionsRepository.parseIndexKeys(from: json)
            #expect(keys == [IndexField(name: "properties.engine.type", ascending: true)])
        }

        @Test(.tags(.repository))
        func `parseIndexKeys strips backticks emitted by older SDKs`() {
            let json: [String: Any] = [
                "fields": [["direction": "desc", "key": ["`createdAt`"]]]
            ]
            let keys = CollectionsRepository.parseIndexKeys(from: json)
            #expect(keys == [IndexField(name: "createdAt", ascending: false)])
        }

        @Test(.tags(.repository))
        func `parseIndexKeys accepts legacy plain string arrays`() {
            let json: [String: Any] = ["fields": ["status", "`priority`"]]
            let keys = CollectionsRepository.parseIndexKeys(from: json)
            #expect(keys == [
                IndexField(name: "status", ascending: true),
                IndexField(name: "priority", ascending: true)
            ])
        }

        @Test(.tags(.repository))
        func `parseIndexKeys returns empty for missing or malformed fields`() {
            #expect(CollectionsRepository.parseIndexKeys(from: [:]).isEmpty)
            #expect(CollectionsRepository.parseIndexKeys(from: ["fields": 42]).isEmpty)
            #expect(CollectionsRepository.parseIndexKeys(from: ["fields": [["direction": "asc"]]]).isEmpty)
        }

        @Test(.tags(.repository))
        func `indexKeysMatch: identical definitions match`() {
            let a = [IndexField(name: "status"), IndexField(name: "createdAt", ascending: false)]
            #expect(CollectionsRepository.indexKeysMatch(existing: a, requested: a))
        }

        @Test(.tags(.repository))
        func `indexKeysMatch: flipped direction does not match`() {
            let existing = [IndexField(name: "status"), IndexField(name: "createdAt", ascending: false)]
            let requested = [IndexField(name: "status"), IndexField(name: "createdAt", ascending: true)]
            #expect(!CollectionsRepository.indexKeysMatch(existing: existing, requested: requested))
        }

        @Test(.tags(.repository))
        func `indexKeysMatch: different order or count does not match`() {
            let a = [IndexField(name: "status"), IndexField(name: "createdAt")]
            #expect(!CollectionsRepository.indexKeysMatch(existing: a, requested: Array(a.reversed())))
            #expect(!CollectionsRepository.indexKeysMatch(existing: a, requested: Array(a.dropLast())))
        }
    }

    // MARK: - Callback Registration Tests

    //
    // Removed: the previous "Callback Registration" suite was vacuous — it
    // called setOnCollectionsUpdate/setAppState and then asserted
    // `#expect(Bool(true))`, which cannot fail. There is nothing real to
    // assert here without a live Ditto instance: the callback is private
    // actor state and is only invoked from hydrate/refresh paths that throw
    // when no app is selected. Callback-invocation tests belong in
    // EdgeStudioIntegrationTests.
}

// MARK: - Integration Test Stub

// TODO: Integration tests needed
// The following tests require a live Ditto instance and belong in EdgeStudioIntegrationTests.
// Add them when a Ditto test instance is available:
//
// @Suite("CollectionsRepository Integration Tests")
// struct CollectionsRepositoryIntegrationTests {
//
//     @Test("hydrateCollections returns non-empty list when collections exist")
//     func testHydrateCollectionsWithLiveDitto() async throws { ... }
//
//     @Test("refreshDocumentCounts returns accurate document counts")
//     func testRefreshDocumentCounts() async throws { ... }
//
//     @Test("Real-time observer fires when collection changes")
//     func testRealTimeObserver() async throws { ... }
// }
