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
    
    public var insertedJson: [String] = []
    public var updatedJson: [String] = []
    public var deletedJson: [String] = []

}
