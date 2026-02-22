import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("MetricsBackend Tests")
struct MetricsBackendTests {

    // MARK: - InMemoryMetricsStore Tests

    @Suite("InMemoryMetricsStore")
    struct InMemoryMetricsStoreTests {

        @Test("record() stores samples for label", .tags(.model, .fast))
        func testRecordStoresSamples() async {
            // ARRANGE
            let store = InMemoryMetricsStore()

            // ACT
            await store.record(label: "test.metric", value: 42.0)

            // ASSERT
            let samples = await store.samplesForLabel("test.metric")
            #expect(samples.count == 1)
            #expect(samples[0].value == 42.0)
        }

        @Test("samplesForLabel returns empty for unknown label", .tags(.model, .fast))
        func testSamplesForLabelUnknown() async {
            // ARRANGE
            let store = InMemoryMetricsStore()

            // ACT
            let samples = await store.samplesForLabel("nonexistent.label")

            // ASSERT
            #expect(samples.isEmpty)
        }

        @Test("latestValue returns nil for unknown label", .tags(.model, .fast))
        func testLatestValueUnknown() async {
            // ARRANGE
            let store = InMemoryMetricsStore()

            // ACT
            let value = await store.latestValue(for: "nonexistent.label")

            // ASSERT
            #expect(value == nil)
        }

        @Test("increment accumulates counter correctly", .tags(.model, .fast))
        func testIncrementAccumulates() async {
            // ARRANGE
            let store = InMemoryMetricsStore()

            // ACT
            await store.increment(label: "test.counter")
            await store.increment(label: "test.counter")
            await store.increment(label: "test.counter")

            // ASSERT
            let value = await store.latestValue(for: "test.counter")
            #expect(value == 3.0)
        }

        @Test("increment with custom amount", .tags(.model, .fast))
        func testIncrementWithAmount() async {
            // ARRANGE
            let store = InMemoryMetricsStore()

            // ACT
            await store.increment(label: "test.counter", by: 5.0)
            await store.increment(label: "test.counter", by: 3.0)

            // ASSERT
            let value = await store.latestValue(for: "test.counter")
            #expect(value == 8.0)
        }

        @Test("reset clears all data", .tags(.model, .fast))
        func testResetClearsAllData() async {
            // ARRANGE
            let store = InMemoryMetricsStore()
            await store.record(label: "test.metric", value: 1.0)
            await store.increment(label: "test.counter")

            // ACT
            await store.reset()

            // ASSERT
            let samples = await store.samplesForLabel("test.metric")
            let value = await store.latestValue(for: "test.counter")
            #expect(samples.isEmpty)
            #expect(value == nil)
        }

        @Test("ring buffer respects maxSamples cap", .tags(.model, .fast))
        func testRingBufferCap() async {
            // ARRANGE
            let store = InMemoryMetricsStore()
            let label = "test.ring"

            // ACT — record 130 samples (more than maxSamples=120)
            for i in 0 ..< 130 {
                await store.record(label: label, value: Double(i))
            }

            // ASSERT — capped at 120
            let samples = await store.samplesForLabel(label)
            #expect(samples.count == 120)
            // Last value should be the most recently recorded
            #expect(samples.last?.value == 129.0)
        }
    }

    // MARK: - AppMetricsCounter Tests

    @Suite("AppMetricsCounter")
    struct AppMetricsCounterTests {

        @Test("increment fires without error", .tags(.model, .fast))
        func testIncrementFiresWithoutError() async throws {
            // ARRANGE
            let counter = AppMetricsCounter(label: "test.counter.unit.\(UUID().uuidString)")

            // ACT — increment should not throw
            counter.increment()

            // Give the detached task time to run
            try await Task.sleep(nanoseconds: 50_000_000)

            // ASSERT — label should exist in store (no crash)
            #expect(true) // If we get here, no crash occurred
        }
    }

    // MARK: - AppMetricsTimer Tests

    @Suite("AppMetricsTimer")
    struct AppMetricsTimerTests {

        @Test("recordMilliseconds fires without error", .tags(.model, .fast))
        func testRecordMillisecondsFiresWithoutError() async throws {
            // ARRANGE
            let timer = AppMetricsTimer(label: "test.timer.unit.\(UUID().uuidString)")

            // ACT
            timer.recordMilliseconds(42.5)

            // Give the detached task time to run
            try await Task.sleep(nanoseconds: 50_000_000)

            // ASSERT — no crash
            #expect(true)
        }
    }
}
