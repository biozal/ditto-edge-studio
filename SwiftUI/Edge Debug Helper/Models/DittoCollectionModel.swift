//
//  DittoCollectionModel.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/7/25.
//

import Foundation

struct DittoCollection: Codable {
    let _id: String
    let name: String
}

struct DittoCollectionModel: Codable {
    let name: String
    let documentCount: Int
}
