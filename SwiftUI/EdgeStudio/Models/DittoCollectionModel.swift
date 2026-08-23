import Foundation

/// One key in a DQL index definition: a field path plus its sort direction.
/// Two or more keys form a composite index (Ditto SDK 5.1+).
struct IndexField: Equatable, Hashable, Sendable {
    var name: String
    var ascending: Bool

    init(name: String, ascending: Bool = true) {
        self.name = name
        self.ascending = ascending
    }

    /// Field name without SDK backtick-quoting. Keeps the
    /// `fields.map(\.strippingBackticks)` keypath call sites (e.g. the MCP
    /// tool handlers) compiling now that `DittoIndex.fields` is `[IndexField]`.
    var strippingBackticks: String {
        name.strippingBackticks
    }
}

struct DittoIndex: Identifiable {
    let _id: String // index name (from system:indexes)
    let collection: String
    /// Index keys with sort direction — direction is preserved so the UI can
    /// show ASC/DESC for composite indexes.
    let fields: [IndexField]
    var id: String {
        _id
    }

    init(id: String, collection: String, fields: [IndexField]) {
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
