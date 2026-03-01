import Foundation

actor QueryMetricsRepository {
    static let shared = QueryMetricsRepository()

    private let maxRecords = 200
    private var records: [QueryExplainRecord] = []

    init() {}

    func capture(dql: String, executionTimeMs: Double, resultCount: Int, explainOutput: String) {
        let record = QueryExplainRecord(
            id: UUID(),
            timestamp: Date(),
            dql: dql,
            executionTimeMs: executionTimeMs,
            resultCount: resultCount,
            explainOutput: explainOutput
        )
        records.append(record)
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
    }

    func allRecords() -> [QueryExplainRecord] {
        Array(records.reversed())
    }

    func clearRecords() {
        records = []
    }
}
