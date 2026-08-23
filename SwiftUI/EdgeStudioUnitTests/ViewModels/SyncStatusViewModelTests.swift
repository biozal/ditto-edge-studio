import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests that prove `SyncStatusViewModel` is constructible with mock
/// dependencies and that its sync-toggle path round-trips through the
/// injected `DittoManager`. Phase 10b extraction — see
/// `plans/2026-05-07-pre-v1-shipping-fixes.md`.
@Suite("SyncStatusViewModel — sub-VM", .serialized)
struct SyncStatusViewModelTests {
    @Test(.tags(.fast))
    @MainActor
    func `ViewModel constructs with default empty state`() {
        // ARRANGE / ACT
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )

        // ASSERT — sync starts NOT running. The old default was an optimistic `true`
        // ("hydration starts sync"), which was a guess: it was already wrong whenever an
        // open failed or a restart threw. It is now derived from SyncRuntimeState.
        #expect(viewModel.syncStatusItems.isEmpty)
        #expect(viewModel.isSyncEnabled == false)
        #expect(viewModel.localPeerDeviceName == nil)
        #expect(viewModel.localPeerSDKLanguage == nil)
        #expect(viewModel.localPeerSDKPlatform == nil)
        #expect(viewModel.localPeerSDKVersion == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `toggleSync routes through the injected DittoManager`() async throws {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )

        // Initial state is "not running", so the first toggle STARTS sync.
        // ACT
        try await viewModel.toggleSync()

        // ASSERT — the derived flag followed the manager's published state.
        #expect(viewModel.isSyncEnabled == true)
        #expect(await mocks.dittoManager.startSyncCallCount == 1)
        #expect(await mocks.dittoManager.stopSyncCallCount == 0)

        // ACT — toggle back off
        try await viewModel.toggleSync()

        // ASSERT — state flipped, and the live transport / peer caches were cleared.
        #expect(viewModel.isSyncEnabled == false)
        #expect(await mocks.dittoManager.stopSyncCallCount == 1)
        #expect(viewModel.syncStatusItems.isEmpty)
    }

    /// The core guarantee of deriving the flag: a start that FAILS must not light the
    /// indicator. Before this, `toggleSync` assigned `isSyncEnabled = true` on the
    /// non-throwing path, and `selectedDatabaseStartSync` could return silently without
    /// starting anything — so the toolbar went green over stopped sync and the user's next
    /// tap took the stop branch.
    @Test(.tags(.fast))
    @MainActor
    func `a failed start leaves sync reported as stopped`() async {
        // ARRANGE
        let mocks = MockSet()
        await mocks.dittoManager.setStartError(AppError.error(message: "scope apply failed"))
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )

        // ACT — the throw propagates to the caller, which surfaces it.
        await #expect(throws: AppError.self) {
            try await viewModel.toggleSync()
        }

        // ASSERT — the attempt was made, but the indicator did NOT flip.
        #expect(await mocks.dittoManager.startSyncCallCount == 1)
        #expect(viewModel.isSyncEnabled == false, "a failed start must not report sync as running")
    }

    /// `SyncRuntimeState` is the single writer; a view must not be able to fake it.
    @Test(.tags(.fast))
    @MainActor
    func `the derived flag tracks the runtime state directly`() {
        // ARRANGE
        let runtime = SyncRuntimeState()
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: runtime
        )
        #expect(viewModel.isSyncEnabled == false)

        // ACT / ASSERT — only the runtime state moves the needle.
        runtime.setRunning(true)
        #expect(viewModel.isSyncEnabled)
        runtime.setRunning(false)
        #expect(viewModel.isSyncEnabled == false)
    }

    @Test(.tags(.fast))
    @MainActor
    func `reset clears all sync-related state`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository,
            syncRuntime: mocks.syncRuntime
        )
        viewModel.localPeerDeviceName = "TestDevice"
        viewModel.localPeerSDKLanguage = "swift"

        // ACT
        viewModel.reset()

        // ASSERT — `reset()` clears the caches. It no longer writes sync state: closing
        // the database is what stops sync, and the stop funnel publishes that.
        #expect(viewModel.syncStatusItems.isEmpty)
        #expect(viewModel.localPeerDeviceName == nil)
        #expect(viewModel.localPeerSDKLanguage == nil)
    }
}
