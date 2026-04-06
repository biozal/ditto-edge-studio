import Foundation

/// Represents a parsed attachment token found in a document field.
struct AttachmentInfo: Identifiable {
    let id: String // Cryptographic hash from token
    let fieldName: String // The document field containing this token
    let length: Int // Blob size in bytes
    let metadata: [String: String]

    /// Human-readable file size (e.g., "2.4 MB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .file)
    }

    /// MIME type from metadata, if present
    var mimeType: String? {
        metadata["mimeType"] ?? metadata["mime_type"] ?? metadata["type"]
    }

    /// File name from metadata, if present
    var fileName: String? {
        metadata["name"] ?? metadata["fileName"] ?? metadata["file_name"]
    }

    /// Whether this attachment is an image based on MIME type
    var isImage: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("image/")
    }
}

extension AttachmentInfo {
    /// Scans a JSON document dictionary for fields that look like attachment tokens.
    /// An attachment token has the shape: { "id": String, "len": Number, "metadata": Object }
    static func detectTokens(in jsonString: String) -> [AttachmentInfo] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            return []
        }

        var results: [AttachmentInfo] = []
        for (key, value) in dict {
            guard let obj = value as? [String: Any],
                  let id = obj["id"] as? String,
                  let len = obj["len"] as? Int,
                  let meta = obj["metadata"] as? [String: String] else
            {
                continue
            }
            results.append(AttachmentInfo(
                id: id,
                fieldName: key,
                length: len,
                metadata: meta
            ))
        }
        return results
    }
}
