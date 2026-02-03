import Foundation

struct DittoCollection: Codable {
    let _id: String
    let name: String
    var documentCount: Int?
}

struct CollectionDocCount: Codable {
    let key: String    // e.g., "collection_num_docs[theaters]"
    let value: Int     // e.g., 1564

    var collectionName: String? {
        // Extract "theaters" from "collection_num_docs[theaters]"
        guard key.hasPrefix("collection_num_docs["),
              key.hasSuffix("]") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 20) // Position after "collection_num_docs["
        let end = key.index(before: key.endIndex)
        return String(key[start..<end])
    }
}
