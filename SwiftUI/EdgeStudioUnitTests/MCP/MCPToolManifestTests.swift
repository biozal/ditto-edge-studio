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

    @Test("All 10 tools are registered", .tags(.mcp, .fast))
    func testAllTenToolsRegistered() {
        #expect(MCPToolHandlers.allTools.count == 10)
    }

    @Test("No duplicate tool names", .tags(.mcp, .fast))
    func testNoDuplicateToolNames() {
        // ARRANGE
        let names = MCPToolHandlers.allTools.map(\.name)

        // ASSERT
        #expect(Set(names).count == names.count)
    }

    // MARK: - Required Fields

    @Test("Every tool has a non-empty name", .tags(.mcp, .fast))
    func testEveryToolHasNonEmptyName() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.name.isEmpty, "Tool has empty name")
        }
    }

    @Test("Every tool has a non-empty description", .tags(.mcp, .fast))
    func testEveryToolHasNonEmptyDescription() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.description.isEmpty, "Tool '\(tool.name)' has empty description")
        }
    }

    @Test("Every tool has a non-empty inputSchema", .tags(.mcp, .fast))
    func testEveryToolHasNonEmptyInputSchema() {
        for tool in MCPToolHandlers.allTools {
            #expect(!tool.inputSchema.isEmpty, "Tool '\(tool.name)' has empty inputSchema")
        }
    }

    // MARK: - Specific Tool: insert_documents_from_file

    @Test("insert_documents_from_file is registered", .tags(.mcp, .fast))
    func testInsertFromFileIsRegistered() {
        let tool = MCPToolHandlers.allTools.first { $0.name == "insert_documents_from_file" }
        #expect(tool != nil)
    }

    @Test("insert_documents_from_file has file_path in required", .tags(.mcp, .fast))
    func testInsertFromFileHasFilePathRequired() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "insert_documents_from_file" }) else {
            Issue.record("insert_documents_from_file tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("file_path"))
    }

    @Test("insert_documents_from_file has collection in required", .tags(.mcp, .fast))
    func testInsertFromFileHasCollectionRequired() {
        // ARRANGE
        guard let tool = MCPToolHandlers.allTools.first(where: { $0.name == "insert_documents_from_file" }) else {
            Issue.record("insert_documents_from_file tool not found")
            return
        }
        let required = tool.inputSchema["required"] as? [String] ?? []

        // ASSERT
        #expect(required.contains("collection"))
    }

    @Test("insert_documents_from_file mode enum has exactly 2 values", .tags(.mcp, .fast))
    func testInsertFromFileModeEnumHasTwoValues() {
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

    @Test("execute_dql has query in required", .tags(.mcp, .fast))
    func testExecuteDQLHasQueryRequired() {
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

    @Test("create_index has collection and field in required", .tags(.mcp, .fast))
    func testCreateIndexHasCollectionAndFieldRequired() {
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

    // MARK: - Known Tool Names

    @Test("All expected tool names are present", .tags(.mcp, .fast))
    func testAllExpectedToolNamesPresent() {
        let names = Set(MCPToolHandlers.allTools.map(\.name))
        let expected: Set<String> = [
            "execute_dql",
            "list_databases",
            "get_active_database",
            "list_collections",
            "create_index",
            "drop_index",
            "get_query_metrics",
            "get_sync_status",
            "configure_transport",
            "insert_documents_from_file"
        ]
        #expect(names == expected)
    }
}
