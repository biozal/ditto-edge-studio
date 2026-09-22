import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("System metrics database-session lifetime", .serialized)
@MainActor
struct SystemMetricsSessionTests {
    @Test(.tags(.fast))
    func `Start respects the disabled collection preference without reading`() async {
        let restore = overrideCollectionPreference(false)
        defer { restore() }
        var reads = 0
        let service = SystemMetricsService {
            reads += 1
            return Self.rows(delta: 1)
        }
        defer { service.endSession() }

        service.start()
        await Task.yield()

        #expect(service.snapshot.status == .settingDisabled)
        #expect(reads == 0)
    }

    @Test(.tags(.fast))
    func `Start is idempotent, stop permits resume, and Close is terminal`() async throws {
        let restore = overrideCollectionPreference(true)
        defer { restore() }
        var reads = 0
        let service = SystemMetricsService {
            reads += 1
            return Self.rows(delta: 2)
        }
        defer { service.endSession() }

        service.start()
        service.start()
        try await waitUntil { reads >= 1 }
        // Let every queued start task run before checking that only one read occurred.
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(reads == 1)
        let since = service.snapshot.since

        service.stop()
        service.start()
        try await waitUntil { reads >= 2 }
        #expect(service.snapshot.samples.first?.sinceConnect == 4)
        #expect(service.snapshot.since == since)

        service.endSession()
        service.start()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(reads == 2)
        #expect(service.snapshot == SystemMetricsService.Snapshot())
    }

    @Test(.tags(.fast), arguments: Interruption.allCases)
    func `Transient poll failures preserve the session zero point when polling recovers`(interruption: Interruption) async {
        var read = 0
        let service = SystemMetricsService {
            read += 1
            if read == 2 {
                switch interruption {
                case .disconnected: return nil
                case .exporterDisabled: return [["status": "disabled"]]
                case .failure: throw ReadFailure()
                }
            }
            return [
                ["key": "ditto.z.counter", "delta": read == 1 ? 5.0 : 3.0],
                ["key": "ditto.a.counter", "delta": 1.0]
            ]
        }
        defer { service.endSession() }
        await service.refreshNow()
        let since = service.snapshot.since
        #expect(since != nil)
        await service.refreshNow()
        switch interruption {
        case .disconnected: #expect(service.snapshot.status == .noConnection)
        case .exporterDisabled: #expect(service.snapshot.status == .exporterDisabled)
        case .failure:
            #expect(service.snapshot.status == .error("Test read failed"))
            #expect(service.snapshot.errorMessage == "Test read failed")
        }
        await service.refreshNow()

        #expect(service.snapshot.status == .ready)
        #expect(service.snapshot.samples.map(\.key) == ["ditto.a.counter", "ditto.z.counter"])
        #expect(service.snapshot.samples.last?.sinceConnect == 8)
        #expect(service.snapshot.since == since)
        #expect(service.snapshot.errorMessage == nil)
    }

    @Test(.tags(.fast))
    func `A read failing after Close cannot replace its cleared snapshot`() async {
        let reader = SuspendedReader()
        let service = SystemMetricsService {
            _ = await reader.read()
            throw ReadFailure()
        }
        let owner = makeOwner(service: service)
        let poll = Task { await service.refreshNow() }
        await reader.waitUntilReading()

        await owner.closeSelectedApp()
        reader.complete()
        await poll.value

        #expect(service.snapshot == SystemMetricsService.Snapshot())
    }

    @Test(.tags(.fast))
    func `Recreating the metrics detail retains the database session's totals`() async {
        var delta = 5.0
        let service = SystemMetricsService { Self.rows(delta: delta) }
        let owner = makeOwner(service: service)
        let firstVisit = SystemMetricsDetailView(databaseId: owner.selectedApp._id, service: owner.systemMetricsService)
        await firstVisit.service.refreshNow()
        let since = service.snapshot.since

        // The detail's onDisappear stops polling; its replacement receives the
        // same session-owned service from MainStudioView's destination switch.
        firstVisit.service.stop()
        delta = 3
        let returnVisit = SystemMetricsDetailView(databaseId: owner.selectedApp._id, service: owner.systemMetricsService)
        await returnVisit.service.refreshNow()

        #expect(returnVisit.service === firstVisit.service)
        #expect(returnVisit.service.snapshot.samples.first?.sinceConnect == 8)
        #expect(returnVisit.service.snapshot.samples.first?.periodDelta == 3)
        #expect(returnVisit.service.snapshot.since == since)
    }

