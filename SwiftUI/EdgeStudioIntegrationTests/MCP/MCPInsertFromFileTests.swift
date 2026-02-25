import Testing
@testable import Ditto_Edge_Studio

/// Integration tests for the insert_documents_from_file MCP tool.
///
/// Tests are split into two groups:
/// - Argument validation (no database needed): missing/empty required params
/// - File I/O errors (no database needed): file not found, bad JSON, missing _id, invalid collection
/// - Happy path (requires active database): annotated .external, skipped in CI
///
/// All tests are serialized because only one server can run at a time.
@Suite("MCP Insert From File Tests", .serialized, .tags(.mcp, .mcpTools))
struct MCPInsertFromFileTests {

    // MARK: - Argument Validation (no database, no file)

    @Test("Missing file_path returns missing argument error", .tags(.mcp, .mcpTools, .fast))
    func testMissingFilePath() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool(
                "insert_documents_from_file",
                arguments: ["collection": "tasks"]
            )

            // ASSERT
            #expect(text.contains("Missing required argument: file_path"))
        }
    }

    @Test("Missing collection returns missing argument error", .tags(.mcp, .mcpTools, .fast))
    func testMissingCollection() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool(
                "insert_documents_from_file",
                arguments: ["file_path": "/tmp/x.json"]
            )

            // ASSERT
            #expect(text.contains("Missing required argument: collection"))
        }
    }

    @Test("Empty file_path returns missing argument error", .tags(.mcp, .mcpTools, .fast))
    func testEmptyFilePath() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool(
                "insert_documents_from_file",
                arguments: ["file_path": "", "collection": "tasks"]
            )

            // ASSERT
            #expect(text.contains("Missing required argument: file_path"))
        }
    }

    @Test("Empty collection returns missing argument error", .tags(.mcp, .mcpTools, .fast))
    func testEmptyCollection() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let text = try await MCPTestHelpers.callTool(
                "insert_documents_from_file",
                arguments: ["file_path": "/tmp/x.json", "collection": ""]
            )

            // ASSERT
            #expect(text.contains("Missing required argument: collection"))
        }
    }

    // MARK: - File I/O Errors (no database needed)

    @Test("Non-existent file path returns could not read file error", .tags(.mcp, .mcpTools))
    func testFileNotFound() async throws {
        try await MCPTestHelpers.withServer {
            // ARRANGE — path that doesn't exist
            let fakePath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/mcp_nonexistent_\(UUID().uuidString).json")
                .path

            // ACT
            let text = try await MCPTestHelpers.callTool(
                "insert_documents_from_file",
                arguments: ["file_path": fakePath, "collection": "tasks"]
            )

            // ASSERT
            #expect(text.contains("Could not read file"))
        }
    }

    @Test("File with invalid JSON returns file must contain an array error", .tags(.mcp, .mcpTools))
    func testInvalidJSONFile() async throws {
        try await MCPTestHelpers.withServer {
            try await MCPTestHelpers.withTempJSONFile(content: "not json at all") { path in
                // ACT
                let text = try await MCPTestHelpers.callTool(
                    "insert_documents_from_file",
                    arguments: ["file_path": path, "collection": "tasks"]
                )

                // ASSERT
                #expect(text.contains("array") || text.contains("parse") || text.contains("JSON"))
            }
        }
    }

    @Test("File with JSON object (not array) returns file must contain an array error", .tags(.mcp, .mcpTools))
    func testJSONObjectNotArray() async throws {
        try await MCPTestHelpers.withServer {
            try await MCPTestHelpers.withTempJSONFile(content: "{\"_id\":\"a\",\"title\":\"test\"}") { path in
                // ACT
                let text = try await MCPTestHelpers.callTool(
                    "insert_documents_from_file",
                    arguments: ["file_path": path, "collection": "tasks"]
                )

                // ASSERT
                #expect(text.contains("array"))
            }
        }
    }

    @Test("JSON array with document missing _id returns missing _id error", .tags(.mcp, .mcpTools))
    func testDocumentMissingId() async throws {
        try await MCPTestHelpers.withServer {
            let content = "[{\"title\":\"task without id\",\"done\":false}]"
            try await MCPTestHelpers.withTempJSONFile(content: content) { path in
                // ACT
                let text = try await MCPTestHelpers.callTool(
                    "insert_documents_from_file",
                    arguments: ["file_path": path, "collection": "tasks"]
                )

                // ASSERT
                #expect(text.contains("_id"))
            }
        }
    }

    @Test("Valid file but invalid collection name returns invalid characters error", .tags(.mcp, .mcpTools))
    func testInvalidCollectionName() async throws {
        try await MCPTestHelpers.withServer {
            let content = "[{\"_id\":\"a\",\"title\":\"test\"}]"
            try await MCPTestHelpers.withTempJSONFile(content: content) { path in
                // ACT
                let text = try await MCPTestHelpers.callTool(
                    "insert_documents_from_file",
                    arguments: ["file_path": path, "collection": "bad name!"]
                )

                // ASSERT
                #expect(text.contains("invalid") || text.contains("characters") || text.contains("collection"))
            }
        }
    }

    // MARK: - Happy Path (requires active database)

    @Test(
        "Insert 3 documents from valid JSON file",
        .tags(.mcp, .mcpTools, .external),
        .disabled("Requires active Ditto database — run manually")
    )
    func testInsertValidFile() async throws {
        guard await DittoManager.shared.dittoSelectedApp != nil else {
            withKnownIssue("Requires active database") { Issue.record() }
            return
        }

        try await MCPTestHelpers.withServer {
            let content = """
            [
              {"_id":"mcp-test-001","title":"Test Task 1","done":false},
              {"_id":"mcp-test-002","title":"Test Task 2","done":false},
              {"_id":"mcp-test-003","title":"Test Task 3","done":true}
            ]
            """
            try await MCPTestHelpers.withTempJSONFile(content: content) { path in
                let text = try await MCPTestHelpers.callTool(
                    "insert_documents_from_file",
                    arguments: ["file_path": path, "collection": "mcp_test_tasks", "mode": "insert"]
                )

                // Parse the JSON result
                if let data = text.data(using: .utf8),
                   let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    #expect(result["inserted"] as? Int == 3)
                    #expect(result["failed"] as? Int == 0)
                }
            }
        }
    }
}
