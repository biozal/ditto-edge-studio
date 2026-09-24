import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for MCPToolHandlers.allTools (the tool manifest).
///
/// Tests cover:
/// - Tool count, uniqueness, and non-empty required fields
/// - Specific tool registrations (insert_documents_from_file, execute_dql, create_index)
/// - inputSchema required arrays for key tools
///
/// No server, no database required — reads a static array.
@Suite("MCP Tool Manifest Tests", .tags(.mcp, .mcpTools))
struct MCPToolManifestTests {
    // MARK: - Count & Uniqueness

    @Test(.tags(.mcp, .fast))
    func `All 15 tools are registered`() {
        #expect(MCPToolHandlers.allTools.count == 15)
    }

    @Test(.tags(.mcp, .fast))
    func `No duplicate tool names`() {
        // ARRANGE
        let names = MCPToolHandlers.allTools.map(\.name)

        // ASSERT
        #expect(Set(names).count == names.count)
    }

    // MARK: - Required Fields

    @Test(.tags(.mcp, .fast))
    func `Every tool has a non-empty name`() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.name.isEmpty, "Tool has empty name")
        }
    }

    @Test(.tags(.mcp, .fast))
    func `Every tool has a non-empty description`() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.description.isEmpty, "Tool '\(tool.name)' has empty description")
        }
    }

    @Test(.tags(.mcp, .fast))
    func `Every tool has a non-empty inputSchema`() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.inputSchema.isEmpty, "Tool '\(tool.name)' has empty inputSchema")
        }
    }

    // MARK: - Specific Tool: insert_documents_from_file

    @Test(.tags(.mcp, .fast))
    func `insert_documents_from_file is registered`() {
        let tool = MCPToolHandlers.allTools.first { $0.name == "insert_documents_from_file" }
        #expect(tool != nil)
    }

    @Test(.tags(.mcp, .fast))
    func `insert_documents_from_file has file_path in required`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "insert_documents_from_file" }) else {
            Issue.record("insert_documents_from_file tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("file_path"))
    }

    @Test(.tags(.mcp, .fast))
    func `insert_documents_from_file has collection in required`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "insert_documents_from_file" }) else {
            Issue.record("insert_documents_from_file tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("collection"))
    }

    @Test(.tags(.mcp, .fast))
    func `insert_documents_from_file mode enum has exactly 2 values`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "insert_documents_from_file" }) else {
            Issue.record("insert_documents_from_file tool not found")
            return
        }
        let properties = tool.inputSchema["properties"] as? [String: Any]
        let modeSchema = properties?["mode"] as? [String: Any]
        let enumValues = modeSchema?["enum"] as? [String]

        // ASSERT
        #expect(enumValues?.count == 2)
        #expect(enumValues?.contains("insert") == true)
        #expect(enumValues?.contains("insert_initial") == true)
    }

    // MARK: - Specific Tool: execute_dql

    @Test(.tags(.mcp, .fast))
    func `execute_dql has query in required`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "execute_dql" }) else {
            Issue.record("execute_dql tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("query"))
    }

    // MARK: - Specific Tool: create_index

    @Test(.tags(.mcp, .fast))
    func `create_index has collection and field in required`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "create_index" }) else {
            Issue.record("create_index tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("collection"))
        #expect(required.contains("field"))
    }

    // MARK: - Specific Tool: drop_index

    @Test(.tags(.mcp, .fast))
    func `drop_index has index_name in required`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "drop_index" }) else {
            Issue.record("drop_index tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("index_name"))
    }

    @Test(.tags(.mcp, .fast))
    func `drop_index offers optional collection argument`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "drop_index" }) else {
            Issue.record("drop_index tool not found")
            return
        }
        let properties = tool.inputSchema["properties"] as? [String: Any]
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT — collection is offered but not required
        #expect(properties?["collection"] != nil)
        #expect(!required.contains("collection"))
    }

    // MARK: - Specific Tool: configure_transport

    @Test(.tags(.mcp, .fast))
    func `configure_transport offers the multicast (beta) arguments`() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "configure_transport" }) else {
            Issue.record("configure_transport tool not found")
            return
        }
        let properties = tool.inputSchema["properties"] as? [String: Any]
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT — multicast is offered alongside the other transports, and every
        // parameter stays optional (omitted parameters retain current values).
        #expect(properties?["multicast"] != nil)
        #expect(properties?["multicast_group_address"] != nil)
        #expect(properties?["multicast_port"] != nil)
        #expect(properties?["multicast_interface"] != nil)
        #expect(required.isEmpty)
    }

    // MARK: - Known Tool Names

    @Test(.tags(.mcp, .fast))
    func `All expected tool names are present`() {
        let names = Set(MCPToolHandlers.allTools.map(\.name))
        let expected: Set = [
            "execute_dql",
            "list_databases",
            "get_active_database",
            "list_collections",
            "create_index",
            "drop_index",
            "get_query_metrics",
            "get_sync_status",
            "configure_transport",
            "insert_documents_from_file",
            "set_sync",
            "get_peers",
            "list_indexes",
            "get_app_logs",
            "get_ditto_logs"
        ]
        #expect(names == expected)
    }
}
