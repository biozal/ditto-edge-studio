import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Validates the Sync-tab callback wiring across a transport-settings apply.
///
/// Original claim (two independent reviewers, rounds 1 and 2 — CONFIRMED
/// empirically by the first version of this suite, which failed exactly as
/// predicted): the transport-apply path used `SystemRepository.stopObserver()`
/// — the full session teardown — which clears the `onSyncStatusUpdate` /
/// `onConnectionsUpdate` dispatch callbacks that
/// `SyncStatusViewModel.installCallbacks()` installs exactly once at database
/// open (MainStudioViewModel.performLoad). Nothing re-installed them
/// mid-session, so every subsequent presence emission queued as "pending"
/// against a nil callback (processSyncStatusUpdate's nil guard) — the Peers
/// grid and transport counts froze until the database was closed and reopened.
///
/// The fix (landing here as the already-remote `pauseObservers()`, which this
/// suite pins): the apply paths stop the SDK observers and reset the pipeline
/// while preserving the session-scoped callbacks. These tests pin both halves
/// of that contract.
///
/// Emissions are driven through `processSyncStatusUpdate` directly (made
/// internal for this purpose) because the SDK presence observer that normally
/// feeds it requires a live Ditto instance — see the integration-test stub in
/// SystemRepositoryTests. `.serialized` because SystemRepository is a shared
/// singleton; the tests restore clean state on exit.
@Suite("Transport apply — Sync tab callback wiring", .serialized)
struct TransportApplyCallbackWiringTests {
    /// Invocation counter shared between the test body and the @MainActor
    /// callback hop.
    private final class CallbackRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations = 0
        func increment() {
            lock.lock()
            invocations += 1
            lock.unlock()
        }
        var invocationCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return invocations
        }
    }

    private func emission(_ n: Int) -> [SyncStatusInfo] {
        [SyncStatusInfo(from: ["_id": "peer-\(n)"])]
    }

    @Test(.tags(.repository, .regression))
    func `Sync-status callback survives the transport-apply observer cycle`() async throws {
        // ARRANGE — the production wiring at database open:
        // SyncStatusViewModel.installCallbacks() installs the dispatch callback.
        let repo = SystemRepository.shared
        let recorder = CallbackRecorder()
        await repo.setOnSyncStatusUpdate { _, completion in
            recorder.increment()
            completion()
        }
        defer {
            // Restore clean singleton state for other suites.
            Task {
                await repo.stopObserver()
            }
        }

        // Baseline: an emission reaches the installed callback.
        await repo.processSyncStatusUpdate(emission(1))
        #expect(recorder.invocationCount == 1)

        // ACT — the exact SystemRepository sequence the transport-apply path
        // performs (TransportConfigView.applyTransportConfig): reconfiguration
        // stop (callbacks preserved), then re-register the observers. The
        // registers throw without a live Ditto in a unit test; production
        // catches and logs those, so mirror with try?.
        await repo.pauseObservers()
        try? await repo.registerSyncStatusObserver()
        try? await repo.registerConnectionsPresenceObserver()

        // ASSERT — the Sync tab must still receive updates after the apply.
        // Before the fix, the apply used stopObserver() (full session teardown),
        // which cleared the dispatch callback; this emission was then queued as
        // pending forever and the count stayed at 1 — the frozen Sync tab.
        await repo.processSyncStatusUpdate(emission(2))
        #expect(recorder.invocationCount == 2)
    }

    @Test(.tags(.repository, .regression))
    func `stopObserver - the database-close path - intentionally drops the callback`() async throws {
        // Contract test: the close-path teardown clears the dispatch callbacks
        // on purpose (a closed session's ViewModel closures must not outlive
        // the session during rapid database switching), and the next session
        // re-registers them. This is why the transport-apply path must NOT use
        // stopObserver() mid-session — the two methods must stay distinct.
        let repo = SystemRepository.shared
        let recorder = CallbackRecorder()
        await repo.setOnSyncStatusUpdate { _, completion in
            recorder.increment()
            completion()
        }
        defer {
            Task {
                await repo.stopObserver()
            }
        }

        await repo.stopObserver()
        await repo.processSyncStatusUpdate(emission(1))

        // Not delivered — queued as pending until the next session installs a
        // callback (which is exactly what database reopen does).
        #expect(recorder.invocationCount == 0)
    }

    @Test(.tags(.repository, .regression))
    func `A queued pending update documents the dead-until-reopen symptom`() async throws {
        // Companion test: if an update is queued against a nil callback (the
        // symptom above), only re-installing the callback — i.e. what happens
        // when the database is CLOSED and REOPENED (performLoad →
        // installCallbacks) — drains it. This is why the bug self-heals only
        // on reopen, never mid-session.
        let repo = SystemRepository.shared
        let recorder = CallbackRecorder()
        await repo.setOnSyncStatusUpdate { _, completion in
            recorder.increment()
            completion()
        }
        defer {
            Task {
                await repo.stopObserver()
            }
        }

        // The close-path teardown (or any path that nils the callback) leaves
        // the emission queued — see the stopObserver contract test below.
        await repo.stopObserver()
        await repo.processSyncStatusUpdate(emission(1))
        #expect(recorder.invocationCount == 0)

        // Reopening the database re-installs the callback, which drains the
        // queued update.
        await repo.setOnSyncStatusUpdate { _, completion in
            recorder.increment()
            completion()
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(recorder.invocationCount == 1)
    }
}
