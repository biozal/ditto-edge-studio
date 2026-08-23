import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for pure helpers on `MCPToolHandlers`.
///
/// The tool handlers themselves need a live Ditto instance (covered by
/// EdgeStudioIntegrationTests/MCP); this suite covers the extracted
/// decision logic that doesn't.
@Suite("MCP Tool Handlers Tests", .serialized, .tags(.mcp, .mcpTools))
struct MCPToolHandlersTests {
    // MARK: - indexNameByStrippingCollectionPrefix

    @Suite("indexNameByStrippingCollectionPrefix", .serialized)
    struct IndexNameStrippingTests {
        @Test(.tags(.mcp, .fast))
        func `Strips a simple collection prefix`() {
            #expect(
                MCPToolHandlers.indexNameByStrippingCollectionPrefix(
                    _id: "tasks.idx_tasks_status",
                    collection: "tasks"
                ) == "idx_tasks_status"
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Strips correctly when the collection name contains dots`() {
            // displayName strips at the FIRST dot and would produce
            // "col.idx_x" here — the known-prefix strip yields "idx_x".
            #expect(
                MCPToolHandlers.indexNameByStrippingCollectionPrefix(
                    _id: "my.col.idx_x",
                    collection: "my.col"
                ) == "idx_x"
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Index names containing dots are preserved`() {
            #expect(
                MCPToolHandlers.indexNameByStrippingCollectionPrefix(
                    _id: "tasks.idx.a.b",
                    collection: "tasks"
                ) == "idx.a.b"
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Only the exact collection prefix is stripped`() {
            // _id "tasks2.idx_x" does not start with "tasks." — falls back
            // to the first-dot strip.
            #expect(
                MCPToolHandlers.indexNameByStrippingCollectionPrefix(
                    _id: "tasks2.idx_x",
                    collection: "tasks"
                ) == "idx_x"
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Bare name with no dot is returned unchanged`() {
            #expect(
                MCPToolHandlers.indexNameByStrippingCollectionPrefix(
                    _id: "idx_x",
                    collection: "tasks"
                ) == "idx_x"
            )
        }
    }

    // MARK: - indexMatches

    @Suite("indexMatches", .serialized)
    struct IndexMatchesTests {
        @Test(.tags(.mcp, .fast))
        func `Matches bare index name on a simple collection`() {
            #expect(
                MCPToolHandlers.indexMatches(
                    _id: "tasks.idx_tasks_status",
                    collection: "tasks",
                    name: "idx_tasks_status"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Matches full _id on a simple collection`() {
            #expect(
                MCPToolHandlers.indexMatches(
                    _id: "tasks.idx_tasks_status",
                    collection: "tasks",
                    name: "tasks.idx_tasks_status"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Matches bare index name when the collection name contains dots`() {
            // displayName would yield "col.idx_x" here and fail to match.
            #expect(
                MCPToolHandlers.indexMatches(
                    _id: "my.col.idx_x",
                    collection: "my.col",
                    name: "idx_x"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Matches full _id when the collection name contains dots`() {
            #expect(
                MCPToolHandlers.indexMatches(
                    _id: "my.col.idx_x",
                    collection: "my.col",
                    name: "my.col.idx_x"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Matches the sanitized name makeIndexName produces for a dotted collection`() {
            // create_index pre-check: makeIndexName("my.col", "x") →
            // "idx_my_col_x"; stored _id is "my.col.idx_my_col_x".
            #expect(
                MCPToolHandlers.indexMatches(
                    _id: "my.col.idx_my_col_x",
                    collection: "my.col",
                    name: "idx_my_col_x"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Does not match a different index name`() {
            #expect(
                !MCPToolHandlers.indexMatches(
                    _id: "my.col.idx_x",
                    collection: "my.col",
                    name: "idx_y"
                )
            )
        }

        @Test(.tags(.mcp, .fast))
        func `Does not match a full _id that differs only in the index part`() {
            #expect(
                !MCPToolHandlers.indexMatches(
                    _id: "other.idx_x",
                    collection: "tasks",
                    name: "other.idx_x2"
                )
            )
        }
    }
}
