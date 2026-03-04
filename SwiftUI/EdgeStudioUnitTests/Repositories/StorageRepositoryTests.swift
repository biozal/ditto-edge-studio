import Testing
@testable import Ditto_Edge_Studio

@Suite("StorageRepository Tests", .serialized)
struct StorageRepositoryTests {

    @Suite("Error Paths")
    struct ErrorPathTests {
        @Test("fetchStorageSnapshot throws when no database selected", .tags(.repository, .storage))
        func testFetchThrowsWithNoApp() async {
            await #expect(throws: (any Error).self) {
                try await StorageRepository.fetchStorageSnapshot()
            }
        }
    }

    @Suite("File Categorization")
    struct CategorizationTests {

        @Test("ditto_store/ files go to storeBytes", .tags(.storage))
        func testStoreDirectory() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_store/db.sql", 5_000_000),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.storeBytes == 5_000_000)
            #expect(b.walShmBytes == 0)
        }

        @Test("ditto_replication/ files go to replicationBytes", .tags(.storage))
        func testReplicationDirectory() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_replication/peerA/peerB/db.sql", 1_000_000),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.replicationBytes == 1_000_000)
            #expect(b.storeBytes == 0)
        }

        @Test("ditto_attachments/ files go to attachmentsBytes", .tags(.storage))
        func testAttachmentsDirectory() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_attachments/db.sql", 2_000_000),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.attachmentsBytes == 2_000_000)
        }

        @Test("ditto_auth/ and ditto_auth_tmp/ go to authBytes", .tags(.storage))
        func testAuthDirectory() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_auth/site.cbor", 1_024),
                ("/data/ditto_auth_tmp/scratch", 512),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.authBytes == 1_536)
        }

        @Test("ditto_logs/ directory and .log.gz go to logsBytes", .tags(.storage))
        func testLogsDirectory() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_logs/ditto-2026.log", 400_000),
                ("/data/ditto_logs/ditto-2025.log.gz", 200_000),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.logsBytes == 600_000)
        }

        @Test(".log suffix files go to logsBytes", .tags(.storage))
        func testLogSuffix() {
            let files: [(path: String, sizeInBytes: Int)] = [("/var/app.log", 500)]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.logsBytes == 500)
        }

        @Test("-wal and -shm suffixes go to walShmBytes regardless of directory", .tags(.storage))
        func testWalShmPriority() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_store/db.sql-wal", 10_000_000),
                ("/data/ditto_replication/peer/db.sql-shm", 4_096),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.walShmBytes == 10_004_096)
            #expect(b.storeBytes == 0)       // not double-counted
            #expect(b.replicationBytes == 0)
        }

        @Test("unrecognised files go to otherBytes", .tags(.storage))
        func testOtherFiles() {
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_system_info/db.sql", 50_000),
                ("/data/__ditto_lock_file", 0),
                ("/data/ditto_metrics/some.dat", 1_000),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.otherBytes == 51_000)
            #expect(b.storeBytes == 0)
        }

        @Test("empty input returns all-zero DiskBreakdown", .tags(.storage))
        func testEmpty() {
            let b = StorageRepository.categorizeFiles([])
            #expect(b.storeBytes == 0)
            #expect(b.replicationBytes == 0)
            #expect(b.attachmentsBytes == 0)
            #expect(b.authBytes == 0)
            #expect(b.walShmBytes == 0)
            #expect(b.logsBytes == 0)
            #expect(b.otherBytes == 0)
        }

        @Test("WAL/SHM takes priority over log suffix", .tags(.storage))
        func testWalPriorityOverLog() {
            // A file ending in -wal goes to walShmBytes even inside ditto_logs/
            let files: [(path: String, sizeInBytes: Int)] = [
                ("/data/ditto_logs/app-wal", 100),
            ]
            let b = StorageRepository.categorizeFiles(files)
            #expect(b.walShmBytes == 100)
            #expect(b.logsBytes == 0)
        }
    }
}
