//
//  DittoManager_Query.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import Foundation
import DittoSwift

// MARK: Ditto Selected App - Query Operations
extension DittoManager {
    func executeSelectedAppQuery(query: String) async throws -> [DittoSwift.DittoQueryResultItem]? {
        if let ditto = dittoSelectedApp {
            let results = try await ditto.store.execute(query: query)
            return results.items
        }
        return nil
    }
}
