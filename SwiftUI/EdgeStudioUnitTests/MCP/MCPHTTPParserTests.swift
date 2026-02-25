import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for MCPHTTPParser.
///
/// Tests cover complete and partial HTTP/1.1 request parsing:
/// - GET requests (no body)
/// - POST requests with body and Content-Length
/// - Query parameter extraction
/// - Case-insensitive header parsing
/// - Incomplete data returning nil (partial headers, partial body)
///
/// No server, no database required — pure Swift logic.
@Suite("MCP HTTP Parser Tests", .tags(.mcp))
struct MCPHTTPParserTests {

    // MARK: - GET Requests

    @Test("Parses complete GET request", .tags(.mcp, .fast))
    func testParsesCompleteGETRequest() {
        // ARRANGE
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request != nil)
        #expect(request?.method == "GET")
        #expect(request?.path == "/health")
    }

    @Test("GET request body is empty", .tags(.mcp, .fast))
    func testGETRequestBodyIsEmpty() {
        // ARRANGE
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.body.isEmpty == true)
    }

    // MARK: - POST Requests

    @Test("Parses complete POST request with body", .tags(.mcp, .fast))
    func testParsesCompletePOSTWithBody() {
        // ARRANGE
        let body = "{\"hello\":\"ok\"}"
        let raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request != nil)
        #expect(request?.method == "POST")
        #expect(request?.path == "/mcp")
        #expect(request?.body == Data(body.utf8))
    }

    @Test("POST with zero Content-Length has empty body", .tags(.mcp, .fast))
    func testPOSTWithZeroContentLengthHasEmptyBody() {
        // ARRANGE
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request != nil)
        #expect(request?.body.isEmpty == true)
    }

    // MARK: - Incomplete Data (must return nil)

    @Test("Returns nil for incomplete headers (no CRLF-CRLF)", .tags(.mcp, .fast))
    func testReturnsNilForIncompleteHeaders() {
        // ARRANGE — half a request line, no header terminator
        let raw = "GET /health HTTP/1.1\r\nHost: loc"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    @Test("Returns nil when body not yet fully received", .tags(.mcp, .fast))
    func testReturnsNilWhenBodyIncomplete() {
        // ARRANGE — Content-Length says 100 bytes, but only 10 bytes of body are present
        let partialBody = "0123456789"
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 100\r\n\r\n\(partialBody)"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    @Test("Returns nil for empty data", .tags(.mcp, .fast))
    func testReturnsNilForEmptyData() {
        // ACT
        let request = MCPHTTPParser.tryParse(Data())

        // ASSERT
        #expect(request == nil)
    }

    // MARK: - Query Parameters

    @Test("Parses single query parameter", .tags(.mcp, .fast))
    func testParsesSingleQueryParameter() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc123 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams["sessionId"] == "abc123")
    }

    @Test("Path does not include query string", .tags(.mcp, .fast))
    func testPathDoesNotIncludeQueryString() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc123 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.path == "/mcp")
    }

    @Test("Parses multiple query parameters", .tags(.mcp, .fast))
    func testParsesMultipleQueryParameters() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc&version=2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams["sessionId"] == "abc")
        #expect(request?.queryParams["version"] == "2")
    }

    @Test("No query string produces empty queryParams", .tags(.mcp, .fast))
    func testNoQueryStringProducesEmptyParams() {
        // ARRANGE
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams.isEmpty == true)
    }

    // MARK: - Headers

    @Test("Parses headers with lowercase keys", .tags(.mcp, .fast))
    func testParsesHeadersAsLowercased() {
        // ARRANGE — send mixed-case header
        let raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT — keys are normalized to lowercase
        #expect(request?.headers["content-type"] == "application/json")
        #expect(request?.headers["content-length"] == "0")
    }

    @Test("Parses OPTIONS method", .tags(.mcp, .fast))
    func testParsesOPTIONSMethod() {
        // ARRANGE
        let raw = "OPTIONS /mcp HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.method == "OPTIONS")
    }
}
