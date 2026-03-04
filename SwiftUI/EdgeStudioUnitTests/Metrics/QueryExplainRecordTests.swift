import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("QueryExplainRecord Tests")
struct QueryExplainRecordTests {

    @Test("usedIndex is true when explainOutput contains 'Index'", .tags(.model, .fast))
    func testUsedIndexTrue() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(),
            timestamp: Date(),
            dql: "SELECT * FROM cars",
            executionTimeMs: 12.5,
            resultCount: 5,
            explainOutput: "Using Index Scan on _id"
        )

        // ASSERT
        #expect(record.usedIndex == true)
    }

    @Test("usedIndex is true for lowercase 'index'", .tags(.model, .fast))
    func testUsedIndexLowercaseTrue() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(),
            timestamp: Date(),
            dql: "SELECT * FROM cars",
            executionTimeMs: 5.0,
            resultCount: 1,
            explainOutput: "index scan on primary key"
        )

        // ASSERT
        #expect(record.usedIndex == true)
    }

    @Test("usedIndex is false for full scan output", .tags(.model, .fast))
    func testUsedIndexFalse() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(),
            timestamp: Date(),
            dql: "SELECT * FROM cars WHERE color = 'red'",
            executionTimeMs: 150.0,
            resultCount: 20,
            explainOutput: "Full collection scan"
        )

        // ASSERT
        #expect(record.usedIndex == false)
    }

    @Test("usedIndex is false for empty explainOutput", .tags(.model, .fast))
    func testUsedIndexEmptyOutput() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(),
            timestamp: Date(),
            dql: "SELECT 1",
            executionTimeMs: 1.0,
            resultCount: 1,
            explainOutput: ""
        )

        // ASSERT
        #expect(record.usedIndex == false)
    }

    @Test("initializer stores all fields correctly", .tags(.model, .fast))
    func testInitializerStoresFields() {
        // ARRANGE
        let id = UUID()
        let now = Date()
        let dql = "SELECT * FROM items LIMIT 10"
        let ms = 23.7
        let count = 10
        let explain = "Index scan on _id"

        // ACT
        let record = QueryExplainRecord(
            id: id,
            timestamp: now,
            dql: dql,
            executionTimeMs: ms,
            resultCount: count,
            explainOutput: explain
        )

        // ASSERT
        #expect(record.id == id)
        #expect(record.timestamp == now)
        #expect(record.dql == dql)
        #expect(record.executionTimeMs == ms)
        #expect(record.resultCount == count)
        #expect(record.explainOutput == explain)
    }

    @Test("formattedExecutionTime shows ms for small values", .tags(.model, .fast))
    func testFormattedExecutionTimeMs() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(), timestamp: Date(), dql: "Q", executionTimeMs: 23.4, resultCount: 0, explainOutput: ""
        )

        // ASSERT
        #expect(record.formattedExecutionTime.contains("ms"))
    }

    @Test("formattedExecutionTime shows < 1ms for sub-millisecond", .tags(.model, .fast))
    func testFormattedExecutionTimeSubMs() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(), timestamp: Date(), dql: "Q", executionTimeMs: 0.5, resultCount: 0, explainOutput: ""
        )

        // ASSERT
        #expect(record.formattedExecutionTime == "<1ms")
    }

    @Test("formattedExecutionTime shows seconds for large values", .tags(.model, .fast))
    func testFormattedExecutionTimeSeconds() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(), timestamp: Date(), dql: "Q", executionTimeMs: 2500.0, resultCount: 0, explainOutput: ""
        )

        // ASSERT
        #expect(record.formattedExecutionTime.contains("s"))
        #expect(!record.formattedExecutionTime.contains("ms"))
    }

    @Test("formattedTimestamp returns non-empty string", .tags(.model, .fast))
    func testFormattedTimestampNonEmpty() {
        // ARRANGE
        let record = QueryExplainRecord(
            id: UUID(), timestamp: Date(), dql: "Q", executionTimeMs: 1.0, resultCount: 0, explainOutput: ""
        )

        // ASSERT
        #expect(!record.formattedTimestamp.isEmpty)
    }
}
