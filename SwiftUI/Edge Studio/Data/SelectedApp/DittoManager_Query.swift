//
//  DittoManager_Query.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import Foundation
import DittoSwift

extension DittoManager {
    
    // MARK: Query Execution
    
    func executeSelectedAppQuery(query: String) async throws -> [String] {
        if let ditto = dittoSelectedApp {
            let results = try await ditto.store.execute(query: query)
            if results.items.isEmpty {
                if (!results.mutatedDocumentIDs().isEmpty) {
                    let resultsStrings = results.mutatedDocumentIDs().compactMap {
                        return "Document ID: \($0.stringValue)"
                    }
                    return resultsStrings.isEmpty ? ["No results found"] : resultsStrings
                } else {
                    return ["No results found"]
                }
            } else {
                let resultJsonStrings = results.items.compactMap {
                    item -> String? in
                    // Convert [String: Any?] to [String: Any] by removing nil values
                    let cleanedValue = item.value.compactMapValues {
                        $0
                    }
                    
                    do {
                        let data = try JSONSerialization.data(
                            withJSONObject: cleanedValue,
                            options: [
                                .prettyPrinted,
                                .fragmentsAllowed,
                                .sortedKeys,
                                .withoutEscapingSlashes,
                            ]
                        )
                        return String(data: data, encoding: .utf8)
                    } catch {
                        return nil
                    }
                }
                return resultJsonStrings.isEmpty ? ["No results found"] : resultJsonStrings
            }
        }
        return ["No results found"]
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
        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let mutatedDocumentIDs = (jsonObject["mutatedDocumentIds"] as? [String]) {
                if mutatedDocumentIDs.count > 0 {
                    return mutatedDocumentIDs.map { "Document ID: \($0)" }
                }
            }
            
            if let results = jsonObject["items"] as? [[String: Any]] {
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
        }
        
        // If response format is different, return the whole thing as one item
        if let jsonString = String(data: data, encoding: .utf8) {
            return [jsonString]
        }
        return ["No results found"]
    }
    
    // MARK: Query Favorite
    
    func deleteFavorite(_ id: String) async throws {
        guard let ditto = dittoLocal
        else {
            throw InvalidStateError(message: "No Ditto local database available. You should never see this message.")
        }
        let query = "DELETE FROM dittoqueryfavorites WHERE _id = :id"
        let arguments: [String: Any] = [ "id": id ]
        let _ = try await ditto.store.execute(query: query, arguments: arguments)
    }

    func saveFavorite(_ favorite: DittoQueryHistory) async throws {
        guard let ditto = dittoLocal,
              let selectedAppConfig = dittoSelectedAppConfig
        else {
            throw InvalidStateError(message: "No Ditto SelectedApp available. You should never see this message.")
        }
        let query = "INSERT INTO dittoqueryfavorites DOCUMENTS (:queryHistory)"
        let arguments: [String: Any] = [
            "queryHistory": [
                "_id": UUID().uuidString,
                "query": favorite.query,
                "createdDate": Date().ISO8601Format(),
                "selectedApp_id": selectedAppConfig._id
            ]
        ]
        let _ = try await ditto.store.execute(query: query, arguments: arguments)
    }
        
    // MARK: Query History
    
    func clearQueryHistory() async throws {
        guard let ditto = dittoLocal,
              let selectedAppConfig = dittoSelectedAppConfig
        else {
            throw InvalidStateError(message: "No Ditto SelectedApp available. You should never see this message.")
        }
        let query = "DELETE FROM dittoqueryhistory WHERE selectedApp_id = :selectedApp_id"
        let arguments: [String: Any] = [ "selectedApp_id": selectedAppConfig._id ]
        let _ = try await ditto.store.execute(query: query, arguments: arguments)
    }
    
    func deleteQueryHistory(_ id: String) async throws {
        guard let ditto = dittoLocal
        else {
            throw InvalidStateError(message: "No Ditto local database available. You should never see this message.")
        }
        let query = "DELETE FROM dittoqueryhistory WHERE _id = :id"
        let arguments: [String: Any] = [ "id": id ]
        let _ = try await ditto.store.execute(query: query, arguments: arguments)
    }
   
    func saveQueryHistory(_ history: DittoQueryHistory) async throws {
        guard let ditto = dittoLocal,
              let selectedAppConfig = dittoSelectedAppConfig
        else {
            throw InvalidStateError(message: "No Ditto SelectedApp available. You should never see this message.")
        }
        //check if we already have the query if so then just update the date, otherwise insert new record
        let queryCheck = "SELECT * FROM dittoqueryhistory WHERE query = :query"
        let argumentsCheck: [String: Any] =
        ["query": history.query]
        let resultsCheck = try await ditto.store.execute(query: queryCheck, arguments: argumentsCheck)
        if resultsCheck.items.count > 0 {
            let decoder = JSONDecoder()
            guard let item = resultsCheck.items.first else {
                return
            }
            let existingHistory = try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
            let query = "UPDATE dittoqueryhistory SET createdDate = :createdDate WHERE _id = :id"
            let arguments: [String: Any] = [
                "id": existingHistory.id,
                "createdDate": Date().ISO8601Format()
             ]
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
            
        } else {
            let query = "INSERT INTO dittoqueryhistory DOCUMENTS (:queryHistory)"
            let arguments: [String: Any] = [
                "queryHistory": [
                    "_id": history.id,
                    "query": history.query,
                    "createdDate": history.createdDate,
                    "selectedApp_id": selectedAppConfig._id
                ]
            ]
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
        }
    }
}
