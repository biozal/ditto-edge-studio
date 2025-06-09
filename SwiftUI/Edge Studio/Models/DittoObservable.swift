//
//  DittoObservable.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import Foundation
import DittoSwift

public struct DittoObservable : Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var args: String?
    public var isActive: Bool
    public var storeObserver: DittoStoreObserver?
    public var isLoading: Bool? = false
    
    init(id: String){
        self.id = id
        self.name = ""
        self.query = ""
        self.args = nil
        self.isActive = false
        storeObserver = nil
    }
    
    init(_ value: [String: Any?]) {
        self.id = value["_id"] as! String
        self.name = value["name"] as! String
        self.query = value["query"] as! String
        self.isActive = value["isActive"] as? Bool ?? false
        
        if (value.keys.contains("args")) {
            if let arguments = value["args"] as? String {
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
            

