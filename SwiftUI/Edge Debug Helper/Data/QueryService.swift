import Foundation
import DittoSwift

actor QueryService {
    static let shared = QueryService()
    
    private let dittoManager = DittoManager.shared
    
    private init() { }
    
    // MARK: Query Execution
    func executeSelectedAppQuery(query: String) async throws -> [String] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            return ["No results found"]
        }
        
        let results = try await ditto.store.execute(query: query)
        if results.items.isEmpty {
            if (!results.mutatedDocumentIDs().isEmpty) {
                var resultsStrings = results.mutatedDocumentIDs().compactMap {
                    return "Document ID: \($0.stringValue)"
                }
                if let commitID = results.commitID {
                    resultsStrings.append("Commit ID: \(commitID)")
                } else {
                    resultsStrings.append("Commit ID: N/A")
                }
                return resultsStrings
            } else {
                return ["No results found"]
            }
        } else {
            print("[QueryService] Query returned \(results.items.count) items")
            let resultJsonStrings = results.items.enumerated().compactMap { index, item -> String? in
                // Convert [String: Any?] to [String: Any] by removing nil values
                let cleanedValue = item.value.compactMapValues {
                    $0
                }

                print("[QueryService] Item[\(index)] keys: \(cleanedValue.keys.sorted())")
                print("[QueryService] Item[\(index)] full value: \(cleanedValue)")

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
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("[QueryService] Item[\(index)] JSON length: \(jsonString.count) chars")
                        return jsonString
                    }
                    return nil
                } catch {
                    print("[QueryService] ERROR Item[\(index)] JSON serialization error: \(error)")
                    return nil
                }
            }
            print("[QueryService] Returning \(resultJsonStrings.count) JSON strings")
            return resultJsonStrings.isEmpty ? ["No results found"] : resultJsonStrings
        }
    }
    
    func executeSelectedAppQueryHttp(query: String) async throws -> [String] {
        guard let appConfig = await dittoManager.dittoSelectedAppConfig else {
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
        
        let (data, response): (Data, URLResponse)
        
        if appConfig.allowUntrustedCerts {
            // Use cached URLSession that allows untrusted certificates
            let session = await dittoManager.getCachedUntrustedSession()
            (data, response) = try await session.data(for: request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return ["HTTP Error: \(errorBody)"]
        }
        
        // Parse the response data
        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let mutatedDocumentIDs = (jsonObject["mutatedDocumentIds"] as? [String]) {
                if mutatedDocumentIDs.count > 0 {
                    var resultStrings = mutatedDocumentIDs.map { "Document ID: \($0)" }
                    if let commitId = jsonObject["commitId"] as? String {
                        resultStrings.append("Commit ID: \(commitId)")
                    }
                    return resultStrings
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

    // MARK: Delete Document
    func deleteDocument(documentId: String, collection: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw NSError(domain: "QueryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Ditto instance available"])
        }

        print("[QueryService] Deleting document with ID: \(documentId) from collection: \(collection)")

        let query = "DELETE FROM \(collection) WHERE _id = :id"
        let arguments = ["id": documentId]
        print("[QueryService] Executing delete query: \(query)")
        print("[QueryService] Query arguments: \(arguments)")
        print("[QueryService] Substituted query: DELETE FROM \(collection) WHERE _id = '\(documentId)'")

        let results = try await ditto.store.execute(query: query, arguments: arguments)

        if !results.mutatedDocumentIDs().isEmpty {
            print("[QueryService] Successfully deleted document. Mutated IDs: \(results.mutatedDocumentIDs())")
        } else {
            print("[QueryService] WARNING: Delete query executed but no documents were mutated")
        }
    }
}
