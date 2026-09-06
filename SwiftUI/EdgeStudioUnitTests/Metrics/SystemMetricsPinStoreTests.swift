import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("SystemMetrics pin store tests")
struct SystemMetricsPinStoreTests {
    /// A throwaway `UserDefaults` suite per test so pins never leak into the
    /// developer's real defaults or across tests.
    ///
    /// `#require` rather than `!`: a suite that failed to open would otherwise
    /// crash the whole run instead of failing the one test that needed it.
    private func makeDefaults() throws -> UserDefaults {
        let name = "SystemMetricsPinStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func ref(_ key: String, _ labels: [String: String] = [:]) -> SystemMetricSeriesRef {
        SystemMetricSeriesRef(key: key, labels: labels)
    }

    @Test("series identity ignores label ordering")
    func identityIgnoresLabelOrder() {
        // Arrange
        let a = ref("ditto.backend.wal", ["db": "main", "op": "fsync"])
        let b = ref("ditto.backend.wal", ["op": "fsync", "db": "main"])

        // Act / Assert
        #expect(a.id == b.id)
        #expect(a.labelLine == "db=main,op=fsync")
    }

    @Test("different label maps are different series")
    func differentLabelsAreDifferentSeries() {
        // Arrange / Act
        let main = ref("ditto.backend.wal", ["db": "main"])
        let attachment = ref("ditto.backend.wal", ["db": "attachment"])

        // Assert
        #expect(main.id != attachment.id)
    }

    @Test("pins round-trip in pin order")
    func pinsRoundTrip() throws {
        // Arrange
        let defaults = try makeDefaults()
        let pins = [ref("b.metric"), ref("a.metric", ["t": "ble"])]

        // Act
        SystemMetricsPinStore.write(pins, databaseId: "db-1", defaults: defaults)
        let read = SystemMetricsPinStore.read(databaseId: "db-1", defaults: defaults)

        // Assert — pin order is preserved, not sorted.
        #expect(read == pins)
    }

    @Test("pins are scoped per database")
    func pinsAreScopedPerDatabase() throws {
        // Arrange
        let defaults = try makeDefaults()

        // Act
        SystemMetricsPinStore.write([ref("a.metric")], databaseId: "db-1", defaults: defaults)

        // Assert
        #expect(SystemMetricsPinStore.read(databaseId: "db-2", defaults: defaults).isEmpty)
    }

    @Test("duplicate series are collapsed, first occurrence wins")
    func duplicatesAreCollapsed() throws {
        // Arrange
        let defaults = try makeDefaults()
        let duplicated = [ref("a.metric"), ref("b.metric"), ref("a.metric")]

        // Act
        SystemMetricsPinStore.write(duplicated, databaseId: "db-1", defaults: defaults)
        let read = SystemMetricsPinStore.read(databaseId: "db-1", defaults: defaults)

        // Assert
        #expect(read == [ref("a.metric"), ref("b.metric")])
    }

    @Test("writing an empty list removes the stored key")
    func clearingRemovesTheKey() throws {
        // Arrange
        let defaults = try makeDefaults()
        SystemMetricsPinStore.write([ref("a.metric")], databaseId: "db-1", defaults: defaults)

        // Act
        SystemMetricsPinStore.write([], databaseId: "db-1", defaults: defaults)

        // Assert
        #expect(SystemMetricsPinStore.read(databaseId: "db-1", defaults: defaults).isEmpty)
        #expect(defaults.data(forKey: "dittoSystemMetricsPins.v1.db-1") == nil)
    }

    @Test("undecodable stored data reads as no pins")
    func corruptDataReadsAsEmpty() throws {
        // Arrange
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "dittoSystemMetricsPins.v1.db-1")

        // Act
        let read = SystemMetricsPinStore.read(databaseId: "db-1", defaults: defaults)

        // Assert
        #expect(read.isEmpty)
    }

    @Test("a sample's seriesID matches the ref pinned from it")
    func sampleIdentityMatchesRef() {
        // Arrange
        let sample = SystemMetricSample(
            key: "ditto.network.dsoq.connection.opened",
            labels: ["transport": "ble"],
            description: "",
            unit: "",
            kind: .counter,
            sinceConnect: 3,
            periodDelta: 1,
            sumSinceConnect: nil,
            absMax: nil
        )

        // Act
        let pinned = SystemMetricSeriesRef(sample: sample)

        // Assert
        #expect(sample.seriesID == pinned.id)
    }
}

@Suite("SystemMetrics namespace filter tests")
struct SystemMetricsNamespaceFilterTests {
    private func sample(_ key: String) -> SystemMetricSample {
        SystemMetricSample(
            key: key,
            labels: [:],
            description: "",
            unit: "",
            kind: .counter,
            sinceConnect: 0,
            periodDelta: 0,
            sumSinceConnect: nil,
            absMax: nil
        )
    }

