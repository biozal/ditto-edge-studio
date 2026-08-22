import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers what `initialize()` does with its connection handle when it fails **after** the
/// open succeeds.
///
/// **Production path this covers.** `ContentView.sqlCipherInitErrorView` is shown when
/// `loadApps` sees an initialization failure, and its Retry button
/// (`ContentView.swift:511-518`) calls `loadApps` → `initialize()` again. `_isInitialized`
/// is only set on the success path, so every press re-enters, re-opens, and — before this
/// fix — overwrote `db`, abandoning the previous connection along with its file
/// descriptor, its WAL/SHM references and its lock. A failing migration or an unreadable
/// store never clears on its own, so repeated Retry is exactly what the UI invites.
@Suite("SQLCipherService — failed initialize releases its handle", .serialized)
struct SQLCipherInitFailureTests {
    /// Creates an isolated store directory containing a file that is *not* a SQLite
    /// database. `sqlite3_open` succeeds against it (it opens lazily); the first statement
    /// that actually reads a page — `verifyEncryption`, which reads `sqlite_master` — fails.
    /// That is a post-open failure, which is the only kind that can leak.
    private func makeServiceOverCorruptFile() throws -> (SQLCipherService, URL) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dirName = "ditto_test_initfail_\(UUID().uuidString)"
        let dirURL = appSupport.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try Data("this is definitely not a SQLite database".utf8)
            .write(to: dirURL.appendingPathComponent("ditto_encrypted.db"))
        return (SQLCipherService(testPath: dirName), dirURL)
    }

    @Test(.tags(.integration))
    func `a failed initialize leaves no open connection behind`() async throws {
        // ARRANGE
        let (service, dirURL) = try makeServiceOverCorruptFile()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        // ACT
        await #expect(throws: (any Error).self) {
            try await service.initialize()
        }

        // ASSERT — the handle was closed and cleared, not abandoned.
        #expect(await service.hasOpenConnectionForTesting == false)
    }

    /// The Retry loop, five presses of it. Each press re-enters `initialize()`; each must
    /// leave nothing behind, because nothing in the UI stops a user pressing it again.
    @Test(.tags(.integration))
    func `repeated Retry presses do not accumulate connections`() async throws {
        // ARRANGE
        let (service, dirURL) = try makeServiceOverCorruptFile()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        for press in 1 ... 5 {
            // ACT
            await #expect(throws: (any Error).self) {
                try await service.initialize()
            }

            // ASSERT
            #expect(
                await service.hasOpenConnectionForTesting == false,
                "Retry press \(press) leaked its connection handle"
            )
        }
    }

    /// The failure must stay a failure: releasing the handle must not accidentally mark the
    /// service usable, which would let queries run against a nil connection.
    @Test(.tags(.integration))
    func `a failed initialize does not report the service as initialized`() async throws {
        // ARRANGE
        let (service, dirURL) = try makeServiceOverCorruptFile()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        // ACT
        await #expect(throws: (any Error).self) {
            try await service.initialize()
        }

        // ASSERT — a second call must still attempt (and fail) rather than return early.
        await #expect(throws: (any Error).self) {
            try await service.initialize()
        }
    }
}
