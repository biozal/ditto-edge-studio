import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogPatternStore Tests")
struct LogPatternStoreTests {
    private let bundledJSON = """
    {
      "deadlock_critical": {
        "pattern": "(?:deadlock|write transaction).*elapsed",
        "level_filter": "error",
        "severity": 5,
        "recommendation": "Possible deadlock."
      },
      "memory_oom": {
        "pattern": "out of memory|OOMKiller",
        "severity": 4,
        "recommendation": "Memory pressure detected."
      }
    }
    """

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logpatternstore-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeStore(
        in dir: URL,
        bundled: String? = nil
    ) throws -> LogPatternStore {
        var bundledURL: URL?
        if let bundled {
            let url = dir.appendingPathComponent("problem_patterns.json")
            try bundled.write(to: url, atomically: true, encoding: .utf8)
            bundledURL = url
        }
        return LogPatternStore(
            bundledResourceURL: bundledURL,
            userPatternsFileURL: dir
                .appendingPathComponent("log-analyzer", isDirectory: true)
                .appendingPathComponent("user_patterns.json")
        )
    }

    private func userPattern(_ name: String = "boom") -> LogPatternBody {
        LogPatternBody(pattern: name, severity: 2, recommendation: "deal with \(name)")
    }

    @Test("bundled patterns load with parsed level filter and source")
    @MainActor
    func bundledLoad() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)

        let p = store.patterns["deadlock_critical"]
        #expect(p?.source == .bundled)
        #expect(p?.levelFilter == DittoLogLevel.error)
        #expect(p?.severity == 5)
        #expect(store.patternErrors.isEmpty)
    }

    @Test("missing bundled resource yields empty catalog without crashing")
    @MainActor
    func missingBundled() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: nil)
        #expect(store.patterns.isEmpty)
    }

    @Test("corrupt bundled json yields empty catalog")
    @MainActor
    func corruptBundled() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: "{ not json")
        #expect(store.patterns.isEmpty)
    }

    @Test("invalid bundled entries are dropped and reported")
    @MainActor
    func invalidBundledReported() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(
            in: dir,
            bundled: """
            { "bad_severity": { "pattern": "x", "severity": 9, "recommendation": "r" } }
            """
        )
        #expect(store.patterns.isEmpty)
        #expect(store.patternErrors.keys.sorted() == ["bad_severity"])
    }

    @Test("missing user file is tolerated")
    @MainActor
    func missingUserFile() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        #expect(store.patterns.count == 2)
    }

    @Test("corrupt user file is tolerated and bundled still loads")
    @MainActor
    func corruptUserFile() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userDir = dir.appendingPathComponent("log-analyzer", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "not json {".write(
            to: userDir.appendingPathComponent("user_patterns.json"),
            atomically: true,
            encoding: .utf8
        )
        let store = try makeStore(in: dir, bundled: bundledJSON)
        #expect(store.patterns.count == 2)
    }

    @Test("add persists user pattern and survives a fresh store instance")
    @MainActor
    func addPersists() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        try store.add(key: "my_rule", body: userPattern())
        #expect(store.patterns["my_rule"]?.source == .user)

        let reloaded = try makeStore(in: dir, bundled: bundledJSON)
        #expect(reloaded.patterns["my_rule"] != nil)
    }

    @Test("add rejects bundled key collision and duplicate user keys")
    @MainActor
    func addRejectsDuplicates() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        #expect(throws: LogPatternStore.StoreError.self) {
            try store.add(key: "deadlock_critical", body: userPattern())
        }
        try store.add(key: "my_rule", body: userPattern())
        #expect(throws: LogPatternStore.StoreError.self) {
            try store.add(key: "my_rule", body: userPattern("other"))
        }
    }

    @Test("update changes an existing user pattern only")
    @MainActor
    func updateUserOnly() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        try store.add(key: "my_rule", body: userPattern())
        try store.update(key: "my_rule", body: userPattern("kaboom"))
        #expect(store.patterns["my_rule"]?.body.pattern == "kaboom")

        #expect(throws: LogPatternStore.StoreError.self) {
            try store.update(key: "deadlock_critical", body: userPattern())
        }
    }

    @Test("delete removes only user patterns")
    @MainActor
    func deleteUserOnly() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        try store.add(key: "my_rule", body: userPattern())
        try store.delete(key: "my_rule")
        #expect(store.patterns["my_rule"] == nil)
        #expect(throws: LogPatternStore.StoreError.self) {
            try store.delete(key: "deadlock_critical")
        }
        #expect(store.patterns["deadlock_critical"] != nil)
    }

    @Test("reload picks up externally edited user file and bumps revision")
    @MainActor
    func reloadExternal() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir, bundled: bundledJSON)
        let before = store.revision

        let userDir = dir.appendingPathComponent("log-analyzer", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try #"{ "external": { "pattern": "e", "severity": 1, "recommendation": "r" } }"#
            .write(to: userDir.appendingPathComponent("user_patterns.json"), atomically: true, encoding: .utf8)

        store.reload()
        #expect(store.patterns["external"] != nil)
        #expect(store.revision > before)
    }
}
