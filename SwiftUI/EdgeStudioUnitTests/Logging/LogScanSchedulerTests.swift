import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("Log scan cadence")
@MainActor
struct LogScanSchedulerTests {
    @Test
    func `sustained batches produce repeated scans of the latest value without a quiet period`() async {
        var latestBatch = 0
        var completedWindows = 0
        var scannedBatches: [Int] = []

        await LogScanScheduler.run(
            sleep: {
                guard completedWindows < 4 else { throw CancellationError() }
                // A deterministic 500 ms window with batches at 250 ms and 500 ms.
                // There is no quiet window before any of these four scans.
                latestBatch += 1
                await Task.yield()
                latestBatch += 1
                completedWindows += 1
            },
            input: { latestBatch },
            scan: { scannedBatches.append($0); return true }
        )

        #expect(scannedBatches == [2, 4, 6, 8])
    }

    @Test
    func `unchanged input is skipped, pause freezes output, and resume scans the latest input`() async {
        // nil represents the exact pause signal supplied by LoggingDetailView.
        let windows: [Int?] = [1, 1, nil, nil, 3, 3, nil, 3]
        var index = 0
        var latest: Int?
        var scanned: [Int] = []

        await LogScanScheduler.run(
            sleep: {
                guard index < windows.count else { throw CancellationError() }
                latest = windows[index]
                index += 1
            },
            input: { latest },
            scan: { scanned.append($0); return true }
        )

        #expect(scanned == [1, 3, 3])
    }

    @Test
    func `a result discarded during a scan is retried without requiring another batch`() async {
        var ticks = 0
        var attempts = 0
        await LogScanScheduler.run(
            sleep: {
                guard ticks < 3 else { throw CancellationError() }
                ticks += 1
            },
            input: { 1 },
            scan: { _ in
                attempts += 1
                return attempts > 1
            }
        )
        #expect(attempts == 2)
    }

    @Test
    func `a cancelled wait never starts another scan`() async {
        var scanned = false
        await LogScanScheduler.run(
            sleep: { throw CancellationError() },
            input: { 1 },
            scan: { _ in scanned = true; return true }
        )
        #expect(!scanned)
    }
}
