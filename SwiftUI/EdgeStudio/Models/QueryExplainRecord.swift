import Foundation

struct QueryExplainRecord: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let dql: String
    let executionTimeMs: Double
    let resultCount: Int
    let explainOutput: String

    var usedIndex: Bool {
        explainOutput.lowercased().contains("index")
    }

    private static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm:ss.SSS"
        return fmt
    }()

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    var formattedExecutionTime: String {
        if executionTimeMs < 1.0 { return "<1ms" }
        if executionTimeMs < 1000.0 { return String(format: "%.1fms", executionTimeMs) }
        return String(format: "%.2fs", executionTimeMs / 1000.0)
    }
}
