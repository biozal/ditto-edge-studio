//
//  DittoSubscription.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import Foundation
import DittoSwift

public struct DittoSubscription : Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var args: String?
    public var syncSubscription: DittoSyncSubscription?
    
    init(id: String){
        self.id = id
        self.name = ""
        self.query = ""
        self.args = nil
        syncSubscription = nil
    }
    
    init(_ value: [String: Any?]) {
        self.id = value["_id"] as! String
        self.name = value["name"] as! String
        self.query = value["query"] as! String
        if (value.keys.contains("args")) {
            if let arguments = value["args"] as? String  {
                self.args =  arguments
            }
        }
        syncSubscription = nil
    }
}

extension DittoSubscription {
    static func new() -> DittoSubscription {
        return DittoSubscription(id: UUID().uuidString)
    }
}
            
