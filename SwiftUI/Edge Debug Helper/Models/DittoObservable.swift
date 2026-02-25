import DittoSwift
import Foundation

public struct DittoObservable: Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var isActive: Bool
    public var lastUpdated: String?
    public var storeObserver: DittoStoreObserver?
    public var isLoading: Bool? = false

    init(id: String) {
        self.id = id
        name = ""
        query = ""
        isActive = false
        lastUpdated = nil
        storeObserver = nil
    }

    init(_ value: [String: Any?]) {
        id = value["_id"] as? String ?? UUID().uuidString
        name = value["name"] as? String ?? "Unnamed Observable"
        query = value["query"] as? String ?? ""
        isActive = value["isActive"] as? Bool ?? false
        lastUpdated = value["lastUpdated"] as? String
        storeObserver = nil
    }
}

extension DittoObservable {
    static func new() -> DittoObservable {
        DittoObservable(id: UUID().uuidString)
    }
}
