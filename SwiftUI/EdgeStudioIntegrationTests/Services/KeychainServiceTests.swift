import Testing
@testable import Ditto_Edge_Studio

/// Comprehensive test suite for KeychainService
///
/// Tests cover:
/// - Save and load credentials round-trip
/// - Overwrite (update) existing credentials
/// - Delete removes item, delete non-existent is idempotent
/// - listDatabaseIds reflects adds and removes
/// - Isolation: different databaseId values don't collide
/// - Edge cases: empty string fields, UUID-length strings
///
/// Uses .serialized because Keychain is a shared system resource.
/// Each test uses TestHelpers.uniqueTestId() for databaseIds to avoid
/// collisions with production data and between parallel tests.
///
/// **IMPORTANT:** All test keychain entries are deleted after each test.
/// Target: 85% code coverage.
@Suite("KeychainService Tests", .serialized)
struct KeychainServiceTests {

    // MARK: - Save and Load Tests

    @Suite("Save and Load")
    struct SaveAndLoadTests {

        @Test("Save and load credentials round-trip preserves all fields", .tags(.service, .encryption))
        func testSaveLoadRoundTrip() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest")
            let credentials = KeychainService.DatabaseCredentials(
                name: "My Test DB",
                token: "test-token-abc",
                authUrl: "https://auth.test.com",
                websocketUrl: "wss://ws.test.com",
                httpApiUrl: "https://api.test.com",
                httpApiKey: "api-key-xyz",
                secretKey: "secret-123"
            )

