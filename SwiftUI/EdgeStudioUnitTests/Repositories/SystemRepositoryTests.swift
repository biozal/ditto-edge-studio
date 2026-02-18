import Testing
@testable import Edge_Debug_Helper

/// Test suite for SystemRepository
///
/// SystemRepository registers Ditto presence observers. Without a live Ditto
/// instance (dittoSelectedApp is nil in unit tests), full observer tests
/// belong in EdgeStudioIntegrationTests.
///
/// These unit tests cover:
/// - Error paths: registerSyncStatusObserver() and registerConnectionsPresenceObserver()
///   with no selected database throw or return safely (no crash)
/// - stopObserver() with no active observers is safe and idempotent
/// - Callback registration: setOnSyncStatusUpdate, setOnConnectionsUpdate,
///   and setAppState can be registered without crashing
///
/// TODO: Integration tests needed
/// Full integration tests with a live Ditto instance belong in
/// EdgeStudioIntegrationTests.
///
/// Target: ~20% code coverage (error paths and registration only).
@Suite("SystemRepository Tests", .serialized)
struct SystemRepositoryTests {

    // MARK: - Error Path Tests

    @Suite("Error Paths")
    struct ErrorPathTests {

        @Test("registerSyncStatusObserver with no selected app throws", .tags(.repository))
        func testRegisterSyncStatusObserverThrowsWithNoApp() async throws {
            // ARRANGE — No selected app (unit test: DittoManager.dittoSelectedApp is nil)
            let repo = SystemRepository.shared

            // ACT & ASSERT — should throw because dittoSelectedApp is nil
            await #expect(throws: (any Error).self) {
                try await repo.registerSyncStatusObserver()
            }
        }

        @Test("registerConnectionsPresenceObserver with no selected app throws", .tags(.repository))
        func testRegisterConnectionsPresenceObserverThrowsWithNoApp() async throws {
            // ARRANGE — No selected app
            let repo = SystemRepository.shared

            // ACT & ASSERT — should throw because dittoSelectedApp is nil
            await #expect(throws: (any Error).self) {
                try await repo.registerConnectionsPresenceObserver()
            }
        }
    }

    // MARK: - Stop Observer Tests

    @Suite("Stop Observer")
    struct StopObserverTests {

        @Test("stopObserver with no active observers does not crash", .tags(.repository))
        func testStopObserverWithNoActiveObservers() async {
            // ARRANGE — No observers registered
            let repo = SystemRepository.shared

            // ACT & ASSERT — should not crash
            await repo.stopObserver()
        }

        @Test("stopObserver can be called multiple times safely", .tags(.repository))
        func testStopObserverIsIdempotent() async {
            // ARRANGE
            let repo = SystemRepository.shared

            // ACT — multiple calls
            await repo.stopObserver()
            await repo.stopObserver()
            await repo.stopObserver()

            // ASSERT — reached here without crashing
            #expect(Bool(true))
        }
    }

    // MARK: - Callback Registration Tests

    @Suite("Callback Registration")
    struct CallbackRegistrationTests {

        @Test("setOnSyncStatusUpdate can be registered without crashing", .tags(.repository))
        func testSetOnSyncStatusUpdateRegistration() async {
            // ARRANGE
            let repo = SystemRepository.shared

            // ACT
            await repo.setOnSyncStatusUpdate { _, _ in
                // callback — not invoked in unit test
            }

            // ASSERT — reached here without crashing
            #expect(Bool(true))
        }

        @Test("setOnConnectionsUpdate can be registered without crashing", .tags(.repository))
        func testSetOnConnectionsUpdateRegistration() async {
            // ARRANGE
            let repo = SystemRepository.shared

            // ACT
            await repo.setOnConnectionsUpdate { _ in
                // callback — not invoked in unit test
            }

            // ASSERT — reached here without crashing
            #expect(Bool(true))
        }

        @Test("Both callbacks can be registered without crashing", .tags(.repository))
        func testBothCallbacksRegistration() async {
            // ARRANGE
            let repo = SystemRepository.shared

            // ACT
            await repo.setOnSyncStatusUpdate { _, _ in }
            await repo.setOnConnectionsUpdate { _ in }

            // ASSERT — reached here without crashing
            #expect(Bool(true))
        }
    }
}

// MARK: - Integration Test Stub

// TODO: Integration tests needed
// The following tests require a live Ditto instance and belong in EdgeStudioIntegrationTests.
// Add them when a Ditto test instance is available:
//
// @Suite("SystemRepository Integration Tests")
// struct SystemRepositoryIntegrationTests {
//
//     @Test("registerSyncStatusObserver fires callback when sync status changes")
//     func testSyncStatusObserverFiresCallback() async throws { ... }
//
//     @Test("registerConnectionsPresenceObserver fires callback when peers connect/disconnect")
//     func testConnectionsPresenceObserverFiresCallback() async throws { ... }
//
//     @Test("stopObserver cancels active sync and presence observers")
//     func testStopObserverCancelsActiveObservers() async throws { ... }
// }
