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
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ImportError.invalidJSON("File contains invalid JSON syntax: \(error.localizedDescription)")
        }

        // Must be an array
        guard let jsonArray = jsonObject as? [Any] else {
            throw ImportError.invalidJSON("""
                Invalid format: File must contain a JSON array.

                Expected format:
                [
                  {"field1": "value1", "field2": "value2"},
                  {"field1": "value3", "field2": "value4"}
                ]

                Your file appears to contain a single object instead of an array.
                Wrap your data in square brackets [ ] to create an array.
                """)
        }

        // Array must contain only objects
        var documents: [[String: Any]] = []
        for (index, element) in jsonArray.enumerated() {
            guard let object = element as? [String: Any] else {
                let elementType: String
                if element is String {
                    elementType = "a string"
                } else if element is NSNumber {
                    elementType = "a number"
                } else if element is [Any] {
                    elementType = "an array"
                } else {
                    elementType = "type: \(type(of: element))"
                }

                throw ImportError.invalidJSON("""
                    Invalid format: Element at index \(index) is \(elementType), not a JSON object.

                    Each element in the array must be a JSON object with key-value pairs.
                    Example: {"name": "John", "age": 30}
                    """)
            }

            // Validate object is not empty
            if object.isEmpty {
                throw ImportError.invalidJSON("Document at index \(index) is empty. Each document must have at least one field.")
            }

            documents.append(object)
        }

        if documents.isEmpty {
            throw ImportError.invalidJSON("The JSON array is empty. Add at least one document to import.")
        }

        return documents
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

        // Register collection in __collections if it doesn't exist (idempotent operation)
        // This ensures the collection appears in Edge Studio even if it was unregistered
        do {
            try await EdgeStudioCollectionService.shared.registerCollection(name: collection)
        } catch {
            // Log but don't fail import if registration fails
            // The collection will still work, just might not appear in UI
            print("Warning: Failed to register collection '\(collection)' in __collections: \(error)")
        }

        // Process documents in batches for better performance
        let batchSize = 50
        for (batchIndex, batch) in documents.chunked(into: batchSize).enumerated() {
            let batchStartIndex = batchIndex * batchSize
            
            for (indexInBatch, document) in batch.enumerated() {
                let globalIndex = batchStartIndex + indexInBatch
                let documentId = document["_id"] as? String ?? "document_\(globalIndex)"

                // Report progress
                progressHandler(ImportProgress(
                    current: globalIndex + 1,
                    total: totalDocuments,
                    currentDocumentId: documentId
                ))

                do {
                    // Note: _id is optional - if not provided, Ditto will generate one

                    // Build the DQL INSERT statement using parameterized query
                    // This is safer and cleaner than manual string formatting
                    let dqlQuery: String
                    if insertType == .initial {
                        dqlQuery = "INSERT INTO \(collection) INITIAL DOCUMENTS (:documents)"
                    } else {
                        dqlQuery = "INSERT INTO \(collection) DOCUMENTS (:documents)"
                    }

                    // Execute the DQL query with the document as a parameter
                    try await withErrorHandling {
                        _ = try await ditto.store.execute(
                            query: dqlQuery,
                            arguments: ["documents": document]
                        )
                    }

                    successCount += 1
                    
                    // Add small delay to make progress visible for small datasets
                    if totalDocuments < 50 {
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                    }
                } catch let formattingError as DQLFormattingError {
                    failureCount += 1
                    let errorMessage = "Formatting error for document \(documentId): \(formattingError.localizedDescription)"
                    errors.append(errorMessage)
                } catch let dittoError as DittoError {
                    failureCount += 1
                    let errorMessage = "Ditto error for document \(documentId): \(dittoError.localizedDescription)"
                    errors.append(errorMessage)
                } catch {
                    failureCount += 1
                    let errorMessage = "Failed to import document \(documentId): \(error.localizedDescription)"
                    errors.append(errorMessage)
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