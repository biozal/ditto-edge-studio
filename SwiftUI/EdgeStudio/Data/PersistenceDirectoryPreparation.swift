import Foundation

/// Prepares the exact directory passed to Ditto.open without opening an SDK store.
/// Legacy inspection is limited to the selected small-peer database's two known
/// default paths. Tests supply temporary roots and never inspect user storage.
enum PersistenceDirectoryPreparation {
    enum PreparationError: LocalizedError {
        case invalidDatabaseID
        case unexpectedPath(URL)
        case ambiguousStores([URL])

        var errorDescription: String? {
            switch self {
            case .invalidDatabaseID:
                "The database ID cannot be used as a local store directory name."
            case let .unexpectedPath(url):
                "Cannot safely adopt the offline database at \(url.path). Expected a regular directory; no store was moved."
            case let .ambiguousStores(urls):
                "Multiple local stores exist for this offline database. Opening was stopped to preserve all copies. " +
                    "Back up and reconcile these directories before retrying: " + urls.map(\.path).joined(separator: ", ")
            }
        }
    }

    static func prepare(
        mode: AuthMode,
        databaseID: String,
        isUITesting: Bool,
        destination: URL,
        legacyRoot: URL
    ) throws {
        let files = FileManager.default
        if mode == .smallPeerOnly, !isUITesting {
            guard !databaseID.isEmpty, !databaseID.contains("/"),
                  databaseID != ".", databaseID != ".." else
            {
                throw PreparationError.invalidDatabaseID
            }

            // SDK 5.1 preserves ID case. Older documented defaults lowercased it.
            // On case-insensitive volumes these URLs can identify the same store.
            let candidates = [databaseID, databaseID.lowercased()].map {
                legacyRoot.appendingPathComponent("ditto-\($0)", isDirectory: true)
            }
            var identities: Set<String> = []
            var populated: [URL] = []
            for candidate in candidates {
                if let identity = try populatedDirectoryIdentity(candidate), identities.insert(identity).inserted {
                    populated.append(candidate)
                }
            }

            if !populated.isEmpty {
                if try populatedDirectoryIdentity(destination) != nil {
                    populated.append(destination)
                }
                guard populated.count == 1, let source = populated.first else {
                    throw PreparationError.ambiguousStores(populated)
                }
                try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Previous hydration created this empty directory even when the
                // SDK wrote elsewhere. Only an empty directory may be removed.
                if files.fileExists(atPath: destination.path) {
                    try files.removeItem(at: destination)
                }
                // Move the entire directory, preserving documents, attachments,
                // identity and license state. Never merge or overwrite stores.
                try files.moveItem(at: source, to: destination)
            }
        }
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    /// Any content counts as a store; guessing SDK filenames risks discarding data.
    /// Device/inode identity avoids treating case aliases as separate stores.
    private static func populatedDirectoryIdentity(_ url: URL) throws -> String? {
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return nil }
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else
        {
            throw PreparationError.unexpectedPath(url)
        }
        guard try !files.contentsOfDirectory(atPath: url.path).isEmpty else { return nil }
        return "\(device.stringValue):\(inode.stringValue)"
    }
}
