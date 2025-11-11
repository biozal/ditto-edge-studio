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
            let resultJsonStrings = results.items.compactMap { item -> String? in
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

    // MARK: Collection Size
    func getCollectionCount(collection: String) async throws -> Int {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw NSError(domain: "QueryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Ditto instance available"])
        }

        let query = "SELECT COUNT(*) as count FROM \(collection)"
        let results = try await ditto.store.execute(query: query)

        // Extract count from the first result
        guard let firstItem = results.items.first,
              let count = firstItem.value["count"] as? Int else {
            return 0
        }

        return count
    }

    // MARK: Delete Document
    func deleteDocument(documentId: String, collection: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw NSError(domain: "QueryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Ditto instance available"])
        }

        let query = "DELETE FROM \(collection) WHERE _id = :id"
        let arguments = ["id": documentId]
        let results = try await ditto.store.execute(query: query, arguments: arguments)

        // Verify deletion occurred
        guard !results.mutatedDocumentIDs().isEmpty else {
            throw NSError(domain: "QueryService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Delete query executed but no documents were mutated"])
        }
    }

    // MARK: Delete Multiple Documents
    func deleteDocuments(documentIds: [String], collection: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw NSError(domain: "QueryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Ditto instance available"])
        }

        guard !documentIds.isEmpty else {
            return
        }

        // Batch deletions to avoid huge SQL queries
        // Process in chunks of 100 to keep queries manageable
        let batchSize = 100

        for batchStart in stride(from: 0, to: documentIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, documentIds.count)
            let batch = Array(documentIds[batchStart..<batchEnd])

            // Create WHERE clause with IN operator for this batch
            var arguments: [String: Any] = [:]
            var placeholders: [String] = []

            for (index, id) in batch.enumerated() {
                let key = "id\(index)"
                arguments[key] = id
                placeholders.append(":\(key)")
            }

            let placeholderString = placeholders.joined(separator: ", ")
            let query = "DELETE FROM \(collection) WHERE _id IN (\(placeholderString))"

            _ = try await ditto.store.execute(query: query, arguments: arguments)
        }
    }
}
