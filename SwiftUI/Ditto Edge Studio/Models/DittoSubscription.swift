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
    public var args: [String : Any?]?
    public var isActive: Bool
    public var syncSubscription: DittoSyncSubscription?
}

extension DittoSubscription {
    static func new() -> DittoSubscription {
        return DittoSubscription(
            id: UUID().uuidString,
            name: "",
            query: "",
            args: nil,
            isActive: false,
            syncSubscription: nil)
    }
}
            
