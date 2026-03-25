import Foundation

/// Per-collection CBOR payload estimate.
struct CollectionStats: Identifiable {
    var id: String {
        name
    }

    let name: String
    let documentCount: Int
    let cborPayloadBytes: Int
}

/// Categorized disk usage breakdown from the diskUsage tree.
/// Return type of `StorageRepository.categorizeFiles(_:)`.
struct DiskBreakdown {
    var storeBytes = 0
    var replicationBytes = 0
    var attachmentsBytes = 0
    var authBytes = 0
    var walShmBytes = 0
    var logsBytes = 0
    var otherBytes = 0
}

struct StorageSnapshot {
    /// From diskUsage tree — ditto_store/ directory
    var storeBytes = 0

    /// From diskUsage tree — ditto_replication/ directory
    var replicationBytes = 0

    /// From diskUsage tree — ditto_attachments/ directory
    var attachmentsBytes = 0

    /// From diskUsage tree — ditto_auth/ + ditto_auth_tmp/ directories
    var authBytes = 0

    /// From diskUsage tree — -wal / -shm file suffixes (across all directories)
    var walShmBytes = 0

    /// From diskUsage tree — ditto_logs/ directory + .log / .log.gz files
    var logsBytes = 0

    // Residual: ditto_metrics/, ditto_system_info/, lock files, etc.
    var otherBytes = 0

    /// Per-collection CBOR payload breakdown (sorted largest-first)
    var collectionBreakdown: [CollectionStats] = []

    /// Sum of all collection CBOR payload bytes.
    var collectionPayloadBytes: Int {
        collectionBreakdown.reduce(0) { $0 + $1.cborPayloadBytes }
    }

    static func formatMB(_ bytes: Int) -> String {
        String(format: "%.2f MB", Double(bytes) / 1_048_576.0)
    }
}
