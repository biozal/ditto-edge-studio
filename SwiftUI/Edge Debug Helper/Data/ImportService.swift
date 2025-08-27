import Foundation
import DittoSwift
import UniformTypeIdentifiers

struct ImportService {
    static let shared = ImportService()
    
    private init() {}
    
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
        
        for (index, document) in documents.enumerated() {
            let documentId = document["_id"] as? String ?? "unknown"
            
            // Report progress
            progressHandler(ImportProgress(
                current: index + 1,
                total: totalDocuments,
                currentDocumentId: documentId
            ))
            
            do {
                // Validate collection name to prevent issues
                guard collection.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                    throw ImportError.invalidCollectionName("Collection name contains invalid characters. Only letters, numbers, and underscores are allowed.")
                }
                
                // Validate document structure
                guard let documentId = document["_id"] as? String, !documentId.isEmpty else {
                    throw ImportError.missingID("Document is missing a valid '_id' field")
                }
                
                // Use Ditto's collection API instead of raw DQL to avoid SQL parsing issues
                // This is much safer and handles escaping automatically
                try await withErrorHandling {
                    try await ditto.store
                        .collection(collection)
                        .upsert(document)
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