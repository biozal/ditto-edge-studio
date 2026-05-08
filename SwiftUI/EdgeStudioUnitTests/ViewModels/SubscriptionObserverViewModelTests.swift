import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests covering `SubscriptionObserverViewModel` — editor staging,
/// form save routing, and reset semantics. Phase 10b extraction.
@Suite("SubscriptionObserverViewModel — sub-VM", .serialized)
struct SubscriptionObserverViewModelTests {
    @Test(.tags(.fast))
    @MainActor
    func `ViewModel constructs with the expected default observe inspector tabs`() {
        let mocks = MockSet()

        let viewModel = SubscriptionObserverViewModel(
            dittoManager: mocks.dittoManager,
            subscriptionsRepository: mocks.subscriptionsRepository,
            observableRepository: mocks.observableRepository
        )

        #expect(viewModel.subscriptions.isEmpty)
        #expect(viewModel.observerables.isEmpty)
        #expect(viewModel.observeInspectorMenuItems.count == 2)
        #expect(viewModel.observeInspectorMenuItems.first?.name == "JSON")
        #expect(viewModel.selectedObserveInspectorMenuItem.name == "JSON")
    }

    @Test(.tags(.fast))
    @MainActor
    func `stageNewSubscription seeds an empty editorSubscription`() {
        let mocks = MockSet()
        let viewModel = SubscriptionObserverViewModel(
            dittoManager: mocks.dittoManager,
            subscriptionsRepository: mocks.subscriptionsRepository,
            observableRepository: mocks.observableRepository
        )

        // ACT
        viewModel.stageNewSubscription()

        // ASSERT — editorSubscription holds a fresh blank instance ready
        // for the editor sheet to populate.
        #expect(viewModel.editorSubscription != nil)
        #expect(viewModel.editorSubscription?.name == "")
        #expect(viewModel.editorSubscription?.query == "")
    }

    @Test(.tags(.fast))
    @MainActor
    func `formSaveSubscription forwards the saved subscription to the repository`() async {
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = SubscriptionObserverViewModel(
            dittoManager: mocks.dittoManager,
            subscriptionsRepository: mocks.subscriptionsRepository,
            observableRepository: mocks.observableRepository
        )
        viewModel.stageNewSubscription()

        // ACT — formSaveSubscription dispatches a Task with the save call.
        viewModel.formSaveSubscription(
            name: "Active orders",
            query: "SELECT * FROM orders WHERE active = true",
            appState: appState
        )

        // ASSERT — wait briefly for the unstructured Task. We poll up to
        // 1 second for the side-effect to land — fast in green path,
        // bounded if the wiring breaks.
        for _ in 0 ..< 100 {
            let saved = await mocks.subscriptionsRepository.savedSubscriptions
            if !saved.isEmpty {
                #expect(saved.first?.name == "Active orders")
                #expect(saved.first?.query == "SELECT * FROM orders WHERE active = true")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("formSaveSubscription did not reach the repository within 1s")
    }

    @Test(.tags(.fast))
    @MainActor
    func `reset clears all subscription/observer state`() {
        let mocks = MockSet()
        let viewModel = SubscriptionObserverViewModel(
            dittoManager: mocks.dittoManager,
            subscriptionsRepository: mocks.subscriptionsRepository,
            observableRepository: mocks.observableRepository
        )
        viewModel.stageNewSubscription()
        viewModel.stageNewObservable()
        viewModel.selectedEventId = "evt-1"

        // ACT
        viewModel.reset()

        // ASSERT
        #expect(viewModel.editorSubscription == nil)
        #expect(viewModel.editorObservable == nil)
        #expect(viewModel.selectedEventId == nil)
        #expect(viewModel.selectedObservable == nil)
        #expect(viewModel.subscriptions.isEmpty)
        #expect(viewModel.observerables.isEmpty)
    }
}
