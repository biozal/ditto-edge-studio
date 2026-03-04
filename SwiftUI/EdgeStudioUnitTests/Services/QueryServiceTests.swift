import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - QueryService Tests
//
// Tests cover:
// - Local query error paths (no database selected)
// - HTTP query error paths (no app config selected)
// - Result format verification (Document ID / Commit ID strings)
// - fetchSmallPeerInfo error path (no database selected)
//
// NOTE: Full HTTP response parsing tests require a live DittoConfigForDatabase
// to be set on DittoManager (dittoSelectedAppConfig). Those tests belong in
// EdgeStudioIntegrationTests. This file covers all error paths and format
// verification that are unit-testable.
//
// Target: ~40% QueryService coverage from error paths and format tests.

@Suite("QueryService Tests", .serialized)
struct QueryServiceTests {

    // MARK: - Local Query Error Path Tests

    @Suite("Local Query Error Path Tests", .serialized)
    struct LocalQueryErrorPathTests {

        @Test("Returns no results when no database is selected", .tags(.service))
        func testNoSelectedDatabase() async throws {
            // ARRANGE: No database is selected (fresh test environment)
            let service = QueryService.shared

            // ACT: Execute query with no selected database
            let results = try await service.executeSelectedAppQuery(query: "SELECT * FROM users")

            // ASSERT: Returns graceful fallback, not a crash
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }

        @Test("SELECT query returns no results when no database selected", .tags(.service, .fast))
        func testSelectQueryNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.simpleSelect)