    @Test("all matches every namespace")
    func allMatchesEverything() {
        #expect(SystemMetricsNamespaceFilter.all.matches(sample("ditto.network.dsoq.connection.opened")))
        #expect(SystemMetricsNamespaceFilter.all.matches(sample("something.else")))
    }

    @Test(
        "namespaces match their prefixes",
        arguments: [
            (SystemMetricsNamespaceFilter.network, "ditto.network.dsoq.connection.opened"),
            (SystemMetricsNamespaceFilter.store, "ditto.backend.sqlite3.txn_attempts"),
            (SystemMetricsNamespaceFilter.sync, "ditto.sync.sessions_started"),
            (SystemMetricsNamespaceFilter.sync, "ditto.replication.sessions_started")
        ]
    )
    func namespacesMatchTheirPrefixes(filter: SystemMetricsNamespaceFilter, key: String) {
        #expect(filter.matches(sample(key)))
    }

    @Test("other matches only what no namespace claims")
    func otherIsTheComplement() {
        #expect(SystemMetricsNamespaceFilter.other.matches(sample("ditto.peer.revocation_diffs_sent")))
        #expect(!SystemMetricsNamespaceFilter.other.matches(sample("ditto.network.dsoq.connection.opened")))
        #expect(!SystemMetricsNamespaceFilter.other.matches(sample("ditto.backend.sqlite3.txn_attempts")))
    }
}

@Suite("SystemMetrics pin ordering tests")
struct SystemMetricsPinOrderingTests {
    private func ref(_ key: String) -> SystemMetricSeriesRef {
        SystemMetricSeriesRef(key: key, labels: [:])
    }

    private var pins: [SystemMetricSeriesRef] {
        [ref("a"), ref("b"), ref("c"), ref("d")]
    }

    private func keys(_ pins: [SystemMetricSeriesRef]) -> [String] {
        pins.map(\.key)
    }

    @Test("dragging down past a row's midpoint lands after it")
    func dragDownInsertsAfter() {
        // Arrange / Act — drag "a" onto the lower half of "c".
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("a").id, targetID: ref("c").id, insertBefore: false
        )

        // Assert — "a" lands where the pointer was, not one slot short of it.
        #expect(keys(moved) == ["b", "c", "a", "d"])
    }

    @Test("dragging down onto a row's upper half lands before it")
    func dragDownInsertsBefore() {
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("a").id, targetID: ref("c").id, insertBefore: true
        )

        #expect(keys(moved) == ["b", "a", "c", "d"])
    }

    @Test("dragging up onto a row's upper half lands before it")
    func dragUpInsertsBefore() {
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("d").id, targetID: ref("b").id, insertBefore: true
        )

        #expect(keys(moved) == ["a", "d", "b", "c"])
    }

    @Test("dropping a row on itself changes nothing")
    func selfDropIsANoOp() {
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("b").id, targetID: ref("b").id, insertBefore: true
        )

        #expect(keys(moved) == keys(pins))
    }

    @Test("a target unpinned mid-drag leaves the order untouched")
    func staleTargetIsANoOp() {
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("a").id, targetID: ref("gone").id, insertBefore: true
        )

        #expect(keys(moved) == keys(pins))
    }

    @Test("an unknown dragged series leaves the order untouched")
    func unknownDraggedIsANoOp() {
        // Guards the cross-app drop path: a text drag the coordinator never saw.
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("gone").id, targetID: ref("b").id, insertBefore: true
        )

        #expect(keys(moved) == keys(pins))
    }

    @Test("reordering preserves the set — no duplicates, nothing dropped")
    func reorderPreservesTheSet() {
        let moved = SystemMetricsPinOrdering.moved(
            pins, draggedID: ref("a").id, targetID: ref("d").id, insertBefore: false
        )

        #expect(Set(keys(moved)) == Set(keys(pins)))
        #expect(moved.count == pins.count)
    }

    @Test("Move Up swaps with the previous row")
    func moveUp() {
        #expect(keys(SystemMetricsPinOrdering.moved(pins, from: 2, to: 1)) == ["a", "c", "b", "d"])
    }

    @Test("Move Down swaps with the next row")
    func moveDown() {
        #expect(keys(SystemMetricsPinOrdering.moved(pins, from: 1, to: 2)) == ["a", "c", "b", "d"])
    }

    @Test(
        "out-of-range and no-op index moves change nothing",
        arguments: [(0, -1), (3, 4), (1, 1), (-1, 0), (9, 0)]
    )
    func outOfRangeMovesAreNoOps(source: Int, destination: Int) {
        #expect(keys(SystemMetricsPinOrdering.moved(pins, from: source, to: destination)) == keys(pins))
    }
}
