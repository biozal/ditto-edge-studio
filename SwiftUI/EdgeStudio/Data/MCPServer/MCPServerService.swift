#if os(macOS)
import Foundation
import Network

// MARK: - SSE Session

/// Represents an active SSE connection with a MCP client.
/// Thread-safe: NWConnection.send is internally thread-safe.
final class MCPSSESession: @unchecked Sendable {
    let sessionId: String
    private let connection: NWConnection
    private var keepAliveTask: Task<Void, Never>?

    init(sessionId: String, connection: NWConnection) {
        self.sessionId = sessionId
        self.connection = connection
    }

    func startKeepAlive() {
        keepAliveTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                connection.send(
                    content: Data(": keepalive\n\n".utf8),
                    completion: .contentProcessed { _ in }
                )
            }
        }
    }

    func sendEvent(_ event: String, data: String) {
        let sseString = "event: \(event)\ndata: \(data)\n\n"
        connection.send(content: Data(sseString.utf8), completion: .contentProcessed { _ in })
    }

    func close() {
        keepAliveTask?.cancel()
        connection.cancel()
    }
}

// MARK: - Session Manager

/// Manages active SSE sessions.
actor MCPSessionManager {
    static let shared = MCPSessionManager()
    private var sessions: [String: MCPSSESession] = [:]

    private init() {}

    func addSession(_ session: MCPSSESession) {
        sessions[session.sessionId] = session
    }

    func removeSession(_ sessionId: String) {
        sessions[sessionId]?.close()
        sessions.removeValue(forKey: sessionId)
    }

    func sendResponse(_ responseJSON: String, to sessionId: String) {
        sessions[sessionId]?.sendEvent("message", data: responseJSON)
    }
}

// MARK: - HTTP Request

struct HTTPRequest {
    let method: String
    let path: String
    let queryParams: [String: String]
    let headers: [String: String]
    let body: Data
}

// MARK: - HTTP Connection Handler

/// Handles a single incoming HTTP connection.
final class MCPHTTPConnectionHandler: @unchecked Sendable {
    private let connection: NWConnection
    private let serverPort: UInt16
    /// Only accessed from the serialized NWConnection receive callback chain
    private var accumulatedData = Data()
    /// Retains self until the connection finishes so the weak-self receive callback stays valid.
    private var selfRetain: MCPHTTPConnectionHandler?

    init(connection: NWConnection, serverPort: UInt16) {
        self.connection = connection
        self.serverPort = serverPort
    }

    func start() {
        selfRetain = self
        scheduleRead()
    }

    // MARK: Read Loop

    private func scheduleRead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data { accumulatedData.append(data) }

            if let request = MCPHTTPParser.tryParse(accumulatedData) {
                Task { await self.handleRequest(request) }
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            scheduleRead()
        }
    }

    // MARK: Request Routing

    private func handleRequest(_ request: HTTPRequest) async {
        if request.method == "OPTIONS" {
            sendCORSPreflight()
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            sendTextResponse(status: 200, body: "OK")

        case ("GET", "/mcp"):
            await handleSSEConnection(request)

        case ("POST", "/mcp"):
            await handlePostMessage(request)

        default:
            sendTextResponse(status: 404, body: "Not Found")
        }
    }

    // MARK: SSE Connection

    private func handleSSEConnection(_: HTTPRequest) async {
        let sessionId = UUID().uuidString
        let session = MCPSSESession(sessionId: sessionId, connection: connection)
        await MCPSessionManager.shared.addSession(session)

        let headerLines = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ]
        connection.send(
            content: Data(headerLines.joined(separator: "\r\n").utf8),
            completion: .contentProcessed { _ in }
        )

        let endpointURL = "http://localhost:\(serverPort)/mcp?sessionId=\(sessionId)"
        connection.send(
            content: Data("event: endpoint\ndata: \(endpointURL)\n\n".utf8),
            completion: .contentProcessed { _ in }
        )

        session.startKeepAlive()

        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed:
                Task { await MCPSessionManager.shared.removeSession(sessionId) }
            default:
                break
            }
        }

        // Session now owns the connection; release self-retain.
        selfRetain = nil
    }

    // MARK: POST Message

    private func handlePostMessage(_ request: HTTPRequest) async {
        let sessionId = request.queryParams["sessionId"]

        let (responseJSON, isNotification) = await MCPJSONRPCHandler.handle(request.body)

        if isNotification {
            sendJSONResponse(status: 202, body: Data())
            return
        }

        if let sessionId {
            await MCPSessionManager.shared.sendResponse(responseJSON, to: sessionId)
            sendJSONResponse(status: 202, body: Data())
        } else {
            sendJSONResponse(status: 200, body: Data(responseJSON.utf8))
        }
    }

    // MARK: Response Helpers

    private func sendJSONResponse(status: Int, body: Data) {
        let statusText = statusDescription(status)
        let headerLines = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ]
        var response = Data(headerLines.joined(separator: "\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
            self?.selfRetain = nil
        })
    }

    private func sendTextResponse(status: Int, body: String) {
        let bodyData = Data(body.utf8)
        let statusText = statusDescription(status)
        let headerLines = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: text/plain",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ]
        var response = Data(headerLines.joined(separator: "\r\n").utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
            self?.selfRetain = nil
        })
    }

    private func sendCORSPreflight() {
        let headerLines = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ]
        connection.send(
            content: Data(headerLines.joined(separator: "\r\n").utf8),
            completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
                self?.selfRetain = nil
            }
        )
    }

    private func statusDescription(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 404: "Not Found"
        default: "Error"
        }
    }
}

// MARK: - MCP Server Service

/// Manages the embedded MCP HTTP server lifecycle.
///
/// The server listens on localhost only (port 65269 by default).
/// Enable/disable via Settings → General → MCP Server.
///
/// Usage:
/// ```swift
/// await MCPServerService.shared.start()
/// await MCPServerService.shared.stop()
/// ```
actor MCPServerService {
    static let shared = MCPServerService()

    private var listener: NWListener?
    private(set) var isRunning = false

    var port: UInt16 {
        let p = UserDefaults.standard.integer(forKey: "mcpServerPort")
        return p > 0 ? UInt16(p) : 65269
    }

    private init() {}

    func start() async {
        guard !isRunning else { return }

        let currentPort = port
        guard let nwPort = NWEndpoint.Port(rawValue: currentPort) else {
            Log.error("MCP Server: invalid port \(currentPort)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    switch state {
                    case .ready:
                        await self?.setRunning(true)
                        Log.info("MCP Server started on port \(currentPort)")
                    case let .failed(error):
                        await self?.setRunning(false)
                        Log.error("MCP Server failed: \(error.localizedDescription)")
                    case .cancelled:
                        await self?.setRunning(false)
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                let handler = MCPHTTPConnectionHandler(connection: connection, serverPort: currentPort)
                handler.start()
            }

            newListener.start(queue: .global(qos: .userInitiated))
            listener = newListener
        } catch {
            Log.error("MCP Server failed to start on port \(currentPort): \(error.localizedDescription)")
        }
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        isRunning = false
        Log.info("MCP Server stopped")
    }

    private func setRunning(_ value: Bool) {
        isRunning = value
    }
}
#endif
