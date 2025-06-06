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
    
    func getCollections() async throws -> [String]  {
        guard let ditto = dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto SelectedApp available. You should never see this message.")
        }
        let query = "SELECT * FROM __collections"
        let results = try await ditto.store.execute(query: query)
        let collections =  results.items.compactMap { $0.value["name"] as? String }
        // Filter out system collections that start with "__"
        .filter { !$0.hasPrefix("__") }
        return collections
    }
   
    func saveQueryHistory(_ history: DittoQueryHistory) async throws {
        guard let ditto = dittoLocal,
        let selectedAppConfig = dittoSelectedAppConfig
        else {
            throw InvalidStateError(message: "No Ditto SelectedApp available. You should never see this message.")
        }
        let query = "INSERT INTO dittoqueryhistory DOCUMENTS (:queryHistory)"
        let arguments: [String: Any] = [
            "queryHistory": [
                "_id": history.id,
                "query": history.query,
                "createdDate": history.createdDate,
                "selectedApp_id": selectedAppConfig._id
            ]
        ]
        let results = try await ditto.store.execute(query: query, arguments: arguments)
    }
    
    func executeSelectedAppQuery(query: String) async throws -> [DittoSwift.DittoQueryResultItem]? {
        if let ditto = dittoSelectedApp {
            let results = try await ditto.store.execute(query: query)
            return results.items
        }
        return nil
    }
    
    func executeSelectedAppQueryHttp(query: String) async throws -> [String] {
        guard let appConfig = dittoSelectedAppConfig  else {
            return ["{'error': 'No Ditto SelectedApp available.  You should never see this message.'}"];
        }
        
        let urlString = "https://\(appConfig.httpApiUrl)/api/v4/store/execute"
        let authorization = "Bearer \(appConfig.httpApiKey)"
        
        guard let url = URL(string: urlString) else {
            return ["{'error': 'Invalid URL string.'}"]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authorization, forHTTPHeaderField: "Authorization")
        
        // Create the request body with the query
        let requestBody = ["statement": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return ["HTTP Error: \(errorBody)"]
        }
        
        // Parse the response data
        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = jsonObject["items"] as? [[String: Any]] {
            
            // Convert each item to a JSON string
            var resultStrings = [String]()
            
            for item in results {
                if let itemData = try? JSONSerialization.data(withJSONObject: item,
                                                              options: [
                                                                .withoutEscapingSlashes,
                                                                .fragmentsAllowed,
                                                                .prettyPrinted,
                                                                .sortedKeys]),
                   let itemString = String(data: itemData, encoding: .utf8) {
                    resultStrings.append(itemString)
                }
            }
            
            return resultStrings.isEmpty ? ["No items found"] : resultStrings
        }
        
        // If response format is different, return the whole thing as one item
        if let jsonString = String(data: data, encoding: .utf8) {
            return [jsonString]
        }
 
        return ["No results found"]
        
    }
}
