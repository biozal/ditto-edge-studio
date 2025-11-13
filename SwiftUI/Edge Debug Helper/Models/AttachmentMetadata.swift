//
//  AttachmentMetadata.swift
//  Edge Studio
//

import Foundation

struct AttachmentMetadata: Codable, Equatable {
    let id: String
    let len: Int
    let type: String?

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(len), countStyle: .file)
    }
}

struct AttachmentFieldInfo {
    let fieldName: String
    let metadata: AttachmentMetadata?

    var hasMetadata: Bool {
        metadata != nil
    }
}

// Helper to detect attachment fields from query
struct AttachmentQueryParser {
    // Regex pattern to detect ATTACHMENT cast in query
    // Matches: fieldName ATTACHMENT or (fieldName ATTACHMENT)
    private static let attachmentPattern = #"(\w+)\s+ATTACHMENT"#

    static func extractAttachmentFields(from query: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: attachmentPattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsString = query as NSString
        let matches = regex.matches(
            in: query,
            range: NSRange(location: 0, length: nsString.length)
        )

        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let fieldNameRange = match.range(at: 1)
            return nsString.substring(with: fieldNameRange)
        }
    }

    static func parseAttachmentMetadata(from value: Any?) -> AttachmentMetadata? {
        // Attachment metadata comes back as a dictionary with id, len, and optionally type
        guard let dict = value as? [String: Any],
              let id = dict["id"] as? String,
              let len = dict["len"] as? Int else {
            return nil
        }

        let type = dict["type"] as? String
        return AttachmentMetadata(id: id, len: len, type: type)
    }
}