            // ACT
            try await service.saveDatabaseCredentials(dbId, credentials: credentials)
            let loaded = try await service.loadDatabaseCredentials(dbId)

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId)
            #expect(loaded != nil)
            #expect(loaded?.name == "My Test DB")
            #expect(loaded?.token == "test-token-abc")
            #expect(loaded?.authUrl == "https://auth.test.com")
            #expect(loaded?.websocketUrl == "wss://ws.test.com")
            #expect(loaded?.httpApiUrl == "https://api.test.com")
            #expect(loaded?.httpApiKey == "api-key-xyz")
            #expect(loaded?.secretKey == "secret-123")
        }

        @Test("Load non-existent credentials returns nil", .tags(.service, .encryption))
        func testLoadNonExistentReturnsNil() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-nonexist")

            // ACT
            let loaded = try await service.loadDatabaseCredentials(dbId)

            // ASSERT — no entry, should return nil, not throw
            #expect(loaded == nil)
        }

        @Test("Overwrite credentials replaces all fields", .tags(.service, .encryption))
        func testOverwriteCredentials() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-overwrite")
            let original = KeychainService.DatabaseCredentials(
                name: "Original DB",
                token: "token-v1",
                authUrl: "https://v1.auth.com",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: "",
                secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId, credentials: original)

            let updated = KeychainService.DatabaseCredentials(
                name: "Updated DB",
                token: "token-v2",
                authUrl: "https://v2.auth.com",
                websocketUrl: "wss://v2.ws.com",
                httpApiUrl: "https://v2.api.com",
                httpApiKey: "new-key",
                secretKey: "new-secret"
            )

            // ACT — save again to same databaseId
            try await service.saveDatabaseCredentials(dbId, credentials: updated)
            let loaded = try await service.loadDatabaseCredentials(dbId)

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId)
            #expect(loaded?.name == "Updated DB")
            #expect(loaded?.token == "token-v2")
            #expect(loaded?.authUrl == "https://v2.auth.com")
            #expect(loaded?.secretKey == "new-secret")
        }
    }

    // MARK: - Delete Tests

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes credentials", .tags(.service, .encryption))
        func testDeleteRemovesCredentials() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-del")
            let credentials = KeychainService.DatabaseCredentials(
                name: "To Delete",
                token: "t",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: "",
                secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId, credentials: credentials)

            // ACT
            try await service.deleteDatabaseCredentials(dbId)

            // ASSERT
            let loaded = try await service.loadDatabaseCredentials(dbId)
            #expect(loaded == nil)
        }

        @Test("Delete non-existent credentials is idempotent", .tags(.service, .encryption))
        func testDeleteNonExistentIsIdempotent() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-del-noexist")

            // ACT & ASSERT — should not throw
            try await service.deleteDatabaseCredentials(dbId)

            // Second delete also should not throw
            try await service.deleteDatabaseCredentials(dbId)
        }

        @Test("Delete one does not affect another", .tags(.service, .encryption))
        func testDeleteOneDoesNotAffectAnother() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId1 = TestHelpers.uniqueTestId(prefix: "kctest-keep")
            let dbId2 = TestHelpers.uniqueTestId(prefix: "kctest-gone")

            let creds = KeychainService.DatabaseCredentials(
                name: "DB", token: "t", authUrl: "", websocketUrl: "",
                httpApiUrl: "", httpApiKey: "", secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId1, credentials: creds)
            try await service.saveDatabaseCredentials(dbId2, credentials: creds)

            // ACT — delete only dbId2
            try await service.deleteDatabaseCredentials(dbId2)

            // ASSERT — dbId1 still exists
            let loaded1 = try await service.loadDatabaseCredentials(dbId1)
            let loaded2 = try await service.loadDatabaseCredentials(dbId2)
            try await service.deleteDatabaseCredentials(dbId1)
            #expect(loaded1 != nil)
            #expect(loaded2 == nil)
        }
    }

    // MARK: - List Tests

    @Suite("List Database IDs")
    struct ListTests {

        @Test("listDatabaseIds includes saved database ID", .tags(.service, .encryption))
        func testListIncludesSavedId() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-list")
            let creds = KeychainService.DatabaseCredentials(
                name: "Listed DB", token: "", authUrl: "", websocketUrl: "",
                httpApiUrl: "", httpApiKey: "", secretKey: ""
            )

            // ACT
            try await service.saveDatabaseCredentials(dbId, credentials: creds)
            let ids = try await service.listDatabaseIds()

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId)
            #expect(ids.contains(dbId))
        }

        @Test("listDatabaseIds does not include deleted database ID", .tags(.service, .encryption))
        func testListDoesNotIncludeDeletedId() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-list-del")
            let creds = KeychainService.DatabaseCredentials(
                name: "Temp DB", token: "", authUrl: "", websocketUrl: "",
                httpApiUrl: "", httpApiKey: "", secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId, credentials: creds)

            // ACT
            try await service.deleteDatabaseCredentials(dbId)
            let ids = try await service.listDatabaseIds()

            // ASSERT
            #expect(!ids.contains(dbId))
        }

        @Test("listDatabaseIds returns array (not throws) when empty", .tags(.service, .encryption))
        func testListReturnsArrayWhenEmpty() async throws {
            // ARRANGE
            let service = KeychainService.shared

            // ACT — may have other test entries but should not throw
            let ids = try await service.listDatabaseIds()

            // ASSERT — result is an array (reaching here means no throw occurred)
            #expect(ids.count >= 0)
        }
    }

    // MARK: - Isolation Tests

    @Suite("Isolation")
    struct IsolationTests {

        @Test("Different databaseIds store independent credentials", .tags(.service, .encryption))
        func testDifferentIdsAreIndependent() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId1 = TestHelpers.uniqueTestId(prefix: "kctest-iso-1")
            let dbId2 = TestHelpers.uniqueTestId(prefix: "kctest-iso-2")

            let creds1 = KeychainService.DatabaseCredentials(
                name: "DB One", token: "token-one", authUrl: "",
                websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
            )
            let creds2 = KeychainService.DatabaseCredentials(
                name: "DB Two", token: "token-two", authUrl: "",
                websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
            )

            // ACT
            try await service.saveDatabaseCredentials(dbId1, credentials: creds1)
            try await service.saveDatabaseCredentials(dbId2, credentials: creds2)

            let loaded1 = try await service.loadDatabaseCredentials(dbId1)
            let loaded2 = try await service.loadDatabaseCredentials(dbId2)

            // ASSERT — entries are independent
            try await service.deleteDatabaseCredentials(dbId1)
            try await service.deleteDatabaseCredentials(dbId2)
            #expect(loaded1?.token == "token-one")
            #expect(loaded2?.token == "token-two")
        }

        @Test("Save to one databaseId does not affect another", .tags(.service, .encryption))
        func testSaveDoesNotAffectOther() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId1 = TestHelpers.uniqueTestId(prefix: "kctest-iso-a")
            let dbId2 = TestHelpers.uniqueTestId(prefix: "kctest-iso-b")

            let creds1 = KeychainService.DatabaseCredentials(
                name: "A", token: "alpha", authUrl: "",
                websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId1, credentials: creds1)

            // ACT — overwrite dbId1
            let updatedCreds1 = KeychainService.DatabaseCredentials(
                name: "A Updated", token: "alpha-v2", authUrl: "",
                websocketUrl: "", httpApiUrl: "", httpApiKey: "", secretKey: ""
            )
            try await service.saveDatabaseCredentials(dbId1, credentials: updatedCreds1)

            // dbId2 was never saved — should return nil
            let loaded2 = try await service.loadDatabaseCredentials(dbId2)

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId1)
            #expect(loaded2 == nil)
        }
    }

    // MARK: - Edge Case Tests

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Empty string fields are stored and retrieved correctly", .tags(.service, .encryption))
        func testEmptyStringFields() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-empty")
            let creds = KeychainService.DatabaseCredentials(
                name: "",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: "",
                secretKey: ""
            )

            // ACT
            try await service.saveDatabaseCredentials(dbId, credentials: creds)
            let loaded = try await service.loadDatabaseCredentials(dbId)

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId)
            #expect(loaded?.name == "")
            #expect(loaded?.token == "")
            #expect(loaded?.secretKey == "")
        }

        @Test("Long field values are stored and retrieved correctly", .tags(.service, .encryption))
        func testLongFieldValues() async throws {
            // ARRANGE
            let service = KeychainService.shared
            let dbId = TestHelpers.uniqueTestId(prefix: "kctest-long")
            let longToken = String(repeating: "abcdef0123456789", count: 16) // 256 chars
            let creds = KeychainService.DatabaseCredentials(
                name: "Long Values DB",
                token: longToken,
                authUrl: "https://very-long-auth-url-that-tests-storage-limits.example.com",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: "",
                secretKey: ""
            )

            // ACT
            try await service.saveDatabaseCredentials(dbId, credentials: creds)
            let loaded = try await service.loadDatabaseCredentials(dbId)

            // ASSERT
            try await service.deleteDatabaseCredentials(dbId)
            #expect(loaded?.token == longToken)
            #expect(loaded?.token.count == 256)
        }
    }
}
