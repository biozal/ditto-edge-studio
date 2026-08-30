import Foundation
import Network
import Testing
@testable import Ditto_Edge_Studio

/// Protocol tests for `DebugSocketClient` against a self-hosted `NWListener`
/// echo server on a unix socket (the live-Ditto round-trip is
/// `DebugSocketPoCTests` in the integration target).
@Suite("DebugSocketClient tests")
struct DebugSocketClientTests {

    // MARK: - Echo server helper (NWListener can't listen on unix sockets —
    // POSIX it is)

    private final class EchoServer: @unchecked Sendable {
        let path: String
        private let listenFD: Int32
        private var running = true
        private let delayLock = NSLock()
        private var delayMsStorage: UInt64

        /// Thread-safe mutable delay (the timeout test flips it between runs).
        var delayMs: UInt64 {
            get { delayLock.lock(); defer { delayLock.unlock() }; return delayMsStorage }
        }
        func setDelayMs(_ value: UInt64) {
            delayLock.lock(); delayMsStorage = value; delayLock.unlock()
        }

        init?(path: String, delayMs: UInt64) {
            delayMsStorage = delayMs
            self.path = path
            listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listenFD >= 0 else { return nil }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
            _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                path.withCString { strncpy(ptr, $0, maxPath) }
            }
            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listenFD, $0, addrLen)
                }
            }
            guard bound == 0 else { close(listenFD); return nil }
            guard Darwin.listen(listenFD, 8) == 0 else { close(listenFD); return nil }

            Thread.detachNewThread { [weak self] in
                guard let self else { return }
                while self.running {
                    let connFD = accept(listenFD, nil, nil)
                    if connFD < 0 { break }
                    Thread.detachNewThread { self.serve(connFD, delayMs: self.delayMs) }
                }
            }
        }

        private func serve(_ fd: Int32, delayMs: UInt64) {
            var pending = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let read = recv(fd, &buf, buf.count, 0)
                if read <= 0 { break }
                pending.append(contentsOf: buf[0 ..< read])
                while let idx = pending.firstIndex(of: 0x0A) {
                    let line = pending[..<idx]
                    pending = pending[(idx + 1)...]
                    if delayMs > 0 { Thread.sleep(forTimeInterval: Double(delayMs) / 1000) }
                    var reply = Data(line.reversed()) + Data([0x0A])
                    let sent = reply.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
                    if sent < 0 { close(fd); return }
                }
            }
            close(fd)
        }

        func stop() {
            running = false
            close(listenFD)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func startEchoServer(delayMs: UInt64 = 0) -> EchoServer? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds-test-\(UUID().uuidString.prefix(6)).sock").path
        return EchoServer(path: path, delayMs: delayMs)
    }

    // MARK: - Tests

    @Test("round trips and pairs FIFO")
    func roundTrip() async throws {
        let server = try #require(startEchoServer())
        defer { server.stop() }
        let client = DebugSocketClient()
        try await client.connect(path: server.path)
        #expect(try await client.execute("abc") == "cba")
        #expect(try await client.execute("123") == "321")
        await client.close()
    }

    @Test("serial calls preserve order under concurrency")
    func serialOrder() async throws {
        let server = try #require(startEchoServer())
        defer { server.stop() }
        let client = DebugSocketClient(queryTimeout: .seconds(5))
        try await client.connect(path: server.path)
        let replies = try await withThrowingTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for i in 1 ... 20 {
                group.addTask {
                    do {
                        return try (i, .success(await client.execute("q\(i)")))
                    } catch {
                        return (i, .failure(error))
                    }
                }
            }
            var out: [(Int, Result<String, Error>)] = []
            for try await pair in group { out.append(pair) }
            return out
        }
        var failures: [String] = []
        for (i, result) in replies {
            switch result {
            case .success(let reply):
                if reply != String("q\(i)".reversed()) {
                    failures.append("q\(i) → '\(reply)'")
                }
            case .failure(let error):
                failures.append("q\(i) → \(error)")
            }
        }
        #expect(failures.isEmpty, Comment(rawValue: "failed: \(failures.joined(separator: ", "))"))
        await client.close()
    }

    @Test("timeout closes the connection; same-path next call reconnects")
    func timeoutBehavior() async throws {
        let slowServer = try #require(startEchoServer(delayMs: 2_000))
        defer { slowServer.stop() }
        let client = DebugSocketClient(queryTimeout: .milliseconds(300))
        try await client.connect(path: slowServer.path)
        await #expect(throws: DebugSocketClient.ClientError.timeout) {
            _ = try await client.execute("slow")
        }
        // Same-path reconnect must work after a timeout (the client tore the
        // connection down). Drop the server delay and retry on the SAME path —
        // a different-path reconnect would mask a stale connection reference.
        slowServer.setDelayMs(0)
        #expect(try await client.execute("ko") == "ok")
        await client.close()
    }

    @Test("execute without connect fails")
    func notConnected() async {
        let client = DebugSocketClient()
        await #expect(throws: DebugSocketClient.ClientError.notConnected) {
            _ = try await client.execute("SELECT 1")
        }
    }
}
