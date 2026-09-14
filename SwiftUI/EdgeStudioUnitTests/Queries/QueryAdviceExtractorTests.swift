import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("QueryAdvice extractor tests")
struct QueryAdviceExtractorTests {
    private let sampleAdviceJSON = """
    {"advice": {
      "statement": "SELECT * FROM atest WHERE e=1\\n",
      "suggestedIndexes": [
        { "collection": "atest",
          "reason": "equality predicates on `e`",
          "statement": "CREATE INDEX IF NOT EXISTS adv_atest_e ON default:`atest` (`e` ASC)" }
      ]
    }}
    """

    private let noAdviceJSON = """
    {"advice": {
      "statement": "SELECT * FROM atest",
      "outcome": "no keys to advise on"
    }}
    """

    @Test("extracts statement and one suggestion from a single advice row")
    func extractsSuggestion() {
        let advice = QueryAdviceExtractor.extract(from: [sampleAdviceJSON])
        #expect(advice != nil)
        #expect(advice?.statement.hasPrefix("SELECT * FROM atest") == true)
        #expect(advice?.suggestions.count == 1)
        let s = advice?.suggestions.first
        #expect(s?.collection == "atest")
        #expect(s?.reason == "equality predicates on `e`")
        #expect(s?.statement == "CREATE INDEX IF NOT EXISTS adv_atest_e ON default:`atest` (`e` ASC)")
    }

    @Test("outcome is carried when there is nothing to advise on")
    func extractsOutcome() {
        let advice = QueryAdviceExtractor.extract(from: [noAdviceJSON])
        #expect(advice?.suggestions.isEmpty == true)
        #expect(advice?.outcome == "no keys to advise on")
    }

    @Test("returns nil for non-ADVISE result rows")
    func nonAdviseRowsYieldNil() {
        #expect(QueryAdviceExtractor.extract(from: []) == nil)
        #expect(QueryAdviceExtractor.extract(from: ["{\"_id\":\"a\"}"]) == nil)
        #expect(QueryAdviceExtractor.extract(from: ["not json"]) == nil)
    }

    @Test("merges advice across multiple rows and drops incomplete suggestions")
    func mergesAndDropsPartial() {
        let partial = """
        {"advice": {"suggestedIndexes": [
          {"collection": "onlycollection", "reason": "no statement — must be dropped"},
          {"collection": "good", "reason": "", "statement": "CREATE INDEX IF NOT EXISTS adv_good_x ON default:`good` (`x` ASC)"}
        ]}}
        """
        let second = """
        {"advice": {"statement": "SELECT * FROM good WHERE x=1"}}
        """
        let advice = QueryAdviceExtractor.extract(from: [partial, second])
        #expect(advice?.statement == "SELECT * FROM good WHERE x=1")
        #expect(advice?.suggestions.count == 1)
        #expect(advice?.suggestions.first?.collection == "good")
    }

    @Test("isAdviseStatement matches only the leading keyword")
    func adviseDetection() {
        #expect(DqlStatements.isAdviseStatement("ADVISE SELECT * FROM t"))
        #expect(DqlStatements.isAdviseStatement("  advise\nSELECT * FROM t"))
        #expect(!DqlStatements.isAdviseStatement("SELECT * FROM t"))
        #expect(!DqlStatements.isAdviseStatement("ADVISORY SELECT * FROM t"))
        #expect(!DqlStatements.isAdviseStatement(""))
    }
}
