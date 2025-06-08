//
//  DittoObserveEvent.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/5/25.
//

import Foundation

public struct DittoObserveEvent {
    
    //used for tracking unique observe events
    public var id: String
    
    //used to link to the Selected Observer
    public var observeId: String
    
    public var insertCount: Int = 0
    public var updateCount: Int = 0
    public var deleteCount: Int = 0
    public var moveCount: Int = 0
    public var dataCount: Int = 0

    public var data: [String] = []
    public var insertedJson: [String] = []
    public var updatedJson: [String] = []
    public var deletedIndexes: [Int] = []
    
    public var eventTime: String = ""
}

extension DittoObserveEvent {
    static func new(observeId: String) -> DittoObserveEvent {
        return DittoObserveEvent(
            id: UUID().uuidString,
            observeId: observeId)
    }
}
