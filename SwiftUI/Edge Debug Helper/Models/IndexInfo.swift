import Foundation

struct IndexInfo: Identifiable {
    let id: String
    let collection: String
    let fields: [String]
    
    init(from dictionary: [String: Any]) {
        self.id = dictionary["_id"] as? String ?? UUID().uuidString
        self.collection = dictionary["collection"] as? String ?? "Unknown"
        self.fields = dictionary["fields"] as? [String] ?? []
    }
    
    init?(_ data: Data) {
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.init(from: jsonObject)
            } else {
                assertionFailure("IndexInfo: Failed to cast JSON object to [String: Any]")
                return nil
            }
        } catch {
            assertionFailure("IndexInfo decoding error: \(error.localizedDescription)")
            return nil
        }
    }
    
    var formattedFields: String {
        return fields.joined(separator: ", ")
    }
}