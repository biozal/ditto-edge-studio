import Testing
@testable import Ditto_Edge_Studio

/// Integration tests for MCPServerService lifecycle.
///
/// Starts the server on port 65270 (test port) and verifies HTTP responses.
/// All tests are serialized because only one server instance can run at a time.
@Suite("MCP Server Lifecycle Tests", .serialized, .tags(.mcp, .mcpServer))
struct MCPServerLifecycleTests {
    // MARK: - Health Check

    @Test(.tags(.mcp, .mcpServer))
    func `Server responds to /health with 200 OK`() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let (status, body) = try await MCPTestHelpers.get("/health")

            // ASSERT
            #expect(status == 200)
            #expect(body == "OK")
        }
    }

    // MARK: - 404

    @Test(.tags(.mcp, .mcpServer))
    func `Server responds to unknown path with 404`() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let (status, _) = try await MCPTestHelpers.get("/unknown")

            // ASSERT
            #expect(status == 404)
        }
    }

    // MARK: - CORS

    @Test(.tags(.mcp, .mcpServer))
    func `CORS preflight OPTIONS /mcp is not answered (no browser clients)`() async throws {
        try await MCPTestHelpers.withServer {
            // ACT
            let response = try await MCPTestHelpers.options("/mcp")

            // ASSERT — MCP clients are CLI agents, not browsers: no CORS
            // preflight handling and no Access-Control-Allow-Origin header.
            #expect(response?.statusCode == 404)
            #expect(response?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
        }
    }

    // MARK: - Stale Session

    @Test(.tags(.mcp, .mcpServer))
    func `POST with unknown sessionId returns 404 without executing the mutating tool`() async throws {
        try await MCPTestHelpers.withServer {
            // ACT — POST a MUTATING tool call (set_sync) referencing a session
            // that was never established via GET /mcp
            var request = URLRequest(url: try MCPTestHelpers.requireURL("\(MCPTestHelpers.baseURL)/mcp?sessionId=does-not-exist"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"set_sync","arguments":{"enabled":true}}}"#.utf8
            )
            let (_, response) = try await URLSession.shared.data(for: request)

            // ASSERT — must fail loudly BEFORE dispatch: if the mutation
            // executed and only then 404'd, a retrying client would apply it
            // twice. The notification test below proves the guard runs before
            // the JSON-RPC handler (and therefore before any tool execution).
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }

    @Test(.tags(.mcp, .mcpServer))
    func `POST notification with unknown sessionId is rejected before dispatch`() async throws {
        try await MCPTestHelpers.withServer {
            // A JSON-RPC notification (no "id") normally gets 202 with an
            // empty body — the handler short-circuits before any method
            // dispatch. With an unknown sessionId it must instead be rejected
            // with 404 BEFORE the JSON-RPC handler runs at all. This ordering
            // proof is what guarantees the mutating-tool test above never
            // executes its tool either.
            var request = URLRequest(url: try MCPTestHelpers.requireURL("\(MCPTestHelpers.baseURL)/mcp?sessionId=does-not-exist"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)

            // ASSERT — 404, not the notification path's 202
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }

    @Test(.tags(.mcp, .mcpServer))
    func `POST with unknown sessionId still 404s for the stateless tools/list path`() async throws {
        try await MCPTestHelpers.withServer {
            // ACT — read-only method, same guard applies
            var request = URLRequest(url: try MCPTestHelpers.requireURL("\(MCPTestHelpers.baseURL)/mcp?sessionId=does-not-exist"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)

            // ASSERT
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }

    @Test(.tags(.mcp, .mcpServer, .slow))
    func `POST with a valid sessionId is accepted (202) and dispatched`() async throws {
        try await MCPTestHelpers.withServer {
            try await MCPTestHelpers.withSSESession { sessionId in
                // ACT — POST a mutating tool call against the live session
                var request = URLRequest(
                    url: try MCPTestHelpers.requireURL("\(MCPTestHelpers.baseURL)/mcp?sessionId=\(sessionId)")
                )
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(
                    #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"set_sync","arguments":{"enabled":true}}}"#.utf8
                )
                let (_, response) = try await URLSession.shared.data(for: request)

                // ASSERT — the pre-dispatch session guard must let live
                // sessions through (the tool result itself is delivered over
                // the SSE stream, so the POST body is empty)
                #expect((response as? HTTPURLResponse)?.statusCode == 202)
            }
        }
    }

    // MARK: - Stop / Restart

    @Test(.tags(.mcp, .mcpServer, .slow))
    func `Server stops cleanly — connection refused after stop`() async throws {
        // ARRANGE — start and wait until health check responds
        UserDefaults.standard.set(Int(MCPTestHelpers.testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 {
                break
            }
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

    @Test(.tags(.mcp, .mcpServer, .slow))
    func `stop() drains sessions — a pre-restart sessionId is rejected after restart`() async throws {
        // ARRANGE — start and wait until health check responds
        UserDefaults.standard.set(Int(MCPTestHelpers.testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 {
                break
            }
        }
        defer {
            Task { await MCPServerService.shared.stop() }
            UserDefaults.standard.removeObject(forKey: "mcpServerPort")
        }

        try await MCPTestHelpers.withSSESession { sessionId in
            // Sanity — the session is registered while the server runs
            #expect(await MCPSessionManager.shared.hasSession(sessionId))

            // ACT — stop the server; all sessions must be drained
            await MCPServerService.shared.stop()
            #expect(await !MCPSessionManager.shared.hasSession(sessionId))
            // NWListener socket release is OS-async — give the port time to free up
            // before rebinding (same settle delay as testServerCanRestartAfterStop).
            try await Task.sleep(for: .milliseconds(300))

            // Restart on the same port and wait until healthy
            await MCPServerService.shared.start()
            var healthy = false
            for _ in 0 ..< 50 {
                try await Task.sleep(for: .milliseconds(100))
                if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 {
                    healthy = true
                    break
                }
            }
            // Fail loudly here if the restart itself broke — otherwise a port-bind
            // problem surfaces as a confusing "connection refused" at the POST below.
            #expect(healthy)

            // ASSERT — the pre-restart sessionId must be rejected (404), not
            // silently accepted (202) with the response going into a dead
            // connection. Uses a mutating tool to mirror the retry hazard.
            var request = URLRequest(
                url: try MCPTestHelpers.requireURL("\(MCPTestHelpers.baseURL)/mcp?sessionId=\(sessionId)")
            )
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"set_sync","arguments":{"enabled":true}}}"#.utf8
            )
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }

    @Test(.tags(.mcp, .mcpServer, .slow))
    func `Server can restart after stop`() async throws {
        // ARRANGE — start, wait until health check responds, stop, wait for port release
        UserDefaults.standard.set(Int(MCPTestHelpers.testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 {
                break
            }
        }
        await MCPServerService.shared.stop()
        try await Task.sleep(for: .milliseconds(300))

        // ACT — start again and wait until health check responds
        await MCPServerService.shared.start()
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(100))
            if let (s, _) = try? await MCPTestHelpers.get("/health"), s == 200 {
                break
            }
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
