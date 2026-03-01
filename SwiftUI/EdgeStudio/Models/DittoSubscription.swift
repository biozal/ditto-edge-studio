import DittoSwift
import Foundation

public struct DittoSubscription: Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var syncSubscription: DittoSyncSubscription?

    init(id: String) {
        self.id = id
        name = ""
        query = ""
        syncSubscription = nil
    }

    init(_ value: [String: Any?]) {
        id = value["_id"] as? String ?? UUID().uuidString
        name = value["name"] as? String ?? "Unnamed Subscription"
        query = value["query"] as? String ?? ""
        syncSubscription = nil
    }
}

extension DittoSubscription {
    static func new() -> DittoSubscription {
        DittoSubscription(id: UUID().uuidString)
    }
}
