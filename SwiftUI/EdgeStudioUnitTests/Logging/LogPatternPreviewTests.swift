import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("Log pattern preview safety")
struct LogPatternPreviewTests {
    @Test
    func `preview rejects a nested message quantifier before matching`() {
        let body = validBody(pattern: "^(a+)+$")
        // This short matching input is safe even on the regressed implementation,
        // where it returns true. Rejection must happen before any input is matched.
        #expect(!LogPatternEngine.testMatch(body: body, level: .info, tag: "Sync", message: "a"))
    }

    @Test
    func `preview rejects a nested tag quantifier before matching`() {
        let body = LogPatternBody(pattern: "hello", severity: 3, recommendation: "fix", tagFilter: "^(a+)+$")
        #expect(!LogPatternEngine.testMatch(body: body, level: .info, tag: "a", message: "hello"))
    }

    @Test
    func `preview enforces the user pattern length cap`() {
        let text = String(repeating: "a", count: LogPatternEngine.maxUserPatternLength + 1)
        #expect(!LogPatternEngine.testMatch(body: validBody(pattern: text), level: .info, tag: "Sync", message: text))
    }

    private func validBody(pattern: String) -> LogPatternBody {
        LogPatternBody(pattern: pattern, severity: 3, recommendation: "fix it")
    }
}
