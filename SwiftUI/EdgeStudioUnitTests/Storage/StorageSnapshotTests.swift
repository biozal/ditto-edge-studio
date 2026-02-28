import Testing
@testable import Ditto_Edge_Studio

@Suite("StorageSnapshot Tests")
struct StorageSnapshotTests {

    @Test("formatMB converts bytes to MB with 2 decimal places", .tags(.storage))
    func testFormatMBPrecision() {
        #expect(StorageSnapshot.formatMB(1_048_576) == "1.00 MB")
        #expect(StorageSnapshot.formatMB(524_288) == "0.50 MB")
        #expect(StorageSnapshot.formatMB(0) == "0.00 MB")
    }

    @Test("formatMB handles large values", .tags(.storage))
    func testFormatMBLarge() {
        #expect(StorageSnapshot.formatMB(10_485_760) == "10.00 MB")
    }

    @Test("StorageSnapshot defaults to all zeros and empty breakdown", .tags(.storage))
    func testDefaultValues() {
        let snap = StorageSnapshot()
        #expect(snap.storeBytes == 0)
        #expect(snap.replicationBytes == 0)
        #expect(snap.attachmentsBytes == 0)
        #expect(snap.authBytes == 0)
        #expect(snap.walShmBytes == 0)
        #expect(snap.logsBytes == 0)
        #expect(snap.otherBytes == 0)
        #expect(snap.collectionBreakdown.isEmpty)
        #expect(snap.collectionPayloadBytes == 0)
    }

    @Test("collectionPayloadBytes sums cborPayloadBytes from breakdown", .tags(.storage))
    func testCollectionPayloadBytesComputed() {
        var snap = StorageSnapshot()
        snap.collectionBreakdown = [
            CollectionStats(name: "cars", documentCount: 10, cborPayloadBytes: 1_000),
            CollectionStats(name: "trucks", documentCount: 5, cborPayloadBytes: 500),
        ]
        #expect(snap.collectionPayloadBytes == 1_500)
    }

    @Test("CollectionStats exposes id as name", .tags(.storage))
    func testCollectionStatsId() {
        let stats = CollectionStats(name: "cars", documentCount: 3, cborPayloadBytes: 512)
        #expect(stats.id == "cars")
        #expect(stats.documentCount == 3)
        #expect(stats.cborPayloadBytes == 512)
    }

    @Test("DiskBreakdown defaults to all zeros", .tags(.storage))
    func testDiskBreakdownDefaults() {
        let b = DiskBreakdown()
        #expect(b.storeBytes == 0)
        #expect(b.replicationBytes == 0)
        #expect(b.attachmentsBytes == 0)
        #expect(b.authBytes == 0)
        #expect(b.walShmBytes == 0)
        #expect(b.logsBytes == 0)
        #expect(b.otherBytes == 0)
    }
}
