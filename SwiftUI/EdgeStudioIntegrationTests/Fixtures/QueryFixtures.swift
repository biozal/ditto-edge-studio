import Foundation

/// Test fixtures for DQL queries
/// Provides sample queries for testing query execution and parsing
struct QueryFixtures {
    
    // MARK: - Basic SELECT Queries
    
    static let simpleSelect = "SELECT * FROM users"
    static let selectWithLimit = "SELECT * FROM users LIMIT 10"
    static let selectWithOffset = "SELECT * FROM users LIMIT 10 OFFSET 5"
    static let selectSpecificFields = "SELECT name, age, email FROM users"
    
    // MARK: - SELECT with WHERE Clauses
    
    static let selectWithWhere = "SELECT * FROM users WHERE age > 18"
    static let selectWithMultipleConditions = "SELECT * FROM users WHERE age > 18 AND status = 'active'"
    static let selectWithOrCondition = "SELECT * FROM users WHERE role = 'admin' OR role = 'moderator'"
    static let selectWithNotEqual = "SELECT * FROM users WHERE status != 'deleted'"
    static let selectWithLike = "SELECT * FROM users WHERE name LIKE '%John%'"
    static let selectWithIn = "SELECT * FROM users WHERE status IN ('active', 'pending')"
    
    // MARK: - SELECT with ORDER BY
    
    static let selectOrderByAsc = "SELECT * FROM users ORDER BY age ASC"
    static let selectOrderByDesc = "SELECT * FROM users ORDER BY createdAt DESC"
    static let selectOrderByMultiple = "SELECT * FROM users ORDER BY status ASC, age DESC"
    
    // MARK: - INSERT Queries
    
    static let insertSingle = "INSERT INTO users (name, age) VALUES ('Alice', 30)"
    static let insertMultiple = "INSERT INTO users (name, age) VALUES ('Alice', 30), ('Bob', 25)"
    static let insertAllFields = """
        INSERT INTO users (name, age, email, status, createdAt)
        VALUES ('Charlie', 35, 'charlie@example.com', 'active', '2024-01-01T00:00:00Z')
        """
    
    // MARK: - UPDATE Queries
    
    static let updateSingle = "UPDATE users SET age = 31 WHERE name = 'Alice'"
    static let updateMultipleFields = "UPDATE users SET age = 31, status = 'premium' WHERE name = 'Alice'"
    static let updateWithCondition = "UPDATE users SET status = 'inactive' WHERE lastLogin < '2023-01-01'"
    static let updateAll = "UPDATE users SET verified = true"
    
    // MARK: - DELETE Queries
    
    static let deleteSingle = "DELETE FROM users WHERE name = 'Alice'"
    static let deleteWithCondition = "DELETE FROM users WHERE status = 'deleted'"
    static let deleteOlderThan = "DELETE FROM users WHERE createdAt < '2020-01-01'"
    static let deleteAll = "DELETE FROM users"
    
    // MARK: - EVICT Queries (Ditto-specific)
    
    static let evictSingle = "EVICT FROM users WHERE _id = '123abc'"
    static let evictWithCondition = "EVICT FROM users WHERE status = 'archived'"
    static let evictOlderThan = "EVICT FROM users WHERE lastAccessed < '2022-01-01'"
    
    // MARK: - Complex Queries
    
    static let complexJoin = """
        SELECT users.name, orders.total
        FROM users
        INNER JOIN orders ON users._id = orders.userId
        WHERE orders.status = 'completed'
        """
    
    static let complexAggregation = """
        SELECT status, COUNT(*) as count, AVG(age) as avgAge
        FROM users
        GROUP BY status
        HAVING count > 10
        """
    
    static let nestedSubquery = """
        SELECT * FROM users
        WHERE age > (SELECT AVG(age) FROM users)
        """
    
    // MARK: - Invalid Queries (for error testing)
    
    static let malformedSelect = "SELECT * FORM users" // Typo: FORM instead of FROM
    static let missingSemicolon = "SELECT * FROM users WHERE age > 18"
    static let invalidSyntax = "SELECT FROM WHERE"
    static let emptyQuery = ""
    static let whitespaceOnly = "   \n\t  "
    static let missingClosingQuote = "SELECT * FROM users WHERE name = 'Alice"
    static let invalidFieldName = "SELECT !!invalid FROM users"
    
    // MARK: - Edge Cases
    
    static let unicodeCharacters = "SELECT * FROM users WHERE name = '日本語'"
    static let specialCharacters = "SELECT * FROM users WHERE email LIKE '%+test@example.com'"
    static let veryLongQuery = String(repeating: "SELECT * FROM users WHERE name = 'test' OR ", count: 100) + "name = 'final'"
    static let queryWithComments = """
        -- This is a comment
        SELECT * FROM users /* inline comment */ WHERE age > 18
        """
    
    // MARK: - Collection Variations
    
    static func selectFromCollection(_ collectionName: String) -> String {
        "SELECT * FROM \(collectionName)"
    }
    
    static func insertIntoCollection(_ collectionName: String, fields: [String: String]) -> String {
        let fieldNames = fields.keys.joined(separator: ", ")
        let values = fields.values.map { "'\($0)'" }.joined(separator: ", ")
        return "INSERT INTO \(collectionName) (\(fieldNames)) VALUES (\(values))"
    }
    
    static func updateCollection(_ collectionName: String, field: String, value: String, whereClause: String) -> String {
        "UPDATE \(collectionName) SET \(field) = '\(value)' WHERE \(whereClause)"
    }
    
    static func deleteFromCollection(_ collectionName: String, whereClause: String) -> String {
        "DELETE FROM \(collectionName) WHERE \(whereClause)"
    }
    
    // MARK: - Random Query Generation
    
    /// Generate random SELECT query for testing
    static func randomSelectQuery() -> String {
        let collectionName = "collection_\(UUID().uuidString.prefix(8))"
        let fieldName = ["name", "age", "status", "email"].randomElement()!
        return "SELECT * FROM \(collectionName) WHERE \(fieldName) = '\(UUID().uuidString)'"
    }
    
    /// Generate random INSERT query for testing
    static func randomInsertQuery() -> String {
        let collectionName = "collection_\(UUID().uuidString.prefix(8))"
        let name = "User_\(UUID().uuidString.prefix(8))"
        let age = Int.random(in: 18...80)
        return "INSERT INTO \(collectionName) (name, age) VALUES ('\(name)', \(age))"
    }
    
    // MARK: - Query Collections
    
    /// All valid SELECT queries
    static var allSelectQueries: [String] {
        [
            simpleSelect,
            selectWithLimit,
            selectWithOffset,
            selectSpecificFields,
            selectWithWhere,
            selectWithMultipleConditions,
            selectWithOrCondition,
            selectWithNotEqual,
            selectWithLike,
            selectWithIn,
            selectOrderByAsc,
            selectOrderByDesc,
            selectOrderByMultiple
        ]
    }
    
    /// All mutation queries (INSERT, UPDATE, DELETE)
    static var allMutationQueries: [String] {
        [
            insertSingle,
            insertMultiple,
            insertAllFields,
            updateSingle,
            updateMultipleFields,
            updateWithCondition,
            updateAll,
            deleteSingle,
            deleteWithCondition,
            deleteOlderThan
        ]
    }
    
    /// All invalid queries (for error testing)
    static var allInvalidQueries: [String] {
        [
            malformedSelect,
            invalidSyntax,
            emptyQuery,
            whitespaceOnly,
            missingClosingQuote,
            invalidFieldName
        ]
    }
}
