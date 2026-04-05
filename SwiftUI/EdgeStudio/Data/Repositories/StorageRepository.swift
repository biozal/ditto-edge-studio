import DittoSwift
import Foundation

enum StorageRepository {
    /// Full storage snapshot. Throws InvalidStateError if no database is selected.
    static func fetchStorageSnapshot() async throws -> StorageSnapshot {
        guard let ditto = await DittoManager.shared.dittoSelectedApp else {
            throw InvalidStateError(message: "No selected app available")
        }
        return await computeDiskBreakdown(ditto: ditto)
    }

    // MARK: - Disk usage breakdown

    private static func computeDiskBreakdown(ditto: Ditto) async -> StorageSnapshot {
        let root = await Task.detached(priority: .utility) {
            ditto.diskUsage.item
        }.value

        let flatFiles = flattenTree(root)
        let b = categorizeFiles(flatFiles)
        let breakdown = await computeCollectionBreakdown(ditto: ditto)

        return StorageSnapshot(
            storeBytes: b.storeBytes,
            replicationBytes: b.replicationBytes,
            attachmentsBytes: b.attachmentsBytes,
            authBytes: b.authBytes,
            walShmBytes: b.walShmBytes,
            logsBytes: b.logsBytes,
            otherBytes: b.otherBytes,
            collectionBreakdown: breakdown
        )
    }

    /// Flattens a DittoDiskUsageItem tree into (path, sizeInBytes) tuples.
    private static func flattenTree(_ item: DittoDiskUsageItem) -> [(path: String, sizeInBytes: Int)] {
        var result: [(path: String, sizeInBytes: Int)] = [(item.path, item.sizeInBytes)]
        for child in item.childItems {
            result.append(contentsOf: flattenTree(child))
        }
        return result
    }

    /// Pure function: categorizes flat file list by Ditto directory conventions.
    /// WAL/SHM suffix takes priority and is checked first — these files appear inside
    /// any ditto_* directory and must not be double-counted into that directory's bucket.
    /// Exposed as `internal` so unit tests can call it directly without a Ditto instance.
    static func categorizeFiles(
        _ files: [(path: String, sizeInBytes: Int)]
    ) -> DiskBreakdown {
        var b = DiskBreakdown()
        for file in files {
            let p = file.path.lowercased()
            let bytes = file.sizeInBytes
            if p.hasSuffix("-wal") || p.hasSuffix("-shm") {
                b.walShmBytes += bytes
            } else if p.contains("/ditto_logs/") || p.hasSuffix(".log") || p.hasSuffix(".log.gz") {
                b.logsBytes += bytes
            } else if p.contains("/ditto_store/") {
                b.storeBytes += bytes
            } else if p.contains("/ditto_attachments/") {
                b.attachmentsBytes += bytes
            } else if p.contains("/ditto_auth") { // matches ditto_auth/ and ditto_auth_tmp/
                b.authBytes += bytes
            } else if p.contains("/ditto_replication/") {
                b.replicationBytes += bytes
            } else {
                b.otherBytes += bytes // ditto_metrics/, ditto_system_info/, lock files, etc.
            }
        }
        return b
    }

    // MARK: - Collection breakdown

    /// Queries every user collection and sums cborData() byte counts per collection.
    ///
    /// Uses cborData() — Ditto's native binary format — instead of JSON serialization for
    /// accurate per-collection payload estimates. Lower memory pressure than .value: the CBOR
    /// Data is immediately byte-counted and released without materializing a [String: Any?] dict.
    private static func computeCollectionBreakdown(ditto: Ditto) async -> [CollectionStats] {
        guard let cols = try? await ditto.store.execute(
            query: "SELECT * FROM system:collections"
        ) else { return [] }

        let names = cols.items.compactMap { $0.value["name"] as? String }
        cols.items.forEach { $0.dematerialize() }

        var breakdown: [CollectionStats] = []
        for name in names {
            let escaped = name.replacingOccurrences(of: "`", with: "``")
            guard let result = try? await ditto.store.execute(
                query: "SELECT * FROM `\(escaped)`"
            ) else { continue }

            var cborBytes = 0
            var docCount = 0
            for doc in result.items {
                cborBytes += doc.cborData().count
                docCount += 1
                doc.dematerialize()
            }
            breakdown.append(CollectionStats(
                name: name,
                documentCount: docCount,
                cborPayloadBytes: cborBytes
            ))
        }

        return breakdown.sorted { $0.cborPayloadBytes > $1.cborPayloadBytes }
    }
}