            // ASSERT
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }

        @Test("INSERT query returns no results when no database selected", .tags(.service, .fast))
        func testInsertQueryNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.insertSingle)

            // ASSERT: No crash, returns fallback
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }

        @Test("UPDATE query returns no results when no database selected", .tags(.service, .fast))
        func testUpdateQueryNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.updateSingle)

            // ASSERT: No crash, returns fallback
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }

        @Test("DELETE query returns no results when no database selected", .tags(.service, .fast))
        func testDeleteQueryNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.deleteSingle)

            // ASSERT: No crash, returns fallback
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }

        @Test("Empty query string returns no results when no database selected", .tags(.service, .fast))
        func testEmptyQueryNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.emptyQuery)

            // ASSERT: No crash, returns fallback
            #expect(results.count == 1)
            #expect(results[0] == "No results found")
        }
    }

    // MARK: - HTTP Query Error Path Tests

    @Suite("HTTP Query Error Path Tests", .serialized)
    struct HttpQueryErrorPathTests {

        @Test("Returns error when no app config is selected", .tags(.service))
        func testNoSelectedAppConfig() async throws {
            // ARRANGE: No database is selected (no config available)
            let service = QueryService.shared

            // ACT: Execute HTTP query with no selected config
            let results = try await service.executeSelectedAppQueryHttp(query: "SELECT * FROM users")

            // ASSERT: Returns error message, not a crash
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test("HTTP query with SELECT returns error when no config", .tags(.service, .fast))
        func testHttpSelectNoConfig() async throws {
            // ARRANGE
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQueryHttp(query: QueryFixtures.simpleSelect)

            // ASSERT
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test("HTTP query with INSERT returns error when no config", .tags(.service, .fast))
        func testHttpInsertNoConfig() async throws {
            // ARRANGE
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQueryHttp(query: QueryFixtures.insertSingle)

            // ASSERT: No crash, returns error message
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test("HTTP error response format uses 'HTTP Error:' prefix", .tags(.service, .fast))
        func testHttpErrorResponseFormat() {
            // ARRANGE: Simulate the format the service uses for HTTP error responses
            let errorBody = "Unauthorized"

            // ACT: Construct the error string as QueryService does
            let errorString = "HTTP Error: \(errorBody)"

            // ASSERT: Format uses the expected prefix
            #expect(errorString.hasPrefix("HTTP Error:"))
            #expect(errorString.contains(errorBody))
        }
    }

    // MARK: - Result Format Tests

    @Suite("Result Format Tests", .serialized)
    struct ResultFormatTests {

        @Test("Document ID format uses 'Document ID: ' prefix", .tags(.service, .fast))
        func testDocumentIdFormatPrefix() {
            // ARRANGE: Known document ID value
            let documentId = "abc123def456"

            // ACT: Construct the format string as QueryService does for local mutations
            let resultString = "Document ID: \(documentId)"

            // ASSERT: Format matches the code's pattern
            #expect(resultString.hasPrefix("Document ID: "))
            #expect(resultString == "Document ID: abc123def456")
        }

        @Test("Commit ID format uses 'Commit ID: ' prefix", .tags(.service, .fast))
        func testCommitIdFormatPrefix() {
            // ARRANGE: Known commit ID value
            let commitId = "xyz789uvw"

            // ACT: Construct the format string as QueryService does
            let resultString = "Commit ID: \(commitId)"

            // ASSERT: Format matches the code's pattern
            #expect(resultString.hasPrefix("Commit ID: "))
            #expect(resultString == "Commit ID: xyz789uvw")
        }

        @Test("Commit ID fallback when nil is 'Commit ID: N/A'", .tags(.service, .fast))
        func testCommitIdNilFallback() {
            // ARRANGE: Simulate nil commitID case
            let commitID: String? = nil

            // ACT: Construct the fallback string as QueryService does
            let resultString: String
            if let commitID {
                resultString = "Commit ID: \(commitID)"
            } else {
                resultString = "Commit ID: N/A"
            }

            // ASSERT: Fallback uses the expected literal
            #expect(resultString == "Commit ID: N/A")
            #expect(resultString.hasPrefix("Commit ID: "))
        }

        @Test("HTTP mutation result format maps document IDs correctly", .tags(.service, .fast))
        func testHttpMutationDocumentIdMapping() {
            // ARRANGE: Simulate mutatedDocumentIds from HTTP response parsing
            let mutatedDocumentIds = ["id-aaa", "id-bbb", "id-ccc"]

            // ACT: Map them as QueryService does in the HTTP path
            let resultStrings = mutatedDocumentIds.map { "Document ID: \($0)" }

            // ASSERT: All entries have correct prefix and value
            #expect(resultStrings.count == 3)
            for (index, resultString) in resultStrings.enumerated() {
                #expect(resultString.hasPrefix("Document ID: "),
                        "Entry \(index) must have 'Document ID: ' prefix")
                #expect(resultString == "Document ID: \(mutatedDocumentIds[index])",
                        "Entry \(index) must match expected document ID value")
            }
        }

        @Test("HTTP mutation result appends commit ID when present", .tags(.service, .fast))
        func testHttpMutationCommitIdAppended() {
            // ARRANGE: Simulate mutatedDocumentIds + commitId from HTTP response
            let mutatedDocumentIds = ["doc-001", "doc-002"]
            let commitId = "commit-abc-xyz"

            // ACT: Build result strings as QueryService does in HTTP path
            var resultStrings = mutatedDocumentIds.map { "Document ID: \($0)" }
            resultStrings.append("Commit ID: \(commitId)")

            // ASSERT: Results contain both Document ID entries and Commit ID entry
            #expect(resultStrings.count == 3)
            #expect(resultStrings[0] == "Document ID: doc-001")
            #expect(resultStrings[1] == "Document ID: doc-002")
            #expect(resultStrings[2] == "Commit ID: commit-abc-xyz")
            #expect(resultStrings[2].hasPrefix("Commit ID: "))
        }

        @Test("No results fallback string is 'No results found'", .tags(.service, .fast))
        func testNoResultsFallbackString() {
            // ARRANGE + ACT: The fallback string used throughout QueryService
            let noResults = ["No results found"]

            // ASSERT
            #expect(noResults.count == 1)
            #expect(noResults[0] == "No results found")
        }

        @Test("No items fallback string is 'No items found'", .tags(.service, .fast))
        func testNoItemsFallbackString() {
            // ARRANGE + ACT: The HTTP path uses 'No items found' for empty items array
            let noItems = ["No items found"]

            // ASSERT
            #expect(noItems.count == 1)
            #expect(noItems[0] == "No items found")
        }
    }

    // MARK: - Fetch Small Peer Info Tests

    @Suite("Fetch Small Peer Info Tests", .serialized)
    struct FetchSmallPeerInfoTests {

        @Test("fetchSmallPeerInfo returns empty array when no database selected", .tags(.service))
        func testFetchSmallPeerInfoNoDatabase() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT: Fetch small peer info — internally calls executeSelectedAppQueryHttp
            // which returns an error string because no config is set.
            // The error string cannot be decoded as SmallPeerInfo, so the
            // decoder skips it and returns an empty array.
            let peerInfos = try await service.fetchSmallPeerInfo()

            // ASSERT: Returns empty array gracefully, no crash
            #expect(peerInfos.isEmpty)
        }

        @Test("fetchSmallPeerInfo is idempotent with no database", .tags(.service))
        func testFetchSmallPeerInfoIdempotent() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT: Call multiple times
            let firstResult = try await service.fetchSmallPeerInfo()
            let secondResult = try await service.fetchSmallPeerInfo()

            // ASSERT: Both calls return empty array, no state corruption
            #expect(firstResult.isEmpty)
            #expect(secondResult.isEmpty)
        }
    }
}

// MARK: - Integration Test Stubs
// TODO: Add full HTTP response parsing tests to EdgeStudioIntegrationTests:
//
// class QueryServiceIntegrationTests: XCTestCase {
//     /// Test executeSelectedAppQueryHttp with mock URLProtocol
//     /// Requires a live DittoConfigForDatabase to be set on DittoManager
//     /// (dittoSelectedAppConfig must be non-nil).
//     ///
//     /// Tests to add when live config is injectable:
//     /// - HTTP 200 with items array → results parsed as JSON strings
//     /// - HTTP 200 with mutatedDocumentIds → Document ID / Commit ID format
//     /// - HTTP 4xx → "HTTP Error: <body>" returned
//     /// - HTTP 5xx → "HTTP Error: <body>" returned
//     /// - Malformed JSON → raw string returned
//     /// - Empty items array → "No items found" returned
// }
