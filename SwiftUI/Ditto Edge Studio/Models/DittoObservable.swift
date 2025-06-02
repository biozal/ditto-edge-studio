//
//  DittoObservable.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import Foundation
import DittoSwift

public struct DittoObservable : Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var args: [String : Any?]?
    public var storeObserver: DittoStoreObserver?
    
    init(id: String){
        self.id = id
        self.name = ""
        self.query = ""
        self.args = nil
        storeObserver = nil
    }
    
    init(_ value: [String: Any?]) {
        self.id = value["_id"] as! String
        self.name = value["name"] as! String
        self.query = value["query"] as! String
        if (value.keys.contains("args")) {
            if let arguments = value["args"] as? [String: Any?] {
                self.args =  arguments
            }
        }
        storeObserver = nil
    }
}

extension DittoObservable {
    static func new() -> DittoObservable {
        return DittoObservable(id: UUID().uuidString)
    }
}
            

