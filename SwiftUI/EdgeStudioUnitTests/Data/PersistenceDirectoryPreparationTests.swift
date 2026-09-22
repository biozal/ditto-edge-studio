import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("Offline store upgrade adoption")
struct PersistenceDirectoryPreparationTests {
    @Test(.tags(.fast))
    func `Opening an upgraded offline database preserves its entire SDK store`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStore(at: fixture.legacy, payload: "offline documents")

        try fixture.prepare()
        // Retry follows the same production preparation path without moving again.
        try fixture.prepare()

        #expect(try fixture.readStore(at: fixture.destination) == "offline documents")
        #expect(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("attachments/blob").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.legacy.path))
    }

    @Test(.tags(.fast))
    func `An empty directory left by old hydration does not hide the legacy store`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try fixture.writeStore(at: fixture.legacy, payload: "existing data")

        try fixture.prepare()

        #expect(try fixture.readStore(at: fixture.destination) == "existing data")
        #expect(!FileManager.default.fileExists(atPath: fixture.legacy.path))
    }

    @Test(.tags(.fast))
    func `Older lowercase SDK directories are adopted too`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lowercase = fixture.legacyRoot.appendingPathComponent("ditto-\(fixture.databaseID.lowercased())")
        try fixture.writeStore(at: lowercase, payload: "older SDK data")

        try fixture.prepare()

        #expect(try fixture.readStore(at: fixture.destination) == "older SDK data")
        #expect(!FileManager.default.fileExists(atPath: lowercase.path))
    }

    @Test(.tags(.fast))
    func `Conflicting legacy and app stores fail without changing either copy`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStore(at: fixture.legacy, payload: "legacy writes")
        try fixture.writeStore(at: fixture.destination, payload: "newer writes")

        #expect(throws: PersistenceDirectoryPreparation.PreparationError.self) {
            try fixture.prepare()
        }

        #expect(try fixture.readStore(at: fixture.legacy) == "legacy writes")
        #expect(try fixture.readStore(at: fixture.destination) == "newer writes")
    }

    @Test(.tags(.fast), arguments: [AuthMode.development, .smallPeerOnly])
    func `Development and UI test opens never adopt production legacy data`(mode: AuthMode) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStore(at: fixture.legacy, payload: "untouched")

        try fixture.prepare(mode: mode, isUITesting: mode == .smallPeerOnly)

        #expect(try fixture.readStore(at: fixture.legacy) == "untouched")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
    }

    @Test(.tags(.fast))
    func `A new offline database gets an empty canonical directory`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try fixture.prepare()

        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
    }

    @Test(.tags(.fast))
    func `A non-directory destination is never overwritten`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStore(at: fixture.legacy, payload: "preserve")
        try FileManager.default.createDirectory(at: fixture.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unexpected file".utf8).write(to: fixture.destination)

        #expect(throws: PersistenceDirectoryPreparation.PreparationError.self) {
            try fixture.prepare()
        }

        #expect(try fixture.readStore(at: fixture.legacy) == "preserve")
        #expect(try String(contentsOf: fixture.destination, encoding: .utf8) == "unexpected file")
    }

    private struct Fixture {
        let root: URL
        let databaseID = "Offline-ABC"
        var legacyRoot: URL {
            root.appendingPathComponent("sdk")
        }

        var legacy: URL {
            legacyRoot.appendingPathComponent("ditto-\(databaseID)")
        }

        var destination: URL {
            root.appendingPathComponent("app/database")
        }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("store-adoption-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func prepare(mode: AuthMode = .smallPeerOnly, isUITesting: Bool = false) throws {
            // This is the exact production preparation helper called before Ditto.open.
            try PersistenceDirectoryPreparation.prepare(
                mode: mode, databaseID: databaseID, isUITesting: isUITesting,
                destination: destination, legacyRoot: legacyRoot
            )
        }

        func writeStore(at directory: URL, payload: String) throws {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: true)
            try Data(payload.utf8).write(to: directory.appendingPathComponent("documents"))
            try Data([0, 1, 2, 255]).write(to: directory.appendingPathComponent("attachments/blob"))
        }

        func readStore(at directory: URL) throws -> String {
            try String(contentsOf: directory.appendingPathComponent("documents"), encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
