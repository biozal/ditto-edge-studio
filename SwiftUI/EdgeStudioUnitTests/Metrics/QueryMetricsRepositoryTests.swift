import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("QueryMetricsRepository Tests")
struct QueryMetricsRepositoryTests {

    // Each test uses its own fresh repository instance to avoid shared state
    private func makeRepository() -> QueryMetricsRepository {
        QueryMetricsRepository()
    }

    @Test("allRecords is empty initially", .tags(.repository, .fast))
    func testAllRecordsEmptyInitially() async {
        // ARRANGE
        let repo = makeRepository()

        // ACT
        let records = await repo.allRecords()

        // ASSERT
        #expect(records.isEmpty)
    }

    @Test("capture adds a record", .tags(.repository, .fast))
    func testCaptureAddsRecord() async {
        // ARRANGE
        let repo = makeRepository()

        // ACT
        await repo.capture(
            dql: "SELECT * FROM cars",
            executionTimeMs: 12.5,
            resultCount: 5,
            explainOutput: "Index scan"
        )

        // ASSERT
        let records = await repo.allRecords()
        #expect(records.count == 1)
        #expect(records[0].dql == "SELECT * FROM cars")
        #expect(records[0].executionTimeMs == 12.5)
        #expect(records[0].resultCount == 5)
        #expect(records[0].explainOutput == "Index scan")
    }

    @Test("allRecords returns most recent first (reversed order)", .tags(.repository, .fast))
    func testAllRecordsMostRecentFirst() async {
        // ARRANGE
        let repo = makeRepository()

        // ACT
        await repo.capture(dql: "SELECT 1", executionTimeMs: 1.0, resultCount: 1, explainOutput: "")
        await repo.capture(dql: "SELECT 2", executionTimeMs: 2.0, resultCount: 2, explainOutput: "")
        await repo.capture(dql: "SELECT 3", executionTimeMs: 3.0, resultCount: 3, explainOutput: "")

        // ASSERT
        let records = await repo.allRecords()
        #expect(records.count == 3)
        // Most recent (SELECT 3) should be first
        #expect(records[0].dql == "SELECT 3")
        #expect(records[2].dql == "SELECT 1")
    }

    @Test("clearRecords empties the store", .tags(.repository, .fast))
    func testClearRecords() async {
        // ARRANGE
        let repo = makeRepository()
        await repo.capture(dql: "SELECT * FROM items", executionTimeMs: 5.0, resultCount: 10, explainOutput: "")

        // ACT
        await repo.clearRecords()

        // ASSERT
        let records = await repo.allRecords()
        #expect(records.isEmpty)
    }

    @Test("respects maxRecords cap of 200", .tags(.repository, .fast))
    func testMaxRecordsCap() async {
        // ARRANGE
        let repo = makeRepository()

        // ACT — insert 210 records (10 more than max)
        for i in 0 ..< 210 {
            await repo.capture(
                dql: "SELECT \(i)",
                executionTimeMs: Double(i),
                resultCount: i,
                explainOutput: ""
            )
        }

        // ASSERT — capped at 200
        let records = await repo.allRecords()
        #expect(records.count == 200)
        // Most recent (SELECT 209) should be first
        #expect(records[0].dql == "SELECT 209")
    }

    @Test("captured record has non-nil UUID", .tags(.repository, .fast))
    func testCapturedRecordHasUUID() async {
        // ARRANGE
        let repo = makeRepository()

        // ACT
        await repo.capture(dql: "SELECT 1", executionTimeMs: 1.0, resultCount: 1, explainOutput: "")

        // ASSERT
        let records = await repo.allRecords()
        #expect(records[0].id != UUID.init()) // UUID is not the zero UUID
        #expect(records.count == 1)
    }

    @Test("captured record has recent timestamp", .tags(.repository, .fast))
    func testCapturedRecordHasRecentTimestamp() async {
        // ARRANGE
        let before = Date()
        let repo = makeRepository()

        // ACT
        await repo.capture(dql: "SELECT 1", executionTimeMs: 1.0, resultCount: 0, explainOutput: "")
        let after = Date()

        // ASSERT
        let records = await repo.allRecords()
        #expect(records[0].timestamp >= before)
        #expect(records[0].timestamp <= after)
    }
}
