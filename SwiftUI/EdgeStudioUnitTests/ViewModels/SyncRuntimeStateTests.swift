import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Covers `SyncRuntimeState` — the single source of truth behind
/// `SyncStatusViewModel.isSyncEnabled`, written only by `DittoManager.startSyncNow` /
/// `stopSyncNow`.
///
/// **Production path these cover.** The funnels are the only writers
/// (`DittoManager.startSyncNow` / `stopSyncNow`) and both publish *after* the SDK call
/// returns:
/// `startSyncNow` after a non-throwing `Task.detached { try ditto.sync.start() }.value`,
/// `stopSyncNow` unconditionally. What is testable without a live `Ditto` is the
/// state machine those calls drive — that a stop published over an already-stopped
/// session still reads `false` (the funnel publishes unconditionally, and a stop that
/// threw would land here identically), and that the write is not reachable from a view.
/// The live-instance half is recorded as known-unverified in the remediation plan §10;
/// `SyncStatusViewModelTests` covers the read side through the view model.
@Suite("SyncRuntimeState — the single writer", .serialized)
struct SyncRuntimeStateTests {
    @Test(.tags(.fast))
    @MainActor
    func `a fresh state reports sync stopped`() {
        // ARRANGE / ACT
        let runtime = SyncRuntimeState()

        // ASSERT — never an optimistic `true`. The hard-coded `true` this replaced was
        // wrong from the first frame whenever an open or a restart failed.
        #expect(runtime.isRunning == false)
    }

    @Test(.tags(.fast))
    @MainActor
    func `publishing a start then a stop moves the state both ways`() {
        // ARRANGE
        let runtime = SyncRuntimeState()

        // ACT / ASSERT — mirrors startSyncNow's publish-after-success.
        runtime.setRunning(true)
        #expect(runtime.isRunning)

        // ACT / ASSERT — mirrors stopSyncNow's unconditional publish.
        runtime.setRunning(false)
        #expect(runtime.isRunning == false)
    }

    /// `stopSyncNow` publishes `false` whether or not the SDK call succeeded, and it can
    /// run on a session that is already stopped — every abort path does exactly that
    /// (`hydrate`'s post-condition, the two Phase 4 identity guards,
    /// `closeDittoSelectedDatabase`). Re-publishing the value it already holds must be a
    /// no-op, not a state that ends up disagreeing with reality.
    @Test(.tags(.fast))
    @MainActor
    func `a repeated stop leaves sync reported as stopped`() {
        // ARRANGE
        let runtime = SyncRuntimeState()
        runtime.setRunning(true)

        // ACT
        runtime.setRunning(false)
        runtime.setRunning(false)

        // ASSERT
        #expect(runtime.isRunning == false)
    }

    /// A start published twice — reachable when a restart follows a transport change on a
    /// session that never actually stopped — must not toggle anything off.
    @Test(.tags(.fast))
    @MainActor
    func `a repeated start leaves sync reported as running`() {
        // ARRANGE
        let runtime = SyncRuntimeState()

        // ACT
        runtime.setRunning(true)
        runtime.setRunning(true)

        // ASSERT
        #expect(runtime.isRunning)
    }

    /// Tests inject their own instance; the seeded initialiser is what lets a test set up
    /// a running session without reaching for `.shared`, which would leak state across
    /// suites.
    @Test(.tags(.fast))
    @MainActor
    func `the seeded initialiser reports the value it was given`() {
        // ARRANGE / ACT
        let running = SyncRuntimeState(isRunning: true)
        let stopped = SyncRuntimeState(isRunning: false)

        // ASSERT
        #expect(running.isRunning)
        #expect(stopped.isRunning == false)
    }
}
