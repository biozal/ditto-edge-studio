import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for MCPJSONRPCHandler.
///
/// Tests cover routing, protocol compliance, error codes, and ID round-tripping.
/// Calls MCPJSONRPCHandler.handle(_ body: Data) directly — no server, no database.
///
/// Some tool calls (e.g. execute_dql) will fail with "no active database" errors
/// at the handler level, which is expected and still validates dispatch.
///
/// Serialized because MCPToolHandlers.execute is async and some shared state
/// in the app (DittoManager) is a singleton.
@Suite("MCP JSON-RPC Handler Tests", .serialized, .tags(.mcp))
struct MCPJSONRPCHandlerTests {

    // MARK: - Helpers

    private func makeBody(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }

    private func parseResponse(_ responseJSON: String) -> [String: Any]? {
        guard let data = responseJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    // MARK: - Protocol Handshake

    @Test("initialize returns protocol version 2024-11-05", .tags(.mcp, .fast))
    func testInitializeReturnsProtocolVersion() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]])

        // ACT
        let (responseJSON, isNotification) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let result = response?["result"] as? [String: Any]

        // ASSERT
        #expect(isNotification == false)
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
    }

    @Test("initialize returns serverInfo with name ditto-edge-studio", .tags(.mcp, .fast))
    func testInitializeReturnsServerInfo() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let result = response?["result"] as? [String: Any]
        let serverInfo = result?["serverInfo"] as? [String: Any]

        // ASSERT
        #expect(serverInfo?["name"] as? String == "ditto-edge-studio")
    }

    // MARK: - tools/list

    @Test("tools/list returns 15 tools", .tags(.mcp, .fast))
    func testToolsListReturns10Tools() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let result = response?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]

        // ASSERT
        #expect(tools?.count == 15)
    }

    @Test("tools/list each tool has name, description, inputSchema", .tags(.mcp, .fast))
    func testToolsListEachToolHasRequiredFields() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let tools = (response?["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []

        // ASSERT
        for tool in tools {
            #expect(tool["name"] as? String != nil)
            #expect(tool["description"] as? String != nil)
            #expect(tool["inputSchema"] as? [String: Any] != nil)
        }
    }

    // MARK: - Notifications

    @Test("Notification (no id) returns isNotification = true", .tags(.mcp, .fast))
    func testNotificationReturnsIsNotificationTrue() async {
        // ARRANGE — notification has no "id" field
        let body = makeBody(["jsonrpc": "2.0", "method": "notifications/initialized"])

        // ACT
        let (responseJSON, isNotification) = await MCPJSONRPCHandler.handle(body)

        // ASSERT
        #expect(isNotification == true)
        #expect(responseJSON.isEmpty)
    }

    // MARK: - Error Cases

    @Test("Unknown method returns error code -32601", .tags(.mcp, .fast))
    func testUnknownMethodReturnsError32601() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "nonexistent"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let error = response?["error"] as? [String: Any]

        // ASSERT
        #expect(error?["code"] as? Int == -32601)
    }

    @Test("Empty body returns parse error -32700", .tags(.mcp, .fast))
    func testEmptyBodyReturnsParseError() async {
        // ACT
        let (responseJSON, isNotification) = await MCPJSONRPCHandler.handle(Data())
        let response = parseResponse(responseJSON)
        let error = response?["error"] as? [String: Any]

        // ASSERT
        #expect(isNotification == false)
        #expect(error?["code"] as? Int == -32700)
    }

    @Test("Malformed JSON returns parse error -32700", .tags(.mcp, .fast))
    func testMalformedJSONReturnsParseError() async {
        // ARRANGE
        let body = Data("not json".utf8)

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let error = response?["error"] as? [String: Any]

        // ASSERT
        #expect(error?["code"] as? Int == -32700)
    }

    @Test("tools/call with missing name returns error -32602", .tags(.mcp, .fast))
    func testToolsCallMissingNameReturnsError32602() async {
        // ARRANGE — params dict has no "name" key
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [:]])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let error = response?["error"] as? [String: Any]

        // ASSERT
        #expect(error?["code"] as? Int == -32602)
    }

    @Test("tools/call with unknown tool name returns isError in content", .tags(.mcp, .fast))
    func testToolsCallUnknownToolReturnsIsError() async {
        // ARRANGE
        let body = makeBody([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "does_not_exist"]
        ])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)
        let result = response?["result"] as? [String: Any]

        // ASSERT
        #expect(result?["isError"] as? Bool == true)
    }

    // MARK: - ID Round-Tripping

    @Test("String id is round-tripped correctly", .tags(.mcp, .fast))
    func testStringIdIsRoundTripped() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": "my-id", "method": "tools/list"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)

        // ASSERT
        #expect(response?["id"] as? String == "my-id")
    }

    @Test("Integer id is round-tripped correctly", .tags(.mcp, .fast))
    func testIntegerIdIsRoundTripped() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 42, "method": "tools/list"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)

        // ASSERT
        #expect(response?["id"] as? Int == 42)
    }

    // MARK: - Response Validity

    @Test("Every valid request produces valid JSON response", .tags(.mcp, .fast))
    func testEveryValidRequestProducesValidJSON() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)

        // ASSERT
        let responseData = responseJSON.data(using: .utf8) ?? Data()
        let parsed = try? JSONSerialization.jsonObject(with: responseData)
        #expect(parsed != nil)
    }

    @Test("Response always contains jsonrpc 2.0 field", .tags(.mcp, .fast))
    func testResponseAlwaysContainsJsonRPC20() async {
        // ARRANGE
        let body = makeBody(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]])

        // ACT
        let (responseJSON, _) = await MCPJSONRPCHandler.handle(body)
        let response = parseResponse(responseJSON)

        // ASSERT
        #expect(response?["jsonrpc"] as? String == "2.0")
    }
}