    @Test(.tags(.fast))
    func `Closing a database clears its metrics and cannot poll the next database`() async {
        var reads = 0
        let service = SystemMetricsService {
            reads += 1
            return Self.rows(delta: 7)
        }
        let owner = makeOwner(service: service)
        await owner.systemMetricsService.refreshNow()
        #expect(service.snapshot.samples.first?.sinceConnect == 7)

        // Exercise the production Close button's orchestration, not just the
        // service's teardown method in isolation.
        await owner.closeSelectedApp()
        await service.refreshNow()

        #expect(service.snapshot == SystemMetricsService.Snapshot())
        #expect(reads == 1)
        let nextOwner = makeOwner()
        #expect(nextOwner.selectedApp._id != owner.selectedApp._id)
        #expect(nextOwner.systemMetricsService !== service)
        #expect(nextOwner.systemMetricsService.snapshot == SystemMetricsService.Snapshot())
    }

    @Test(.tags(.fast))
    func `A poll completing after Close cannot restore the old database's totals`() async {
        let reader = SuspendedReader()
        let service = SystemMetricsService { await reader.read() }
        let owner = makeOwner(service: service)
        let poll = Task { await service.refreshNow() }
        await reader.waitUntilReading()

        await owner.closeSelectedApp()
        reader.complete()
        await poll.value

        #expect(service.snapshot == SystemMetricsService.Snapshot())
    }

    @Test(.tags(.fast))
    func `Reopening the same configuration gets a fresh session accumulator`() async {
        let config = DittoConfigForDatabase.new()
        let oldService = SystemMetricsService { Self.rows(delta: 11) }
        let firstOwner = makeOwner(config: config, service: oldService)
        await oldService.refreshNow()
        await firstOwner.closeSelectedApp()

        let nextService = SystemMetricsService { Self.rows(delta: 2) }
        let nextOwner = makeOwner(config: config, service: nextService)
        await nextOwner.systemMetricsService.refreshNow()

        #expect(nextOwner.selectedApp._id == firstOwner.selectedApp._id)
        #expect(nextOwner.systemMetricsService !== oldService)
        #expect(nextOwner.systemMetricsService.snapshot.samples.first?.sinceConnect == 2)
    }

    private func makeOwner(
        config: DittoConfigForDatabase = .new(),
        service: SystemMetricsService? = nil
    ) -> MainStudioView.ViewModel {
        let mocks = MockSet()
        return MainStudioView.ViewModel(
            config,
            dittoManager: mocks.dittoManager,
            queryService: mocks.queryService,
            subscriptionsRepository: mocks.subscriptionsRepository,
            systemRepository: mocks.systemRepository,
            historyRepository: mocks.historyRepository,
            favoritesRepository: mocks.favoritesRepository,
            observableRepository: mocks.observableRepository,
            collectionsRepository: mocks.collectionsRepository,
            systemMetricsService: service
        )
    }

    private static func rows(delta: Double) -> [[String: Any]] {
        [["key": "ditto.test.counter", "delta": delta]]
    }

    enum Interruption: CaseIterable {
        case disconnected, exporterDisabled, failure
    }

    private struct ReadFailure: LocalizedError {
        var errorDescription: String? {
            "Test read failed"
        }
    }

    /// No persistent preference writes, including when the unit host uses standard defaults.
    private func overrideCollectionPreference(_ enabled: Bool) -> () -> Void {
        let defaults = StudioPreferences.store
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var override = original
        override["collectSystemMetrics"] = enabled
        defaults.setVolatileDomain(override, forName: UserDefaults.argumentDomain)
        return { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "The polling task did not reach its expected read")
    }

    @MainActor
    private final class SuspendedReader {
        private var pending: CheckedContinuation<Void, Never>?
        private var started: CheckedContinuation<Void, Never>?

        func read() async -> [[String: Any]]? {
            await withCheckedContinuation { continuation in
                pending = continuation
                started?.resume()
                started = nil
            }
            return SystemMetricsSessionTests.rows(delta: 99)
        }

        func waitUntilReading() async {
            guard pending == nil else { return }
            await withCheckedContinuation { started = $0 }
        }

        func complete() {
            pending?.resume()
            pending = nil
        }
    }
}
