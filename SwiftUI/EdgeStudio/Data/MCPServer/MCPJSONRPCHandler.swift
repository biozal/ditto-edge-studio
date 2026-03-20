#if os(macOS)
import Foundation

// MARK: - JSON-RPC ID

/// Type-safe representation of a JSON-RPC request ID.
enum JSONRPCId {
    case string(String)
    case integer(Int)
    case null

    var jsonValue: Any {
        switch self {
        case let .string(s): s
        case let .integer(i): i
        case .null: NSNull()
        }
    }

    static func parse(from json: [String: Any]) -> JSONRPCId {
        if let s = json["id"] as? String { return .string(s) }
        if let i = json["id"] as? Int { return .integer(i) }
        return .null
    }
}

// MARK: - JSON-RPC Handler

/// Handles MCP JSON-RPC 2.0 protocol messages.
///
/// Supports three methods:
/// - `initialize` — protocol handshake
/// - `tools/list` — returns all available tool definitions
/// - `tools/call` — executes a named tool
///
/// Returns a tuple: (responseJSON, isNotification)
/// Notifications (no `id`) return an empty string and `isNotification = true`.
enum MCPJSONRPCHandler {
    static func handle(_ body: Data) async -> (String, Bool) {
        guard !body.isEmpty else {
            return (errorResponse(id: .null, code: -32700, message: "Empty request body"), false)
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return (errorResponse(id: .null, code: -32700, message: "Parse error"), false)
            }

            let method = json["method"] as? String ?? ""

            // Notifications have no "id" field — do not respond
            if json["id"] == nil {
                return ("", true)
            }

            let id = JSONRPCId.parse(from: json)
            let params = json["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                return (initializeResponse(id: id), false)

            case "tools/list":
                return (toolsListResponse(id: id), false)

            case "tools/call":
                let response = await toolsCallResponse(id: id, params: params)
                return (response, false)

            default:
                return (errorResponse(id: id, code: -32601, message: "Method not found: \(method)"), false)
            }
        } catch {
            return (errorResponse(id: .null, code: -32700, message: "Parse error: \(error.localizedDescription)"), false)
        }
    }

    // MARK: initialize

    private static func initializeResponse(id: JSONRPCId) -> String {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [String: Any]()
            ],
            "serverInfo": [
                "name": "ditto-edge-studio",
                "version": "1.0.0"
            ]
        ]
        return successResponse(id: id, result: result)
    }

    // MARK: tools/list

    private static func toolsListResponse(id: JSONRPCId) -> String {
        let tools = MCPToolHandlers.allTools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.inputSchema
            ]
        }
        return successResponse(id: id, result: ["tools": tools])
    }

    // MARK: tools/call

    private static func toolsCallResponse(id: JSONRPCId, params: [String: Any]) async -> String {
        guard let toolName = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing required parameter: name")
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]

        do {
            let resultText = try await MCPToolHandlers.execute(toolName: toolName, arguments: arguments)
            let result: [String: Any] = [
                "content": [
                    ["type": "text", "text": resultText]
                ]
            ]
            return successResponse(id: id, result: result)
        } catch {
            let result: [String: Any] = [
                "content": [
                    ["type": "text", "text": "Error: \(error.localizedDescription)"]
                ],
                "isError": true
            ]
            return successResponse(id: id, result: result)
        }
    }

    // MARK: Response Builders

    private static func successResponse(id: JSONRPCId, result: [String: Any]) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonValue,
            "result": result
        ]
        return toJSON(response)
    }

    static func errorResponse(id: JSONRPCId, code: Int, message: String) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonValue,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        return toJSON(response)
    }

    private static func toJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else
        {
            return #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"}}"#
        }
        return string
    }
}
#endif
