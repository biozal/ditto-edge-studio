import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("SystemMetrics accumulator tests")
struct SystemMetricsAccumulatorTests {

    private func counterRow(_ key: String, delta: Any, labels: [String: String] = [:]) -> [String: Any] {
        var row: [String: Any] = ["key": key, "description": "desc", "unit": "", "delta": delta]
        if !labels.isEmpty { row["labels"] = labels }
        return row
    }

    private func histogramRow(_ key: String, dcount: Any, dsum: Any = 0.0) -> [String: Any] {
        ["key": key, "description": "", "unit": "secs", "dcount": dcount, "dsum": dsum]
    }

    @Test("deltas accumulate into since-connect totals")
    func deltasAccumulate() {
        var samples: [String: SystemMetricSample] = [:]
        SystemMetricsAccumulator.accumulate(rows: [counterRow("a.b.c", delta: 2)], into: &samples)
        SystemMetricsAccumulator.accumulate(rows: [counterRow("a.b.c", delta: 3)], into: &samples)
        let sample = samples.values.first
        #expect(sample?.sinceConnect == 5)
        #expect(sample?.periodDelta == 3)
    }

    @Test("label maps key separate series")
    func labelSeriesSeparate() {
        var samples: [String: SystemMetricSample] = [:]
        SystemMetricsAccumulator.accumulate(
            rows: [
                counterRow("m", delta: 1, labels: ["db": "main"]),
                counterRow("m", delta: 4, labels: ["db": "auth"]),
            ],
            into: &samples
        )
        #expect(samples.count == 2)
    }

    @Test("label order does not affect the series signature")
    func signatureStable() {
        #expect(
            SystemMetricsAccumulator.seriesSignature(key: "k", labels: ["b": "2", "a": "1"])
                == SystemMetricsAccumulator.seriesSignature(key: "k", labels: ["a": "1", "b": "2"])
        )
    }

    @Test("histograms accumulate dcount and dsum")
    func histogramAccumulation() {
        var samples: [String: SystemMetricSample] = [:]
        SystemMetricsAccumulator.accumulate(rows: [histogramRow("h", dcount: 2, dsum: 0.5)], into: &samples)
        SystemMetricsAccumulator.accumulate(rows: [histogramRow("h", dcount: 1, dsum: 0.25)], into: &samples)
        let sample = samples.values.first
        #expect(sample?.kind == .histogram)
        #expect(sample?.sinceConnect == 3)
        #expect(sample?.sumSinceConnect == 0.75)
    }

    @Test("garbage and placeholder rows are ignored")
    func garbageIgnored() {
        var samples: [String: SystemMetricSample] = [:]
        SystemMetricsAccumulator.accumulate(
            rows: [
                ["status": "disabled", "description": "x"], // placeholder
                ["key": ""], // empty key
                counterRow("ok", delta: 1.5),
            ],
            into: &samples
        )
        #expect(samples.values.map(\.key) == ["ok"])
    }

    @Test("exporter-disabled detection requires all rows keyless plus disabled status")
    func exporterDisabledDetection() {
        #expect(SystemMetricsAccumulator.isExporterDisabled(rows: [["status": "disabled"]]))
        #expect(SystemMetricsAccumulator.isExporterDisabled(rows: []) == false)
        #expect(SystemMetricsAccumulator.isExporterDisabled(rows: [counterRow("k", delta: 1)]) == false)
        #expect(
            SystemMetricsAccumulator.isExporterDisabled(
                rows: [["status": "disabled"], counterRow("k", delta: 1)]
            ) == false
        )
    }

    @Test("non-finite deltas read as zero")
    func nonFiniteDeltas() {
        var samples: [String: SystemMetricSample] = [:]
        SystemMetricsAccumulator.accumulate(rows: [counterRow("k", delta: Double.nan)], into: &samples)
        #expect(samples.values.first?.sinceConnect == 0)
    }
}
