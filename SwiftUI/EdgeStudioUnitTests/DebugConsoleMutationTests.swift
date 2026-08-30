import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("Debug console mutation gating")
struct DebugConsoleMutationTests {
    @Test("mutating prefixes are detected case-insensitively with leading whitespace")
    func mutatingDetected() {
        #expect(isMutatingDqlStatement("INSERT INTO t DOCUMENTS ({})"))
        #expect(isMutatingDqlStatement("  evict from t"))
        #expect(isMutatingDqlStatement("delete from t where _id = 'x'"))
        #expect(isMutatingDqlStatement("ALTER SYSTEM SET x = 1"))
        #expect(isMutatingDqlStatement("CREATE INDEX i ON t (a)"))
        #expect(isMutatingDqlStatement("update t set a = 1"))
        #expect(isMutatingDqlStatement("DROP INDEX t.i"))
    }

    @Test("select and friends do not trigger confirmation")
    func selectSkips() {
        #expect(!isMutatingDqlStatement("SELECT * FROM t"))
        #expect(!isMutatingDqlStatement("  select * from t"))
        #expect(!isMutatingDqlStatement("EXPLAIN SELECT * FROM t"))
        #expect(!isMutatingDqlStatement("ADVISE SELECT * FROM t"))
        #expect(!isMutatingDqlStatement(""))
    }
}
