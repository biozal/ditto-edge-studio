import Foundation

struct DittoIndex: Identifiable {
    let _id: String // index name (from system:indexes)
    let collection: String
    let fields: [String]
    var id: String {
        _id
    }

    init(id: String, collection: String, fields: [String]) {
        _id = id
        self.collection = collection
        self.fields = fields
    }
}

struct DittoCollection: Codable {
    let _id: String
    let name: String
    var documentCount: Int?
    var indexes: [DittoIndex] = []

    /// indexes is populated after decoding and must not be included in CodingKeys —
    /// the __collections query result has no "indexes" field, and non-optional types
    /// without a CodingKey cause a keyNotFound DecodingError at runtime.
    enum CodingKeys: String, CodingKey {
        case _id
        case name
        case documentCount
    }
}

extension DittoIndex {
    /// Strips the SDK-added "{collection}." prefix from the stored index name.
    /// SDK stores "comments.idx_comments_movie_id" → display as "idx_comments_movie_id"
    var displayName: String {
        guard let dot = _id.firstIndex(of: ".") else { return _id }
        return String(_id[_id.index(after: dot)...])
    }
}

extension String {
    /// Strips backtick quotes the SDK adds around field names: `movie_id` → movie_id
    var strippingBackticks: String {
        replacingOccurrences(of: "`", with: "")
    }
}

struct CollectionDocCount: Codable {
    let key: String // e.g., "collection_num_docs[theaters]"
    let value: Int // e.g., 1564

    var collectionName: String? {
        // Extract "theaters" from "collection_num_docs[theaters]"
        guard key.hasPrefix("collection_num_docs["),
              key.hasSuffix("]") else
        {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 20) // Position after "collection_num_docs["
        let end = key.index(before: key.endIndex)
        return String(key[start ..< end])
    }
}
