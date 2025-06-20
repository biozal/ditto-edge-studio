//
//  DittoQuery.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/6/25.
//

import Foundation

struct DittoQueryHistory
: Identifiable, Codable {
    var id: String
    var query: String
    var createdDate: String
    var selectedAppId: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case query
        case createdDate
        case selectedAppId = "selectedApp_id"
    }
    
    init(id: String,
         query: String,
         createdDate: String){
        self.id = id
        self.query = query
        self.createdDate = createdDate
        self.selectedAppId = ""
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        query = try container.decode(String.self, forKey: .query)
        createdDate = try container.decode(String.self, forKey: .createdDate)
        selectedAppId = try container
            .decode(
                String.self,
                forKey: .selectedAppId
            ) // This is unused, but included for compatibility
        
    }
    
}
