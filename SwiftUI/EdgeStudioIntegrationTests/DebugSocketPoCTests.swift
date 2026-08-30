import DittoSwift
import Foundation
import Network
import Testing

/// Phase 4 PoC (plan: plans/2026-08-24-vsc-pr16-5.1-diagnostics-parity.md):
/// proves that on macOS a real Ditto SDK 5.1 debug socket can be opened for our
/// own embedded instance (`ALTER SYSTEM SET debug_socket`) and that
/// `Network.framework`'s `NWConnection` to a Unix endpoint can round-trip a
/// newline-DQL query against it.
///
/// Credentials come from the repo-root `.env` (`DITTO_DATABASE_ID` /
/// `DITTO_OFFLINE_TOKEN`, gitignored — never commit real tokens). The test
/// self-skips when the file or keys are absent.
/// Credentials gate for the PoC — declared outside the @Suite because a trait
/// referencing the suite's own statics is a circular macro reference.
private enum DebugSocketPoCCredentials {
    static let value: (databaseId: String, offlineToken: String)? = {
        let envURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EdgeStudioIntegrationTests/
            .deletingLastPathComponent() // SwiftUI/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard let id = values["DITTO_DATABASE_ID"], !id.isEmpty,
              let token = values["DITTO_OFFLINE_TOKEN"], !token.isEmpty
        else { return nil }
        return (id, token)
    }()

    static var hasCredentials: Bool { value != nil }
}

/// Lock-guarded one-shot resume for continuations (Swift 6 concurrency: a
/// captured `var` in a stateUpdateHandler is a data race).
private final class ResumeGate: @unchecked Sendable {
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

@Suite("Debug socket PoC", .enabled(if: DebugSocketPoCCredentials.hasCredentials))
struct DebugSocketPoC {

    private static var credentials: (databaseId: String, offlineToken: String)? {
        DebugSocketPoCCredentials.value
    }

    // MARK: - PoC

    @Test("debug socket round-trips DQL over NWConnection to a unix endpoint")
    func debugSocketRoundTrip() async throws {
        let creds = try #require(Self.credentials)

        let persistenceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("debug-socket-poc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: persistenceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: persistenceDir) }

        let config = DittoConfig.default.updating {
            $0.databaseID = creds.databaseId
            $0.connect = .smallPeersOnly()
            $0.persistenceDirectory = persistenceDir
        }
        let ditto = try await Ditto.open(config: config)
        // Swift SDK 5.1 has no close() — lifecycle is deallocation-based; stop
        // sync and hold the instance for the test's duration.
        try ditto.setOfflineOnlyLicenseToken(creds.offlineToken)

        // PoC findings (see plans/2026-08-24-vsc-pr16-5.1-diagnostics-parity.md):
        // (1) sun_path is 104 chars — long UUID-leafed paths fail to bind;
        // (2) the App Sandbox denies binds outside the container (/tmp fails);
        // (3) bare NWParameters() never reaches .ready for unix endpoints —
        //     NWParameters.tcp is the working recipe.
        // All three together mean: short name, directly under the container's
        // tmp dir, and `.tcp` parameters.
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds-poc.sock").path
        _ = try await ditto.store.execute(query: "ALTER SYSTEM SET debug_socket = '\(socketPath)'")

        // Wait for the socket file to appear.
        let deadline = Date.now.addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: socketPath), Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: socketPath))

        // NWConnection to the unix endpoint.
        // PoC finding: bare NWParameters() never reaches .ready for a unix
        // endpoint; NWParameters.tcp is the working recipe.
        let connection = NWConnection(
            to: NWEndpoint.unix(path: socketPath),
            using: .tcp
        )
        defer { connection.cancel() }

        try await waitForReady(connection)
        print("POC: NWConnection ready")

        let query = Data("SELECT * FROM system:dual\n".utf8)
        connection.send(
            content: query,
            completion: .contentProcessed { _ in }
        )

        let line = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.receiveLine(connection) }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                connection.cancel() // force the suspended receive to error out
                throw NSError(domain: "DebugSocketPoC", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "no response line within 10s",
                ])
            }
            let first = try await group.next()
            group.cancelAll()
            return first!
        }
        #expect(line.contains("dummy"))
        #expect(line.trimmingCharacters(in: .whitespaces).hasPrefix("["))

        // Tear down the listener before the instance is released.
        _ = try? await ditto.store.execute(query: "ALTER SYSTEM SET debug_socket = ''")
        try? await ditto.sync.stop()
        withExtendedLifetime(ditto) {}
    }

    // MARK: - NW helpers

    private func waitForReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume { cont.resume() }
                case .failed(let error):
                    gate.resume { cont.resume(throwing: error) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func receiveLine(_ connection: NWConnection) async throws -> String {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk(connection)
            buffer.append(chunk)
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return String(decoding: buffer[..<newlineIndex], as: UTF8.self)
            }
        }
    }

    private func receiveChunk(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: NSError(domain: "DebugSocketPoC", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "socket closed before a full line arrived",
                    ]))
                } else {
                    // Empty keep-alive chunk — keep waiting by returning empty data.
                    cont.resume(returning: Data())
                }
            }
        }
    }
}
