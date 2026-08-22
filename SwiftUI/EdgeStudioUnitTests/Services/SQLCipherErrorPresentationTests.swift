import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers how `SQLCipherError` reaches a person — `localizedDescription`, not
/// `String(describing:)`.
///
/// **Production path these cover.** Both render sites read `localizedDescription`:
/// `ContentView.sqlCipherInitErrorView` (`ContentView.swift:509`, the storage-unavailable
/// screen with the Retry button) and the app-level alert's `else` branch
/// (`Ditto_Edge_StudioApp.swift:128`), which is where every error that is not an
/// `AppError` lands. `CustomStringConvertible` alone did not reach either: the NSError
/// bridge ignores it, so the user saw "The operation couldn't be completed. (… error N.)"
/// — including for `keyFileUnreadable`, whose whole purpose is to explain that the key was
/// deliberately *not* regenerated.
@Suite("SQLCipherError — user-facing text", .serialized)
struct SQLCipherErrorPresentationTests {
    /// The regression guard: the generic bridge text must not come back. Asserted on the
    /// substring Foundation uses for an un-localized error, so this fails if the
    /// `LocalizedError` conformance is removed.
    @Test(.tags(.fast))
    func `localizedDescription is not the generic NSError text`() {
        // ARRANGE
        let error = SQLCipherError.keyFileUnreadable(reason: "permission denied")

        // ACT
        let text = error.localizedDescription

        // ASSERT
        #expect(!text.contains("The operation couldn't be completed"))
        #expect(text.contains("key file could not be read"))
        #expect(text.contains("permission denied"))
        #expect(
            text.contains("not regenerated automatically"),
            "the guidance that makes this error non-destructive must survive to the UI"
        )
        #expect(
            !text.contains("permanently unreadable"),
            "the old wording claimed a consequence that is false while the store is plaintext"
        )
    }

    /// One text, not two that drift: `errorDescription` returns `description`.
    @Test(.tags(.fast))
    func `every case renders the same text through both conformances`() {
        // ARRANGE — one instance per case, so a new case added without a `description`
        // arm cannot slip through.
        let errors: [SQLCipherError] = [
            .databaseOpenFailed(code: 14),
            .encryptionVerificationFailed(message: "file is not a database"),
            .pragmaFailed(pragma: "PRAGMA key", error: "not authorized"),
            .keyGenerationFailed,
            .keyFileWriteFailed(code: -25299),
            .keyFileUnreadable(reason: "permission denied"),
            .queryFailed(sql: "updateDatabaseConfig", error: "no database configuration matched _id 7"),
            .executeFailed(sql: "INSERT INTO databaseConfigs", error: "UNIQUE constraint failed: databaseConfigs.databaseId"),
            .unsupportedParameterType(type: "CGRect"),
            .notImplemented(feature: "vacuum")
        ]

        for error in errors {
            // ACT / ASSERT
            #expect(error.localizedDescription == error.description)
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    /// The key never reaches the user-facing text or the log file. `PRAGMA key = '<64 hex>'`
    /// runs through `executePragma`, and since this enum gained `LocalizedError` its text goes
    /// to an alert *and* to `~/Library/Logs/io.ditto.EdgeStudio/`, the log users attach to
    /// GitHub issues. Found by the pre-commit review.
    @Test(.tags(.fast))
    func `a failing key pragma does not put the key in its message`() {
        // ARRANGE — the shape `initialize()` builds, with a plausible 64-hex key.
        let key = String(repeating: "ab", count: 32)
        let redacted = SQLCipherService.redactedPragma("PRAGMA key = '\(key)'")
        let error = SQLCipherError.pragmaFailed(pragma: redacted, error: "unable to open database file")

        // ACT
        let text = error.localizedDescription

        // ASSERT — the statement is still identifiable, the secret is not in it.
        #expect(!text.contains(key), "the encryption key must never reach an alert or a log file")
        #expect(text.contains("<redacted>"))
        #expect(text.contains("PRAGMA key"))
    }

    /// Redaction must not swallow the useful half: a non-secret pragma still names itself.
    @Test(.tags(.fast))
    func `a non-secret pragma is reported verbatim`() {
        // ARRANGE / ACT
        let redacted = SQLCipherService.redactedPragma("PRAGMA journal_mode = WAL")

        // ASSERT
        #expect(redacted == "PRAGMA journal_mode = WAL")
    }

    /// The duplicate-Database-ID case named in the finding: registering an id that already
    /// exists trips the UNIQUE index, and the SQLite message is what tells the user which
    /// constraint failed. It has to survive the bridge to be worth anything.
    @Test(.tags(.fast))
    func `the duplicate Database ID message survives to the UI`() {
        // ARRANGE
        let error = SQLCipherError.executeFailed(
            sql: "INSERT INTO databaseConfigs",
            error: "UNIQUE constraint failed: databaseConfigs.databaseId"
        )

        // ACT / ASSERT
        #expect(error.localizedDescription.contains("databaseConfigs.databaseId"))
    }
}
