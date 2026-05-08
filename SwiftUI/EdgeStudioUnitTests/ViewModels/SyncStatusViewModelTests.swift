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
            systemRepository: mocks.systemRepository
        )

        // ASSERT — defaults match the prior god-VM init contract.
        #expect(viewModel.syncStatusItems.isEmpty)
        #expect(viewModel.isSyncEnabled == true)
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
            systemRepository: mocks.systemRepository
        )

        // Initial: isSyncEnabled = true → toggling once should call stopSync
        // ACT
        try await viewModel.toggleSync()

        // ASSERT — state flipped, mock recorded the call, and the live
        // transport / peer caches were cleared as documented.
        #expect(viewModel.isSyncEnabled == false)
        #expect(await mocks.dittoManager.stopSyncCallCount == 1)
        #expect(await mocks.dittoManager.startSyncCallCount == 0)
        #expect(viewModel.syncStatusItems.isEmpty)

        // ACT — toggle back on
        try await viewModel.toggleSync()

        // ASSERT
        #expect(viewModel.isSyncEnabled == true)
        #expect(await mocks.dittoManager.startSyncCallCount == 1)
    }

    @Test(.tags(.fast))
    @MainActor
    func `reset clears all sync-related state`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = SyncStatusViewModel(
            dittoManager: mocks.dittoManager,
            systemRepository: mocks.systemRepository
        )
        viewModel.localPeerDeviceName = "TestDevice"
        viewModel.localPeerSDKLanguage = "swift"

        // ACT
        viewModel.reset()

        // ASSERT
        #expect(viewModel.isSyncEnabled == false)
        #expect(viewModel.syncStatusItems.isEmpty)
        #expect(viewModel.localPeerDeviceName == nil)
        #expect(viewModel.localPeerSDKLanguage == nil)
    }
}
