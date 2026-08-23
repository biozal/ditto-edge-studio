import Foundation
import Network
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for `MCPServerService` port resolution and `MCPSessionManager`
/// session draining.
///
/// Serialized because the port tests mutate the shared `mcpServerPort`
/// UserDefaults key and the session tests share the `MCPSessionManager`
/// singleton.
@Suite("MCP Server Service Tests", .serialized, .tags(.mcp, .mcpServer))
struct MCPServerServiceTests {
    // MARK: - Port clamping

    @Suite("Port clamping", .serialized)
    struct PortClampingTests {
        init() {
            UserDefaults.standard.removeObject(forKey: "mcpServerPort")
        }

        /// Sets a port value, runs the assertion, then cleans up the shared
        /// UserDefaults key (suite structs can't deinit for teardown).
        private static func withStoredPort(
            _ value: Int?,
            _ assert: () async -> Void
        ) async {
            if let value {
                UserDefaults.standard.set(value, forKey: "mcpServerPort")
            }
            await assert()
            UserDefaults.standard.removeObject(forKey: "mcpServerPort")
        }

        @Test(.tags(.mcp, .fast))
        func `Defaults to 65269 when no port is stored`() async {
            #expect(await MCPServerService.shared.port == 65269)
        }

        @Test(.tags(.mcp, .fast))
        func `Valid stored port is used`() async {
            await Self.withStoredPort(65270) {
                #expect(await MCPServerService.shared.port == 65270)
            }
        }

        @Test(.tags(.mcp, .fast))
        func `Port above UInt16.max falls back to default instead of trapping`() async {
            // UInt16(p) would precondition-fail on 70000 — a corrupt
            // UserDefaults value must not crash the app.
            await Self.withStoredPort(70000) {
                #expect(await MCPServerService.shared.port == 65269)
            }
        }

        @Test(.tags(.mcp, .fast))
        func `Zero and negative ports fall back to default`() async {
            await Self.withStoredPort(0) {
                #expect(await MCPServerService.shared.port == 65269)
            }
            await Self.withStoredPort(-1) {
                #expect(await MCPServerService.shared.port == 65269)
            }
        }

        @Test(.tags(.mcp, .fast))
        func `UInt16.max boundary port is accepted`() async {
            await Self.withStoredPort(65535) {
                #expect(await MCPServerService.shared.port == 65535)
            }
        }
    }

    // MARK: - Session manager draining

    @Suite("Session manager draining", .serialized)
    struct SessionDrainTests {
        /// Builds a session around an unstarted NWConnection — `close()` on
        /// an unstarted connection is a safe no-op.
        private static func makeSession(id: String) -> MCPSSESession {
            let connection = NWConnection(
                to: .hostPort(host: "127.0.0.1", port: 1),
                using: .tcp
            )
            return MCPSSESession(sessionId: id, connection: connection)
        }

        @Test(.tags(.mcp, .fast))
        func `removeAll closes and removes every session`() async {
            // ARRANGE
            let manager = MCPSessionManager.shared
            await manager.addSession(Self.makeSession(id: "drain-test-a"))
            await manager.addSession(Self.makeSession(id: "drain-test-b"))
            #expect(await manager.hasSession("drain-test-a"))
            #expect(await manager.hasSession("drain-test-b"))

            // ACT
            await manager.removeAll()

            // ASSERT — a post-restart hasSession check must not match
            // pre-restart sessionIds
            #expect(await !manager.hasSession("drain-test-a"))
            #expect(await !manager.hasSession("drain-test-b"))
        }

        @Test(.tags(.mcp, .fast))
        func `removeAll on an empty manager is a no-op`() async {
            let manager = MCPSessionManager.shared
            await manager.removeAll()
            #expect(await !manager.hasSession("anything"))
        }

        @Test(.tags(.mcp, .fast))
        func `removeSession still removes a single session`() async {
            let manager = MCPSessionManager.shared
            await manager.addSession(Self.makeSession(id: "single-test"))
            #expect(await manager.hasSession("single-test"))

            await manager.removeSession("single-test")

            #expect(await !manager.hasSession("single-test"))
        }
    }
}
