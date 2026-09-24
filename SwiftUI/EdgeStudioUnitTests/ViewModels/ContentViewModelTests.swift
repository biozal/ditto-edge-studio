import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for the destructive-delete confirmation gate on
/// `ContentView.ViewModel`. Deleting a database cascades through the
/// SQLCipher config row (subscriptions / history / favorites / observables)
/// AND removes the on-disk Ditto store, so every UI trigger must stage
/// `appPendingDeletion` and only the confirmation dialog may call through to
/// the repository.
@Suite("ContentView.ViewModel — delete confirmation gate", .serialized)
struct ContentViewModelTests {
    // MARK: - Helpers

    @MainActor
    private static func makeViewModel(
        mocks: MockSet
    ) -> ContentView.ViewModel {
        ContentView.ViewModel(
            dittoManager: mocks.dittoManager,
            databaseRepository: mocks.databaseRepository,
            subscriptionsRepository: mocks.subscriptionsRepository,
            systemRepository: mocks.systemRepository,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository,
            observableRepository: mocks.observableRepository,
            collectionsRepository: mocks.collectionsRepository
        )
    }

    // MARK: - Tests

    @Test(.tags(.fast))
    @MainActor
    func `deleteApp stages a confirmation instead of deleting`() async {
        // ARRANGE
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = Self.makeViewModel(mocks: mocks)
        let app = DittoConfigForDatabase.new()

        // ACT — the call every UI trigger makes (context menu, swipe action).
        await viewModel.deleteApp(app, appState: appState)

        // ASSERT — the app is staged for confirmation and the repository was
        // NOT touched: nothing may delete without an explicit confirm.
        #expect(viewModel.appPendingDeletion?._id == app._id)
        #expect(await mocks.databaseRepository.deletedConfigs.isEmpty)
    }

    @Test(.tags(.fast))
    @MainActor
    func `confirmAppDeletion deletes the confirmed app and clears staging`() async {
        // ARRANGE
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = Self.makeViewModel(mocks: mocks)
        let app = DittoConfigForDatabase.new()
        await viewModel.deleteApp(app, appState: appState)

        // ACT — the confirmation dialog's destructive button.
        await viewModel.confirmAppDeletion(app, appState: appState)

        // ASSERT
        #expect(await mocks.databaseRepository.deletedConfigs.map(\._id) == [app._id])
        #expect(viewModel.appPendingDeletion == nil)
        #expect(appState.error == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `confirmAppDeletion still deletes when the dialog already cleared staging`() async {
        // The regression this signature exists for. Dismissing a confirmationDialog
        // drives `isPresented` to false, whose setter clears `appPendingDeletion` — and
        // that runs BEFORE the button action's Task. The previous
        // `confirmPendingAppDeletion(appState:)` re-read the staged value, hit its
        // `guard let … else { return }`, and returned silently, so Delete did nothing at
        // all and left no log line to explain itself. Passing the config through
        // `presenting:` is what makes the action immune to that ordering.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = Self.makeViewModel(mocks: mocks)
        let app = DittoConfigForDatabase.new()
        await viewModel.deleteApp(app, appState: appState)

        // ACT — simulate the dismissal landing first.
        viewModel.appPendingDeletion = nil
        await viewModel.confirmAppDeletion(app, appState: appState)

        // ASSERT — the deletion still happens.
        #expect(await mocks.databaseRepository.deletedConfigs.map(\._id) == [app._id])
        #expect(appState.error == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `staging alone never deletes — only an explicit confirm does`() async {
        // Replaces the old "nothing staged is a no-op" case, which only proved the
        // guard fired. The property that matters is that staging is inert.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = Self.makeViewModel(mocks: mocks)
        let app = DittoConfigForDatabase.new()

        // ACT — trigger the menu item but never confirm.
        await viewModel.deleteApp(app, appState: appState)

        // ASSERT
        #expect(await mocks.databaseRepository.deletedConfigs.isEmpty)
        #expect(viewModel.appPendingDeletion?._id == app._id)
        #expect(appState.error == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `staging a second app replaces the first without deleting either`() async {
        // ARRANGE — two consecutive triggers (e.g. user opens the context menu
        // on one card, then on another) must not queue deletions.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = Self.makeViewModel(mocks: mocks)
        let first = DittoConfigForDatabase.new()
        let second = DittoConfigForDatabase.new()

        // ACT
        await viewModel.deleteApp(first, appState: appState)
        await viewModel.deleteApp(second, appState: appState)

        // ASSERT — only the latest is staged; nothing deleted yet.
        #expect(viewModel.appPendingDeletion?._id == second._id)
        #expect(await mocks.databaseRepository.deletedConfigs.isEmpty)
    }
}
