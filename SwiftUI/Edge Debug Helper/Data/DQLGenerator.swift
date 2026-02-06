import Foundation

/// Service for generating DQL (Ditto Query Language) statement templates
struct DQLGenerator {
    
    // MARK: - SELECT Statement
    
    /// Generates a SELECT statement with all specified fields
    static func generateSelect(collection: String, fields: [String]) -> String {
        let fieldList = fields.joined(separator: ", ")
        return "SELECT \(fieldList) FROM \(collection)"
    }
    
    /// Generates a SELECT * statement
    static func generateSelectAll(collection: String) -> String {
        return "SELECT * FROM \(collection)"
    }
    
    // MARK: - INSERT Statement
    
    /// Generates an INSERT statement with placeholder values
    static func generateInsert(collection: String, fields: [String], fieldTypes: [String: TableCellValue]? = nil) -> String {
        let placeholders = fields.map { field in
            let placeholder = placeholderValue(for: field, type: fieldTypes?[field])
            return "\"\(field)\": \(placeholder)"
        }.joined(separator: ", ")
        
        return "INSERT INTO \(collection) DOCUMENTS ({ \(placeholders) })"
    }
    
    // MARK: - UPDATE Statement
    
    /// Generates an UPDATE statement with placeholder values, excluding _id from SET clause
    static func generateUpdate(collection: String, fields: [String], fieldTypes: [String: TableCellValue]? = nil) -> String {
        // Exclude _id from SET clause
        let fieldsToUpdate = fields.filter { $0 != "_id" }
        
        let setClause = fieldsToUpdate.map { field in
            let placeholder = placeholderValue(for: field, type: fieldTypes?[field])
            return "\(field) = \(placeholder)"
        }.joined(separator: ", ")
        
        return "UPDATE \(collection) SET \(setClause) WHERE _id = '<document-id>'"
    }
    
    // MARK: - DELETE Statement
    
    /// Generates a DELETE statement with WHERE clause
    static func generateDelete(collection: String) -> String {
        return "DELETE FROM \(collection) WHERE _id = '<document-id>'"
    }
    
    // MARK: - EVICT Statement
    
    /// Generates an EVICT statement with WHERE clause
    static func generateEvict(collection: String) -> String {
        return "EVICT FROM \(collection) WHERE _id = '<document-id>'"
    }
    
    // MARK: - Helper Methods
    
    /// Returns an appropriate placeholder value based on field name and type
    private static func placeholderValue(for field: String, type: TableCellValue?) -> String {
        if field == "_id" {
            return "\"<document-id>\""
        }
        
        if let type = type {
            switch type {
            case .string: return "\"<value>\""
            case .number: return "0"
            case .bool: return "true"
            case .null: return "null"
            case .nested: return "{}"
            }
        }
        
        return "\"<value>\""
    }
}
