import Testing
@testable import Ditto_Edge_Studio

/// Integration tests for MCPServerService lifecycle.
///
/// Starts the server on port 65270 (test port) and verifies HTTP responses.
/// All tests are serialized because only one server instance can run at a time.
@Suite("MCP Server Lifecycle Tests", .serialized, .tags(.mcp, .mcpServer))
struct MCPServerLifecycleTests {

    // MARK: - Health Check

    @Test("Server responds to /health with 200 OK", .tags(.mcp, .mcpServer))
    func testHealthReturns200() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let (status, body) = try await MCPTestHelpers.get("/health")

            // ASSERT
            #expect(status == 200)
            #expect(body == "OK")
        }
    }

    // MARK: - 404

    @Test("Server responds to unknown path with 404", .tags(.mcp, .mcpServer))
    func testUnknownPathReturns404() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let (status, _) = try await MCPTestHelpers.get("/unknown")

            // ASSERT
            #expect(status == 404)
        }
    }

    // MARK: - CORS

    @Test("CORS preflight OPTIONS /mcp returns 204", .tags(.mcp, .mcpServer))
    func testCORSPreflightReturns204() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.options("/mcp")

            // ASSERT
            #expect(response?.statusCode == 204)
            #expect(response?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")
        }
    }

    // MARK: - Stop / Restart

    @Test("Server stops cleanly — connection refused after stop", .tags(.mcp, .mcpServer, .slow))
    func testServerStopsCleanly() async throws {
        // ARRANGE — start and wait until health check responds
        UserDefaults.standard.set(Int(MCPTestHelpers.testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 { break }
        }

        // Verify it was running
        let (statusBefore, _) = try await MCPTestHelpers.get("/health")
        #expect(statusBefore == 200)

        // ACT — stop the server and wait for port to fully release
        await MCPServerService.shared.stop()
        try await Task.sleep(for: .milliseconds(300))
        UserDefaults.standard.removeObject(forKey: "mcpServerPort")

        // ASSERT — connection should now be refused
        do {
            _ = try await MCPTestHelpers.get("/health")
            Issue.record("Expected connection to be refused after stop, but got a response")
        } catch {
            // Expected: URLError.cannotConnectToHost or similar
            #expect(error is URLError)
        }
    }

    @Test("Server can restart after stop", .tags(.mcp, .mcpServer, .slow))
    func testServerCanRestartAfterStop() async throws {
        // ARRANGE — start, wait until health check responds, stop, wait for port release
        UserDefaults.standard.set(Int(MCPTestHelpers.testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 { break }
        }
        await MCPServerService.shared.stop()
        try await Task.sleep(for: .milliseconds(300))

        // ACT — start again and wait until health check responds
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 { break }
        }
        defer {
            Task { await MCPServerService.shared.stop() }
            UserDefaults.standard.removeObject(forKey: "mcpServerPort")
        }

        // ASSERT
        let (status, body) = try await MCPTestHelpers.get("/health")
        #expect(status == 200)
        #expect(body == "OK")
    }
}
