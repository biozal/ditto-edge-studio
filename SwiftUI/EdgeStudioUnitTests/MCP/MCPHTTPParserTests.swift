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

    @Test(.tags(.mcp, .fast))
    func `Parses complete GET request`() {
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

    @Test(.tags(.mcp, .fast))
    func `GET request body is empty`() {
        // ARRANGE
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.body.isEmpty == true)
    }

    // MARK: - POST Requests

    @Test(.tags(.mcp, .fast))
    func `Parses complete POST request with body`() {
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

    @Test(.tags(.mcp, .fast))
    func `POST with zero Content-Length has empty body`() {
        // ARRANGE
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request != nil)
        #expect(request?.body.isEmpty == true)
    }

    // MARK: - Chunked Transfer Encoding

    @Test(.tags(.mcp, .fast))
    func `Parses chunked POST body`() {
        // ARRANGE — "hello world" split into two chunks
        let raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request != nil)
        #expect(request?.body == Data("hello world".utf8))
    }

    @Test(.tags(.mcp, .fast))
    func `Parses single-chunk POST body`() {
        // ARRANGE
        let body = "{\"jsonrpc\":\"2.0\"}"
        let raw = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n\(String(body.utf8.count, radix: 16))\r\n\(body)\r\n0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.body == Data(body.utf8))
    }

    @Test(.tags(.mcp, .fast))
    func `Returns nil when chunked body is incomplete`() {
        // ARRANGE — chunk declares 10 bytes, only 3 present, no terminator
        let raw = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\na\r\nabc"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    @Test(.tags(.mcp, .fast))
    func `Returns nil when terminating chunk has not arrived`() {
        // ARRANGE — one complete chunk, but no zero-length terminator yet
        let raw = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    // MARK: - Incomplete Data (must return nil)

    @Test(.tags(.mcp, .fast))
    func `Returns nil for incomplete headers (no CRLF-CRLF)`() {
        // ARRANGE — half a request line, no header terminator
        let raw = "GET /health HTTP/1.1\r\nHost: loc"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    @Test(.tags(.mcp, .fast))
    func `Returns nil when body not yet fully received`() {
        // ARRANGE — Content-Length says 100 bytes, but only 10 bytes of body are present
        let partialBody = "0123456789"
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 100\r\n\r\n\(partialBody)"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request == nil)
    }

    @Test(.tags(.mcp, .fast))
    func `Returns nil for empty data`() {
        // ACT
        let request = MCPHTTPParser.tryParse(Data())

        // ASSERT
        #expect(request == nil)
    }

    // MARK: - Query Parameters

    @Test(.tags(.mcp, .fast))
    func `Parses single query parameter`() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc123 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams["sessionId"] == "abc123")
    }

    @Test(.tags(.mcp, .fast))
    func `Path does not include query string`() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc123 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.path == "/mcp")
    }

    @Test(.tags(.mcp, .fast))
    func `Parses multiple query parameters`() {
        // ARRANGE
        let raw = "GET /mcp?sessionId=abc&version=2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams["sessionId"] == "abc")
        #expect(request?.queryParams["version"] == "2")
    }

    @Test(.tags(.mcp, .fast))
    func `No query string produces empty queryParams`() {
        // ARRANGE
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.queryParams.isEmpty == true)
    }

    // MARK: - Headers

    @Test(.tags(.mcp, .fast))
    func `Parses headers with lowercase keys`() {
        // ARRANGE — send mixed-case header
        let raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 0\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT — keys are normalized to lowercase
        #expect(request?.headers["content-type"] == "application/json")
        #expect(request?.headers["content-length"] == "0")
    }

    @Test(.tags(.mcp, .fast))
    func `Parses OPTIONS method`() {
        // ARRANGE
        let raw = "OPTIONS /mcp HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        // ACT
        let request = MCPHTTPParser.tryParse(data)

        // ASSERT
        #expect(request?.method == "OPTIONS")
    }
}
