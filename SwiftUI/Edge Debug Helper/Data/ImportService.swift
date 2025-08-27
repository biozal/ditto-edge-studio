import Foundation
import DittoSwift
import UniformTypeIdentifiers

struct ImportService {
    static let shared = ImportService()
    
    private init() {}
    
    enum InsertType {
        case regular
        case initial
    }
    
    struct ImportResult {
        let successCount: Int
        let failureCount: Int
        let errors: [String]
    }
    
    struct ImportProgress {
        let current: Int
        let total: Int
        let currentDocumentId: String?
    }
    
    func validateJSON(_ data: Data) throws -> [[String: Any]] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ImportError.invalidJSON("File must contain an array of JSON objects")
        }
        
        for (index, object) in jsonArray.enumerated() {
            if object["_id"] == nil {
                throw ImportError.missingID("Document at index \(index) is missing required '_id' field")
            }
        }
        
        return jsonArray
    }
    
    @MainActor
    func importData(
        from url: URL,
        to collection: String,
        insertType: InsertType = .regular,
        progressHandler: @escaping (ImportProgress) -> Void
    ) async throws -> ImportResult {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.fileAccessDenied("Unable to access the selected file. Please try selecting it again.")
        }
        
        // Ensure we stop accessing when we're done
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Read the file data
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileAccessDenied("Could not read file: \(error.localizedDescription)")
        }
        
        let documents = try validateJSON(data)
        let totalDocuments = documents.count
        
        guard let ditto = await DittoManager.shared.dittoSelectedApp else {
            throw ImportError.noDittoInstance("No Ditto instance available")
        }
        
        var successCount = 0
        var failureCount = 0
        var errors: [String] = []
        
        // Validate collection name to prevent SQL injection
        guard collection.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw ImportError.invalidCollectionName("Collection name contains invalid characters. Only letters, numbers, and underscores are allowed.")
        }
        
        // Process documents in batches for better performance
        let batchSize = 50
        for (batchIndex, batch) in documents.chunked(into: batchSize).enumerated() {
            let batchStartIndex = batchIndex * batchSize
            
            for (indexInBatch, document) in batch.enumerated() {
                let globalIndex = batchStartIndex + indexInBatch
                let documentId = document["_id"] as? String ?? "unknown"
                
                // Report progress
                progressHandler(ImportProgress(
                    current: globalIndex + 1,
                    total: totalDocuments,
                    currentDocumentId: documentId
                ))
                
                do {
                    // Validate document structure
                    guard let documentId = document["_id"] as? String, !documentId.isEmpty else {
                        throw ImportError.missingID("Document is missing a valid '_id' field")
                    }
                    
                    // Convert document to JSON string
                    let jsonData = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                        throw ImportError.encodingError("Failed to encode document as JSON")
                    }
                    
                    // Build the appropriate DQL INSERT statement
                    let dqlQuery: String
                    if insertType == .initial {
                        // Use INSERT WITH INITIAL DOCUMENTS for initial data load
                        dqlQuery = "INSERT INTO \(collection) DOCUMENTS (\(jsonString)) WITH INITIAL DOCUMENTS"
                    } else {
                        // Use regular INSERT for normal operations
                        dqlQuery = "INSERT INTO \(collection) DOCUMENTS (\(jsonString))"
                    }
                    
                    // Execute the DQL query using store.execute
                    try await withErrorHandling {
                        _ = try await ditto.store.execute(query: dqlQuery)
                    }
                    
                    successCount += 1
                    
                    // Add small delay to make progress visible for small datasets
                    if totalDocuments < 50 {
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                    }
                } catch let dittoError as DittoError {
                    failureCount += 1
                    let errorMessage = "Ditto error for document \(documentId): \(dittoError.localizedDescription)"
                    errors.append(errorMessage)
                    print("Ditto Import Error: \(errorMessage)")
                } catch {
                    failureCount += 1
                    let errorMessage = "Failed to import document \(documentId): \(error.localizedDescription)"
                    errors.append(errorMessage)
                    print("Import Error: \(errorMessage)")
                }
            }
        }
        
        return ImportResult(
            successCount: successCount,
            failureCount: failureCount,
            errors: errors
        )
    }
    
    // Helper function to wrap Ditto operations with better error handling
    private func withErrorHandling<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            // Log the error for debugging
            print("Ditto operation failed: \(error)")
            throw error
        }
    }
}

enum ImportError: LocalizedError {
    case invalidJSON(String)
    case missingID(String)
    case noDittoInstance(String)
    case encodingError(String)
    case fileAccessDenied(String)
    case invalidCollectionName(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message),
             .missingID(let message),
             .noDittoInstance(let message),
             .encodingError(let message),
             .fileAccessDenied(let message),
             .invalidCollectionName(let message):
            return message
        }
    }
}

// Extension to support chunking arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}