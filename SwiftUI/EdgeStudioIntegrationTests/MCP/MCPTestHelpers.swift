import Foundation
@testable import Ditto_Edge_Studio

/// Shared helpers for MCP integration tests.
///
/// Uses port 65270 (one above the default 65269) to avoid colliding
/// with a running production instance of Ditto Edge Studio.
enum MCPTestHelpers {
    static let testPort: UInt16 = 65270
    static let baseURL = "http://[::1]:\(testPort)"

    // MARK: Server Lifecycle

    /// Starts MCPServerService on the test port, runs body, then stops it.
    ///
    /// Sets `mcpServerPort` in UserDefaults before calling `start()` so the
    /// server binds on the test port. Polls `isRunning` up to 2 s for the
    /// NWListener to reach `.ready` state before running the body.
    /// Properly awaits stop so the port is fully released before returning.
    static func withServer(_ body: () async throws -> Void) async throws {
        UserDefaults.standard.set(Int(testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()

        // Poll until the server responds to /health, with one stop/restart retry.
        // NWListener can exhibit a cold-start issue the very first time it is
        // created in the test process — it reports .ready but doesn't accept
        // connections yet. Stopping and restarting reliably clears this.
        var serverReady = false
        for attempt in 0 ..< 2 {
            for _ in 0 ..< 30 { // up to 3 s per attempt
                try await Task.sleep(for: .milliseconds(100))
                if let (s, _) = try? await get("/health"), s == 200 {
                    serverReady = true
                    break
                }
            }
            if serverReady { break }
            if attempt == 0 {
                // Cold-start failure — stop, wait, and try once more
                await MCPServerService.shared.stop()
                try await Task.sleep(for: .milliseconds(200))
                await MCPServerService.shared.start()
            }
        }

        do {
            try await body()
        } catch {
            await MCPServerService.shared.stop()
            UserDefaults.standard.removeObject(forKey: "mcpServerPort")
            throw error
        }

        await MCPServerService.shared.stop()
        UserDefaults.standard.removeObject(forKey: "mcpServerPort")
        // Brief pause so the OS fully releases the port before the next test
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: HTTP Helpers

    /// Sends a raw GET request and returns (statusCode, body).
    static func get(_ path: String) async throws -> (Int, String) {
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        return (status, body)
    }

    /// Sends an OPTIONS request and returns the HTTPURLResponse.
    static func options(_ path: String) async throws -> HTTPURLResponse? {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "OPTIONS"
        let (_, response) = try await URLSession.shared.data(for: request)
        return response as? HTTPURLResponse
    }

    /// POSTs a JSON-RPC request and returns the decoded response dictionary.
    static func post(id: Int = 1, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Calls a named tool and returns the result text content.
    static func callTool(_ name: String, arguments: [String: Any] = [:]) async throws -> String {
        let response = try await post(
            method: "tools/call",
            params: ["name": name, "arguments": arguments]
        )
        let content = (response["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    // MARK: File Helpers

    /// Writes a temp JSON file to ~/Downloads, runs body with the path, then deletes it.
    static func withTempJSONFile(
        name: String = "mcp_test_\(UUID().uuidString).json",
        content: String,
        _ body: (String) async throws -> Void
    ) async throws {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(name)")
        try content.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try await body(url.path)
    }
}
