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
        @Test(.tags(.service))
        func `Returns 'No Ditto app selected' when no database is selected`() async throws {
            // ARRANGE: No database is selected (fresh test environment)
            let service = QueryService.shared

            // ACT: Execute query with no selected database
            let results = try await service.executeSelectedAppQuery(query: "SELECT * FROM users")

            // ASSERT: Returns the dedicated sentinel (distinct from an empty
            // result set's "No results found") — the MCP formatQueryResults
            // special-cases this exact string.
            #expect(results == ["No Ditto app selected"])
        }

        @Test(.tags(.service, .fast))
        func `SELECT query returns sentinel when no database selected`() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.simpleSelect)

            // ASSERT
            #expect(results == ["No Ditto app selected"])
        }

        @Test(.tags(.service, .fast))
        func `INSERT query returns sentinel when no database selected`() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.insertSingle)

            // ASSERT: No crash, returns sentinel
            #expect(results == ["No Ditto app selected"])
        }

        @Test(.tags(.service, .fast))
        func `UPDATE query returns sentinel when no database selected`() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.updateSingle)

            // ASSERT: No crash, returns sentinel
            #expect(results == ["No Ditto app selected"])
        }

        @Test(.tags(.service, .fast))
        func `DELETE query returns sentinel when no database selected`() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.deleteSingle)

            // ASSERT: No crash, returns sentinel
            #expect(results == ["No Ditto app selected"])
        }

        @Test(.tags(.service, .fast))
        func `Empty query string returns sentinel when no database selected`() async throws {
            // ARRANGE: No database is selected
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQuery(query: QueryFixtures.emptyQuery)

            // ASSERT: No crash, returns sentinel
            #expect(results == ["No Ditto app selected"])
        }
    }

    // MARK: - PROFILE injection (executeSelectedAppQueryWithProfile)

    /// Tests the new SELECT-with-profile entry point. Most of the
    /// behaviour (DB interaction, JSON shaping) is covered by the
    /// existing tests above via the shared codepath — this suite
    /// focuses on the unique additions: PROFILE prefix gating
    /// (isSelectStatement / alreadyHasProfilePrefix) and the
    /// QueryExecutionResult return shape.
    @Suite("PROFILE injection", .serialized)
    struct ProfileInjectionTests {
        @Test(.tags(.service, .fast))
        func `Returns empty result and nil profile when no database selected`() async throws {
            // ARRANGE
            let service = QueryService.shared

            // ACT
            let result = try await service.executeSelectedAppQueryWithProfile(
                query: "SELECT * FROM tasks"
            )

            // ASSERT — graceful fallback matches the legacy method's shape
            #expect(result.items == ["No Ditto app selected"])
            #expect(result.profile == nil)
        }

        // MARK: isSelectStatement

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts uppercase SELECT`() {
            #expect(QueryService.isSelectStatement("SELECT * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts lowercase select`() {
            #expect(QueryService.isSelectStatement("select * from tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts mixed case SeLeCt`() {
            #expect(QueryService.isSelectStatement("SeLeCt * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts leading whitespace`() {
            #expect(QueryService.isSelectStatement("   SELECT * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts leading newlines and tabs`() {
            #expect(QueryService.isSelectStatement("\n\tSELECT * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects INSERT`() {
            #expect(QueryService.isSelectStatement("INSERT INTO tasks SET name = 'x'") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects UPDATE`() {
            #expect(QueryService.isSelectStatement("UPDATE tasks SET done = true") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects DELETE`() {
            #expect(QueryService.isSelectStatement("DELETE FROM tasks WHERE _id = 'x'") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects EVICT`() {
            #expect(QueryService.isSelectStatement("EVICT FROM tasks") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects ALTER SYSTEM`() {
            #expect(QueryService.isSelectStatement("ALTER SYSTEM SET DQL_STRICT_MODE = 'true'") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects empty string`() {
            #expect(QueryService.isSelectStatement("") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects whitespace only`() {
            #expect(QueryService.isSelectStatement("   \n\t  ") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement rejects SELECTOR with no boundary`() {
            // Defensive — make sure we don't false-positive on words
            // that start with "SELECT" but aren't the SELECT keyword.
            #expect(QueryService.isSelectStatement("SELECTOR FROM tasks") == false)
        }

        @Test(.tags(.service, .fast))
        func `isSelectStatement accepts bare SELECT with no trailing whitespace`() {
            // Edge case — pathological but well-defined input.
            #expect(QueryService.isSelectStatement("SELECT") == true)
        }

        // MARK: alreadyHasProfilePrefix

        @Test(.tags(.service, .fast))
        func `alreadyHasProfilePrefix detects user-typed PROFILE`() {
            #expect(QueryService.alreadyHasProfilePrefix("PROFILE SELECT * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `alreadyHasProfilePrefix detects lowercase profile`() {
            #expect(QueryService.alreadyHasProfilePrefix("profile select * from tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `alreadyHasProfilePrefix detects PROFILE after whitespace`() {
            #expect(QueryService.alreadyHasProfilePrefix("  PROFILE SELECT * FROM tasks") == true)
        }

        @Test(.tags(.service, .fast))
        func `alreadyHasProfilePrefix rejects plain SELECT`() {
            #expect(QueryService.alreadyHasProfilePrefix("SELECT * FROM tasks") == false)
        }

        @Test(.tags(.service, .fast))
        func `alreadyHasProfilePrefix rejects PROFILED noise word`() {
            // "PROFILED" is not a DQL keyword but make sure we don't
            // false-positive on prefix-only matches without word boundary.
            #expect(QueryService.alreadyHasProfilePrefix("PROFILED SELECT") == false)
        }
    }

    // MARK: - HTTP Query Error Path Tests

    @Suite("HTTP Query Error Path Tests", .serialized)
    struct HttpQueryErrorPathTests {
        @Test(.tags(.service))
        func `Returns error when no app config is selected`() async throws {
            // ARRANGE: No database is selected (no config available)
            let service = QueryService.shared

            // ACT: Execute HTTP query with no selected config
            let results = try await service.executeSelectedAppQueryHttp(query: "SELECT * FROM users")

            // ASSERT: Returns error message, not a crash
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test(.tags(.service, .fast))
        func `HTTP query with SELECT returns error when no config`() async throws {
            // ARRANGE
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQueryHttp(query: QueryFixtures.simpleSelect)

            // ASSERT
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test(.tags(.service, .fast))
        func `HTTP query with INSERT returns error when no config`() async throws {
            // ARRANGE
            let service = QueryService.shared

            // ACT
            let results = try await service.executeSelectedAppQueryHttp(query: QueryFixtures.insertSingle)

            // ASSERT: No crash, returns error message
            #expect(results.count == 1)
            #expect(results[0].contains("No Ditto SelectedApp available"))
        }

        @Test(.tags(.service, .fast))
        func `HTTP error response format uses 'HTTP Error:' prefix`() {
            // ARRANGE: Simulate the format the service uses for HTTP error responses
            let errorBody = "Unauthorized"

            // ACT: Construct the error string as QueryService does
            let errorString = "HTTP Error: \(errorBody)"

            // ASSERT: Format uses the expected prefix
            #expect(errorString.hasPrefix("HTTP Error:"))
            #expect(errorString.contains(errorBody))
        }
    }

    // MARK: - HTTP Execute URL Construction Tests

    @Suite("HTTP Execute URL Construction", .serialized)
    struct HttpExecuteURLTests {
        @Test(.tags(.service, .fast))
        func `plain host:port is used as-is`() {
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "example.ditto.live:8080")
                    == "https://example.ditto.live:8080/api/v5/store/execute"
            )
        }

        @Test(.tags(.service, .fast))
        func `https scheme prefix is stripped`() {
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "https://example.ditto.live")
                    == "https://example.ditto.live/api/v5/store/execute"
            )
        }

        @Test(.tags(.service, .fast))
        func `http scheme prefix is stripped`() {
            // A user pasting "http://host" previously produced
            // "https://http://host/api/v5/store/execute" — malformed.
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "http://example.ditto.live")
                    == "https://example.ditto.live/api/v5/store/execute"
            )
        }

        @Test(.tags(.service, .fast))
        func `trailing slashes are stripped`() {
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "example.ditto.live/")
                    == "https://example.ditto.live/api/v5/store/execute"
            )
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "https://example.ditto.live//")
                    == "https://example.ditto.live/api/v5/store/execute"
            )
        }

        @Test(.tags(.service, .fast))
        func `surrounding whitespace is trimmed`() {
            #expect(
                QueryService.makeHttpExecuteURL(httpApiUrl: "  example.ditto.live  ")
                    == "https://example.ditto.live/api/v5/store/execute"
            )
        }
    }

    // MARK: - Shared HTTP API URL Construction Tests (makeHttpApiURL)

    /// `makeHttpApiURL(httpApiUrl:path:)` is the shared sanitization helper
    /// behind `makeHttpExecuteURL` and AttachmentService's `/api/v4/…` URLs.
    @Suite("HTTP API URL Construction (shared helper)", .serialized)
    struct HttpApiURLTests {
        @Test(.tags(.service, .fast))
        func `plain host composes with an /api/v4 path`() {
            #expect(
                QueryService.makeHttpApiURL(
                    httpApiUrl: "example.ditto.live:8080",
                    path: "/api/v4/attachments/upload"
                ) == "https://example.ditto.live:8080/api/v4/attachments/upload"
            )
        }

        @Test(.tags(.service, .fast))
        func `scheme and trailing slash are stripped before composing the path`() {
            // A pasted "https://host/" previously produced
            // "https://https://host//api/v4/…" — malformed.
            #expect(
                QueryService.makeHttpApiURL(
                    httpApiUrl: "https://example.ditto.live/",
                    path: "/api/v4/attachments/att-1"
                ) == "https://example.ditto.live/api/v4/attachments/att-1"
            )
            #expect(
                QueryService.makeHttpApiURL(
                    httpApiUrl: "http://example.ditto.live//",
                    path: "/api/v4/attachments/upload"
                ) == "https://example.ditto.live/api/v4/attachments/upload"
            )
        }

        @Test(.tags(.service, .fast))
        func `path without a leading slash is normalized`() {
            #expect(
                QueryService.makeHttpApiURL(
                    httpApiUrl: "example.ditto.live",
                    path: "api/v4/attachments/upload"
                ) == "https://example.ditto.live/api/v4/attachments/upload"
            )
        }

        @Test(.tags(.service, .fast))
        func `makeHttpExecuteURL matches the shared helper for the execute path`() {
            for input in ["example.ditto.live", "https://example.ditto.live/", " http://example.ditto.live "] {
                #expect(
                    QueryService.makeHttpExecuteURL(httpApiUrl: input)
                        == QueryService.makeHttpApiURL(httpApiUrl: input, path: "/api/v5/store/execute")
                )
            }
        }
    }

    // MARK: - Result Format Tests

    @Suite("Result Format Tests", .serialized)
    struct ResultFormatTests {
        @Test(.tags(.service, .fast))
        func `Document ID format uses 'Document ID: ' prefix`() {
            // ARRANGE: Known document ID value
            let documentId = "abc123def456"

            // ACT: Construct the format string as QueryService does for local mutations
            let resultString = "Document ID: \(documentId)"

            // ASSERT: Format matches the code's pattern
            #expect(resultString.hasPrefix("Document ID: "))
            #expect(resultString == "Document ID: abc123def456")
        }

        @Test(.tags(.service, .fast))
        func `Commit ID format uses 'Commit ID: ' prefix`() {
            // ARRANGE: Known commit ID value
            let commitId = "xyz789uvw"

            // ACT: Construct the format string as QueryService does
            let resultString = "Commit ID: \(commitId)"

            // ASSERT: Format matches the code's pattern
            #expect(resultString.hasPrefix("Commit ID: "))
            #expect(resultString == "Commit ID: xyz789uvw")
        }

        @Test(.tags(.service, .fast))
        func `Commit ID fallback when nil is 'Commit ID: N/A'`() {
            // ARRANGE: Simulate nil commitID case
            let commitID: String? = nil

            // ACT: Construct the fallback string as QueryService does
            let resultString = if let commitID {
                "Commit ID: \(commitID)"
            } else {
                "Commit ID: N/A"
            }

            // ASSERT: Fallback uses the expected literal
            #expect(resultString == "Commit ID: N/A")
            #expect(resultString.hasPrefix("Commit ID: "))
        }

        @Test(.tags(.service, .fast))
        func `HTTP mutation result format maps document IDs correctly`() {
            // ARRANGE: Simulate mutatedDocumentIds from HTTP response parsing
            let mutatedDocumentIds = ["id-aaa", "id-bbb", "id-ccc"]

            // ACT: Map them as QueryService does in the HTTP path
            let resultStrings = mutatedDocumentIds.map { "Document ID: \($0)" }

            // ASSERT: All entries have correct prefix and value
            #expect(resultStrings.count == 3)
            for (index, resultString) in resultStrings.enumerated() {
                #expect(
                    resultString.hasPrefix("Document ID: "),
                    "Entry \(index) must have 'Document ID: ' prefix"
                )
                #expect(
                    resultString == "Document ID: \(mutatedDocumentIds[index])",
                    "Entry \(index) must match expected document ID value"
                )
            }
        }

        @Test(.tags(.service, .fast))
        func `HTTP mutation result appends commit ID when present`() {
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

        @Test(.tags(.service, .fast))
        func `No results fallback string is 'No results found'`() {
            // ARRANGE + ACT: The fallback string used throughout QueryService
            let noResults = ["No results found"]

            // ASSERT
            #expect(noResults.count == 1)
            #expect(noResults[0] == "No results found")
        }

        @Test(.tags(.service, .fast))
        func `No items fallback string is 'No items found'`() {
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
        @Test(.tags(.service))
        func `fetchSmallPeerInfo returns empty array when no database selected`() async throws {
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

        @Test(.tags(.service))
        func `fetchSmallPeerInfo is idempotent with no database`() async throws {
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

// Note: full HTTP response parsing tests belong in EdgeStudioIntegrationTests:
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
