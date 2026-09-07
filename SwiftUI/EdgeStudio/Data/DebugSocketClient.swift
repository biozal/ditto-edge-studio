import Foundation
import Network

/// Client for the Ditto SDK 5.1 `debug_socket` listener (parity with the VS Code
/// extension's `DebugSocketClient`).
///
/// **Currently unused by the app — retained deliberately.** The in-app Debug
/// Console it used to drive was removed: it opened a socket back to our *own*
/// process to run DQL the query editor's Local mode already runs directly on
/// the same `dittoSelectedApp` instance, with no syntax restriction either way.
/// `debug_socket` only earns its keep for an *external* process (which is why
/// the VS Code extension needs it), so this client stays for a future
/// attach-to-another-Ditto feature rather than being rewritten from scratch.
/// Expect it in Periphery reports until then.
///
/// Protocol: one DQL statement per line → one reply line (JSON array of items,
/// or `ERROR: <message>`). The actor serialises exchanges (the wire has no
/// request IDs, so FIFO pairing is the only safe alignment). A 30 s timeout
/// closes the connection — the next call reconnects lazily. Reply lines are
/// capped at 64 MiB; exceeding that closes the connection (extension parity).
actor DebugSocketClient {
    enum ClientError: Error, Equatable {
        case notConnected
        case timeout
        case responseTooLarge
    }

    static let defaultConnectTimeout: Duration = .seconds(10)
    static let defaultQueryTimeout: Duration = .seconds(30)
    static let defaultMaxLineBytes = 64 * 1024 * 1024

    private var connection: NWConnection?
    private var socketPath: String?
    /// Leftover bytes from a chunk that carried more than one reply line —
    /// without this, bundled replies are silently dropped and FIFO pairing breaks.
    private var receiveBuffer = Data()

    // FIFO gate for execute(): actor methods are NOT mutually exclusive across
    // suspension points (reentrancy) — two executes would interleave on the wire
    // (that race is what the client tests caught: q2 got q3's reply).
    private var gateHeld = false
    private var gateQueue: [CheckedContinuation<Void, Never>] = []

    private func acquireGate() async {
        if !gateHeld {
            gateHeld = true
            return
        }
        await withCheckedContinuation { gateQueue.append($0) }
    }

    private func releaseGate() {
        if let next = gateQueue.first {
            gateQueue.removeFirst()
            next.resume()
        } else {
            gateHeld = false
        }
    }

    private let connectTimeout: Duration
    private let queryTimeout: Duration
    private let maxLineBytes: Int

    init(
        connectTimeout: Duration = DebugSocketClient.defaultConnectTimeout,
        queryTimeout: Duration = DebugSocketClient.defaultQueryTimeout,
        maxLineBytes: Int = DebugSocketClient.defaultMaxLineBytes
    ) {
        self.connectTimeout = connectTimeout
        self.queryTimeout = queryTimeout
        self.maxLineBytes = maxLineBytes
    }

    /// Connects to the unix socket at `path`. Idempotent; reconnects after close.
    /// (PoC finding: `NWParameters.tcp` is required for unix endpoints — bare
    /// `NWParameters()` never reaches `.ready`.)
    func connect(path: String) async throws {
        if connection != nil, socketPath == path {
            return
        }
        closeLocked()
        socketPath = path
        let conn = NWConnection(to: .unix(path: path), using: .tcp)
        connection = conn
        try await waitForReady(conn, timeout: connectTimeout)
    }

    /// Sends `statement` (newline-terminated on the wire) and returns the reply
    /// line (terminator stripped).
    func execute(_ statement: String) async throws -> String {
        await acquireGate()
        defer { releaseGate() }
        guard let socketPath else { throw ClientError.notConnected }
        if connection == nil {
            let conn = NWConnection(to: .unix(path: socketPath), using: .tcp)
            connection = conn
            try await waitForReady(conn, timeout: connectTimeout)
        }
        guard let active = connection else { throw ClientError.notConnected }

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.exchange(active, statement: statement)
                }
                group.addTask {
                    try await Task.sleep(for: self.queryTimeout)
                    // Extension parity: a timeout closes the connection; the next
                    // call reconnects. Cancelling unblocks the suspended receive.
                    active.cancel()
                    throw ClientError.timeout
                }
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw ClientError.notConnected
                }
                group.cancelAll()
                return result
            }
        } catch {
            // Timeout / responseTooLarge / peer-drop: tear the connection down so
            // the next execute() lazily reconnects (and the poisoned receive
            // buffer is reset). Without this, a single timeout bricks every
            // subsequent statement on this client.
            closeLocked()
            throw error
        }
    }

    func close() {
        closeLocked()
    }

    // MARK: - Internals (actor-isolated)

    private func closeLocked() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
    }

    private func waitForReady(_ connection: NWConnection, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let gate = ResumeOnceGate()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume { cont.resume() }
                        case let .failed(error):
                            gate.resume { cont.resume(throwing: error) }
                        case .cancelled:
                            gate.resume {
                                cont.resume(throwing: ClientError.notConnected)
                            }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                connection.cancel()
                throw ClientError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func exchange(_ connection: NWConnection, statement: String) async throws -> String {
        var payload = Data(statement.utf8)
        payload.append(0x0A) // \n
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }

        while true {
            if let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
                let line = receiveBuffer[..<newlineIndex]
                receiveBuffer = receiveBuffer[(newlineIndex + 1)...]
                return String(bytes: line, encoding: .utf8) ?? ""
            }
            if receiveBuffer.count > maxLineBytes {
                throw ClientError.responseTooLarge
            }
            let chunk = try await receiveChunk(connection)
            receiveBuffer.append(chunk)
        }
    }

    private func receiveChunk(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: ClientError.notConnected)
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }
}

/// Lock-guarded one-shot resume (a captured `var` inside a state handler is a
/// Swift 6 data race).
private final class ResumeOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        body()
    }
}
