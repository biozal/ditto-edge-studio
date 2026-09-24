import Foundation

/// A lifecycle-owned scan cadence. Input changes replace the value read on the next
/// tick; they never restart its delay, so sustained log ingestion cannot starve scans.
@MainActor
enum LogScanScheduler {
    static func run<Input: Equatable>(
        sleep: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) },
        input: @MainActor () -> Input?,
        scan: @MainActor (Input) async -> Bool
    ) async {
        var previous: Input?
        while !Task.isCancelled {
            do {
                try await sleep()
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let latest = input() else {
                // Pause freezes the display; resuming must scan even if no logs arrived.
                previous = nil
                continue
            }
            guard latest != previous else { continue }
            // A scan can be discarded if the user pauses or switches sources
            // while it is in flight. Retry that input if it is still current.
            previous = await scan(latest) ? latest : nil
        }
    }
}
