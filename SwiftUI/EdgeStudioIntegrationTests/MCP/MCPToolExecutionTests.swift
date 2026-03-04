import Testing
@testable import Ditto_Edge_Studio

/// Integration tests for MCP tool dispatch over HTTP.
///
/// Tests exercise the full stack: HTTP → JSON-RPC → tool handler.
/// Most tools return "no active database" errors because no Ditto
/// instance is selected in the test environment — that IS the expected
/// and correct behaviour, so assertions check for those error messages.
///
/// All tests are serialized because only one server can run at a time.
@Suite("MCP Tool Execution Tests", .serialized, .tags(.mcp, .mcpTools))
struct MCPToolExecutionTests {

    // MARK: - Protocol Handshake

    @Test("initialize over HTTP returns protocolVersion 2024-11-05", .tags(.mcp, .mcpTools))
    func testInitializeOverHTTP() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.post(method: "initialize", params: [:])
            let result = response["result"] as? [String: Any]

            // ASSERT
            #expect(result?["protocolVersion"] as? String == "2024-11-05")
        }
    }

    @Test("tools/list over HTTP returns 15 tools", .tags(.mcp, .mcpTools))
    func testToolsListOverHTTP() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.post(method: "tools/list")
            let result = response["result"] as? [String: Any]
            let tools = result?["tools"] as? [[String: Any]]

            // ASSERT
            #expect(tools?.count == 15)
        }
    }

    // MARK: - execute_dql error paths

    @Test("execute_dql with no query argument returns missing argument error", .tags(.mcp, .mcpTools))
    func testExecuteDQLMissingQuery() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("execute_dql", arguments: [:])

            // ASSERT
            #expect(text.contains("Missing required argument: query"))
        }
    }

    @Test("execute_dql with empty query string returns missing argument error", .tags(.mcp, .mcpTools))
    func testExecuteDQLEmptyQuery() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("execute_dql", arguments: ["query": ""])

            // ASSERT
            #expect(text.contains("Missing required argument: query"))
        }
    }

    // MARK: - No-database error paths

    @Test("get_active_database with no active DB returns no active database error", .tags(.mcp, .mcpTools))
    func testGetActiveDatabaseNoActiveDB() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("get_active_database")

            // ASSERT
            #expect(text.contains("No active database"))
        }
    }

    @Test("get_sync_status with no active DB returns no active database error", .tags(.mcp, .mcpTools))
    func testGetSyncStatusNoActiveDB() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("get_sync_status")

            // ASSERT
            #expect(text.contains("No active database"))
        }
    }

    @Test("configure_transport with no active DB returns no active database error", .tags(.mcp, .mcpTools))
    func testConfigureTransportNoActiveDB() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("configure_transport", arguments: ["lan": true])

            // ASSERT
            #expect(text.contains("No active database"))
        }
    }

    // MARK: - create_index / drop_index argument validation

    @Test("create_index with no collection argument returns missing argument error", .tags(.mcp, .mcpTools))
    func testCreateIndexMissingCollection() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("create_index", arguments: ["field": "name"])

            // ASSERT
            #expect(text.contains("Missing required argument: collection"))
        }
    }

    @Test("create_index with no field argument returns missing argument error", .tags(.mcp, .mcpTools))
    func testCreateIndexMissingField() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("create_index", arguments: ["collection": "tasks"])

            // ASSERT
            #expect(text.contains("Missing required argument: field"))
        }
    }

    @Test("drop_index with no index_name argument returns missing argument error", .tags(.mcp, .mcpTools))
    func testDropIndexMissingIndexName() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("drop_index", arguments: [:])

            // ASSERT
            #expect(text.contains("Missing required argument: index_name"))
        }
    }

    // MARK: - list_databases (reads SQLCipher, no Ditto needed)

    @Test("list_databases returns a result (empty array or JSON) without error", .tags(.mcp, .mcpTools))
    func testListDatabasesReturnsResult() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.post(method: "tools/call", params: [
                "name": "list_databases", "arguments": [:]
            ])
            let result = response["result"] as? [String: Any]

            // ASSERT — should have result content, no isError flag
            #expect(result != nil)
            #expect(result?["isError"] as? Bool != true)
        }
    }

    // MARK: - list_indexes

    @Test("list_indexes returns a valid JSON array", .tags(.mcp, .mcpTools))
    func testListIndexesReturnsArray() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.post(method: "tools/call", params: [
                "name": "list_indexes", "arguments": [:]
            ])
            let result = response["result"] as? [String: Any]

            // ASSERT — no error flag (empty array returned when no database is active)
            #expect(result != nil)
            #expect(result?["isError"] as? Bool != true)

            // Verify the content text is a valid JSON array
            let text = try await MCPTestHelpers.callTool("list_indexes")
            let textData = text.data(using: .utf8) ?? Data()
            let parsed = try? JSONSerialization.jsonObject(with: textData)
            #expect(parsed is [Any])
        }
    }

    // MARK: - Unknown tool

    @Test("Unknown tool name returns unknown tool error in content", .tags(.mcp, .mcpTools))
    func testUnknownToolName() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool("fake_tool")

            // ASSERT
            #expect(text.contains("Unknown tool: fake_tool"))
        }
    }
}
