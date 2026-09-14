import DittoSwift
import Foundation

/// Loads, validates and persists the log-analysis pattern catalog (parity port
/// of the VS Code extension's `PatternStore`).
///
/// Sources:
/// - **Bundled** — `problem_patterns.json` in the app bundle (read-only catalog
///   of known Ditto problem signatures).
/// - **User** — `~/Library/Application Support/ditto_edge_studio/log-analyzer/user_patterns.json`.
///
/// A user pattern cannot reuse a bundled key. Invalid entries are dropped from
/// `patterns` and reported via `patternErrors`; a missing/corrupt user file is
/// tolerated (empty catalog).
@MainActor @Observable
final class LogPatternStore {
    /// Validated patterns by key (bundled + user).
    private(set) var patterns: [String: LogPattern] = [:]

    /// key → rejection reason for entries that failed validation.
    private(set) var patternErrors: [String: String] = [:]

    /// Bumped on every catalog change so views can re-run scans.
    private(set) var revision = 0

    var bundledKeys: Set<String> {
        Set(bundledBodies().keys)
    }

    private let bundledResourceURL: URL?
    private let userPatternsFileURL: URL

    /// - Parameters:
    ///   - bundledResourceURL: defaults to the bundled `problem_patterns.json`.
    ///   - userPatternsFileURL: defaults to the app-support `log-analyzer` location;
    ///     injectable for tests.
    init(
        bundledResourceURL: URL? = Bundle.main.url(forResource: "problem_patterns", withExtension: "json"),
        userPatternsFileURL: URL? = nil
    ) {
        self.bundledResourceURL = bundledResourceURL
        if let userPatternsFileURL {
            self.userPatternsFileURL = userPatternsFileURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.userPatternsFileURL = appSupport
                .appendingPathComponent("ditto_edge_studio", isDirectory: true)
                .appendingPathComponent("log-analyzer", isDirectory: true)
                .appendingPathComponent("user_patterns.json")
        }
        reload()
    }

    enum StoreError: Error, LocalizedError {
        case collidesWithBundledKey(String)
        case patternAlreadyExists(String)
        case notAUserPattern(String)

        var errorDescription: String? {
            switch self {
            case let .collidesWithBundledKey(key):
                return "'\(key)' collides with a bundled pattern"
            case let .patternAlreadyExists(key):
                return "a pattern with key '\(key)' already exists"
            case let .notAUserPattern(key):
                return "'\(key)' is not a user pattern"
            }
        }
    }

    // MARK: - Loading

    private func decode(_ url: URL) -> [String: LogPatternBody] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: LogPatternBody].self, from: data)) ?? [:]
    }

    private func bundledBodies() -> [String: LogPatternBody] {
        guard let bundledResourceURL else { return [:] }
        return decode(bundledResourceURL)
    }

    private func userBodies() -> [String: LogPatternBody] {
        decode(userPatternsFileURL)
    }

    /// Re-reads both sources — call after external edits of the user file.
    func reload() {
        var errors: [String: String] = [:]
        var out: [String: LogPattern] = [:]

        func addAll(_ bodies: [String: LogPatternBody], source: PatternSource) {
            for (key, body) in bodies {
                if let reason = LogPatternEngine.rejectReason(key: key, body: body, source: source) {
                    errors[key] = reason
                    continue
                }
                out[key] = LogPattern(
                    key: key,
                    body: body,
                    levelFilter: parseLogLevelFilter(body.levelFilter),
                    source: source
                )
            }
        }

        addAll(bundledBodies(), source: .bundled)
        // User patterns may override bundled by key only via hand-editing the file
        // (parity with the extension); add/update forbid bundled-key collisions.
        addAll(userBodies(), source: .user)

        patterns = out
        patternErrors = errors
        revision += 1
    }

    // MARK: - CRUD

    func add(key: String, body: LogPatternBody) throws {
        let resolvedKey = key.trimmingCharacters(in: .whitespaces)
        guard !bundledKeys.contains(resolvedKey) else {
            throw StoreError.collidesWithBundledKey(resolvedKey)
        }
        var users = userBodies()
        guard users[resolvedKey] == nil else {
            throw StoreError.patternAlreadyExists(resolvedKey)
        }
        users[resolvedKey] = body
        try writeUser(users)
        reload()
    }

    func update(key: String, body: LogPatternBody) throws {
        var users = userBodies()
        guard users[key] != nil else { throw StoreError.notAUserPattern(key) }
        users[key] = body
        try writeUser(users)
        reload()
    }

    func delete(key: String) throws {
        var users = userBodies()
        guard users.removeValue(forKey: key) != nil else {
            throw StoreError.notAUserPattern(key)
        }
        try writeUser(users)
        reload()
    }

    private func writeUser(_ bodies: [String: LogPatternBody]) throws {
        let directory = userPatternsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySorted.encode(bodies)
        try data.write(to: userPatternsFileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
