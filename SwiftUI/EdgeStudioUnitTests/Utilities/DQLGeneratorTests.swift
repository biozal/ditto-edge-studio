import Testing
@testable import Edge_Debug_Helper

/// Comprehensive test suite for DQLGenerator
///
/// Tests cover:
/// - SELECT statements (all fields, specific fields)
/// - INSERT statements (various field types, _id handling)
/// - UPDATE statements (_id excluded from SET, type-aware placeholders)
/// - DELETE statements (WHERE clause structure)
/// - EVICT statements (WHERE clause structure)
/// - Edge cases (empty fields, single field, special collection names)
///
/// All tests are pure string generation — no database dependency.
/// Target: 90% code coverage for DQLGenerator.
@Suite("DQL Generator Tests")
struct DQLGeneratorTests {

    // MARK: - SELECT Tests

    @Suite("SELECT Statements")
    struct SelectTests {

        @Test("generateSelectAll produces SELECT * FROM collection", .tags(.utility, .fast))
        func testGenerateSelectAll() {
            // ARRANGE
            let collection = "users"

            // ACT
            let result = DQLGenerator.generateSelectAll(collection: collection)

            // ASSERT
            #expect(result == "SELECT * FROM users")
        }

        @Test("generateSelectAll works with any collection name", .tags(.utility, .fast))
        func testGenerateSelectAllAnyCollection() {
            // ACT & ASSERT
            #expect(DQLGenerator.generateSelectAll(collection: "cars") == "SELECT * FROM cars")
            #expect(DQLGenerator.generateSelectAll(collection: "orders") == "SELECT * FROM orders")
            #expect(DQLGenerator.generateSelectAll(collection: "my_collection") == "SELECT * FROM my_collection")
        }

        @Test("generateSelect with single field produces correct SQL", .tags(.utility, .fast))
        func testGenerateSelectSingleField() {
            // ARRANGE
            let collection = "users"
            let fields = ["name"]

            // ACT
            let result = DQLGenerator.generateSelect(collection: collection, fields: fields)

            // ASSERT
            #expect(result == "SELECT name FROM users")
        }

        @Test("generateSelect with multiple fields produces comma-separated list", .tags(.utility, .fast))
        func testGenerateSelectMultipleFields() {
            // ARRANGE
            let collection = "products"
            let fields = ["_id", "name", "price", "category"]

            // ACT
            let result = DQLGenerator.generateSelect(collection: collection, fields: fields)

            // ASSERT
            #expect(result == "SELECT _id, name, price, category FROM products")
        }

        @Test("generateSelect with two fields is correctly formatted", .tags(.utility, .fast))
        func testGenerateSelectTwoFields() {
            // ACT
            let result = DQLGenerator.generateSelect(collection: "items", fields: ["id", "status"])

            // ASSERT
            #expect(result == "SELECT id, status FROM items")
        }

        @Test("generateSelect contains FROM keyword", .tags(.utility, .fast))
        func testGenerateSelectContainsFrom() {
            // ACT
            let result = DQLGenerator.generateSelect(collection: "cars", fields: ["make", "model"])

            // ASSERT
            #expect(result.contains("FROM"))
            #expect(result.contains("cars"))
        }
    }

    // MARK: - INSERT Tests

    @Suite("INSERT Statements")
    struct InsertTests {

        @Test("generateInsert with single field produces correct INSERT", .tags(.utility, .fast))
        func testGenerateInsertSingleField() {
            // ACT
            let result = DQLGenerator.generateInsert(collection: "users", fields: ["name"])

            // ASSERT
            #expect(result.hasPrefix("INSERT INTO users DOCUMENTS ({"))
            #expect(result.contains("\"name\": \"<value>\""))
        }

        @Test("generateInsert with _id field uses document-id placeholder", .tags(.utility, .fast))
        func testGenerateInsertIdField() {
            // ACT
            let result = DQLGenerator.generateInsert(collection: "users", fields: ["_id", "name"])

            // ASSERT
            #expect(result.contains("\"_id\": \"<document-id>\""))
            #expect(result.contains("\"name\": \"<value>\""))
        }

        @Test("generateInsert with string type uses string placeholder", .tags(.utility, .fast))
        func testGenerateInsertStringType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["email": .string("")]

            // ACT
            let result = DQLGenerator.generateInsert(collection: "users", fields: ["email"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("\"email\": \"<value>\""))
        }

        @Test("generateInsert with number type uses numeric placeholder", .tags(.utility, .fast))
        func testGenerateInsertNumberType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["age": .number(0)]

            // ACT
            let result = DQLGenerator.generateInsert(collection: "users", fields: ["age"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("\"age\": 0"))
        }

        @Test("generateInsert with bool type uses true placeholder", .tags(.utility, .fast))
        func testGenerateInsertBoolType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["isActive": .bool(true)]

            // ACT
            let result = DQLGenerator.generateInsert(collection: "flags", fields: ["isActive"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("\"isActive\": true"))
        }

        @Test("generateInsert with null type uses null placeholder", .tags(.utility, .fast))
        func testGenerateInsertNullType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["deletedAt": .null]

            // ACT
            let result = DQLGenerator.generateInsert(collection: "records", fields: ["deletedAt"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("\"deletedAt\": null"))
        }

        @Test("generateInsert with nested type uses empty object placeholder", .tags(.utility, .fast))
        func testGenerateInsertNestedType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["metadata": .nested("{}")]

            // ACT
            let result = DQLGenerator.generateInsert(collection: "docs", fields: ["metadata"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("\"metadata\": {}"))
        }

        @Test("generateInsert without fieldTypes defaults all to string placeholder", .tags(.utility, .fast))
        func testGenerateInsertNoFieldTypes() {
            // ACT
            let result = DQLGenerator.generateInsert(collection: "items", fields: ["name", "desc"])

            // ASSERT — both fields should default to "<value>"
            #expect(result.contains("\"name\": \"<value>\""))
            #expect(result.contains("\"desc\": \"<value>\""))
        }

        @Test("generateInsert with multiple fields contains all fields", .tags(.utility, .fast))
        func testGenerateInsertMultipleFields() {
            // ACT
            let result = DQLGenerator.generateInsert(
                collection: "orders",
                fields: ["_id", "product", "quantity"],
                fieldTypes: ["quantity": .number(0)]
            )

            // ASSERT
            #expect(result.contains("\"_id\": \"<document-id>\""))
            #expect(result.contains("\"product\": \"<value>\""))
            #expect(result.contains("\"quantity\": 0"))
        }
    }

    // MARK: - UPDATE Tests

    @Suite("UPDATE Statements")
    struct UpdateTests {

        @Test("generateUpdate excludes _id from SET clause", .tags(.utility, .fast))
        func testGenerateUpdateExcludesId() {
            // ACT
            let result = DQLGenerator.generateUpdate(collection: "users", fields: ["_id", "name", "age"])

            // ASSERT — _id should only appear in WHERE clause, not in SET clause
            // Extract the SET portion (between "SET " and " WHERE")
            if let setRange = result.range(of: "SET "),
               let whereRange = result.range(of: " WHERE") {
                let setClause = String(result[setRange.upperBound ..< whereRange.lowerBound])
                #expect(!setClause.contains("_id"), "SET clause should not contain _id, got: \(setClause)")
            }
            // _id should appear in WHERE clause
            #expect(result.contains("WHERE _id = '<document-id>'"))
        }

        @Test("generateUpdate with string type uses quoted placeholder", .tags(.utility, .fast))
        func testGenerateUpdateStringType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["status": .string("")]

            // ACT
            let result = DQLGenerator.generateUpdate(collection: "users", fields: ["status"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("status = \"<value>\""))
        }

        @Test("generateUpdate with number type uses numeric placeholder", .tags(.utility, .fast))
        func testGenerateUpdateNumberType() {
            // ARRANGE
            let fieldTypes: [String: TableCellValue] = ["score": .number(0)]

            // ACT
            let result = DQLGenerator.generateUpdate(collection: "scores", fields: ["score"], fieldTypes: fieldTypes)

            // ASSERT
            #expect(result.contains("score = 0"))
        }

        @Test("generateUpdate produces correct UPDATE prefix", .tags(.utility, .fast))
        func testGenerateUpdatePrefix() {
            // ACT
            let result = DQLGenerator.generateUpdate(collection: "products", fields: ["name"])

            // ASSERT
            #expect(result.hasPrefix("UPDATE products SET"))
        }

        @Test("generateUpdate contains WHERE _id clause", .tags(.utility, .fast))
        func testGenerateUpdateWhereClause() {
            // ACT
            let result = DQLGenerator.generateUpdate(collection: "items", fields: ["name"])

            // ASSERT
            #expect(result.hasSuffix("WHERE _id = '<document-id>'"))
        }

        @Test("generateUpdate with only _id field produces SET with no real fields", .tags(.utility, .fast))
        func testGenerateUpdateOnlyIdField() {
            // ACT — only _id in fields; everything filtered out
            let result = DQLGenerator.generateUpdate(collection: "users", fields: ["_id"])

            // ASSERT — SET clause should be empty (comma-joined empty array)
            #expect(result.contains("UPDATE users SET"))
            #expect(result.contains("WHERE _id = '<document-id>'"))
        }

        @Test("generateUpdate with multiple non-id fields includes all", .tags(.utility, .fast))
        func testGenerateUpdateMultipleFields() {
            // ACT
            let result = DQLGenerator.generateUpdate(
                collection: "cars",
                fields: ["_id", "make", "model", "year"],
                fieldTypes: ["year": .number(0)]
            )

            // ASSERT
            #expect(result.contains("make = \"<value>\""))
            #expect(result.contains("model = \"<value>\""))
            #expect(result.contains("year = 0"))
            // _id should only be in WHERE clause, not SET clause
            if let setRange = result.range(of: "SET "),
               let whereRange = result.range(of: " WHERE") {
                let setClause = String(result[setRange.upperBound ..< whereRange.lowerBound])
                #expect(!setClause.contains("_id"), "SET clause should not contain _id, got: \(setClause)")
            }
        }
    }

    // MARK: - DELETE Tests

    @Suite("DELETE Statements")
    struct DeleteTests {

        @Test("generateDelete produces correct DELETE statement", .tags(.utility, .fast))
        func testGenerateDelete() {
            // ACT
            let result = DQLGenerator.generateDelete(collection: "users")

            // ASSERT
            #expect(result == "DELETE FROM users WHERE _id = '<document-id>'")
        }

        @Test("generateDelete works with any collection name", .tags(.utility, .fast))
        func testGenerateDeleteAnyCollection() {
            // ACT & ASSERT
            #expect(DQLGenerator.generateDelete(collection: "orders") == "DELETE FROM orders WHERE _id = '<document-id>'")
            #expect(DQLGenerator.generateDelete(collection: "my_cars") == "DELETE FROM my_cars WHERE _id = '<document-id>'")
        }

        @Test("generateDelete contains FROM keyword", .tags(.utility, .fast))
        func testGenerateDeleteContainsFrom() {
            // ACT
            let result = DQLGenerator.generateDelete(collection: "items")

            // ASSERT
            #expect(result.contains("FROM"))
            #expect(result.contains("WHERE"))
            #expect(result.contains("_id"))
        }

        @Test("generateDelete contains placeholder for document ID", .tags(.utility, .fast))
        func testGenerateDeleteContainsPlaceholder() {
            // ACT
            let result = DQLGenerator.generateDelete(collection: "products")

            // ASSERT
            #expect(result.contains("<document-id>"))
        }
    }

    // MARK: - EVICT Tests

    @Suite("EVICT Statements")
    struct EvictTests {

        @Test("generateEvict produces correct EVICT statement", .tags(.utility, .fast))
        func testGenerateEvict() {
            // ACT
            let result = DQLGenerator.generateEvict(collection: "users")

            // ASSERT
            #expect(result == "EVICT FROM users WHERE _id = '<document-id>'")
        }

        @Test("generateEvict works with any collection name", .tags(.utility, .fast))
        func testGenerateEvictAnyCollection() {
            // ACT & ASSERT
            #expect(DQLGenerator.generateEvict(collection: "cache") == "EVICT FROM cache WHERE _id = '<document-id>'")
            #expect(DQLGenerator.generateEvict(collection: "sessions") == "EVICT FROM sessions WHERE _id = '<document-id>'")
        }

        @Test("generateEvict starts with EVICT keyword", .tags(.utility, .fast))
        func testGenerateEvictStartsWithEvict() {
            // ACT
            let result = DQLGenerator.generateEvict(collection: "docs")

            // ASSERT
            #expect(result.hasPrefix("EVICT"))
        }

        @Test("generateEvict contains WHERE clause with document-id placeholder", .tags(.utility, .fast))
        func testGenerateEvictWhereClause() {
            // ACT
            let result = DQLGenerator.generateEvict(collection: "logs")

            // ASSERT
            #expect(result.contains("WHERE _id = '<document-id>'"))
        }
    }

    // MARK: - Edge Case Tests

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("SELECT with empty fields array produces SELECT  FROM collection", .tags(.utility, .fast))
        func testSelectEmptyFields() {
            // ACT
            let result = DQLGenerator.generateSelect(collection: "users", fields: [])

            // ASSERT — joined empty array is empty string
            #expect(result.contains("FROM users"))
            #expect(result.hasPrefix("SELECT"))
        }

        @Test("INSERT with empty fields array produces INSERT with empty document", .tags(.utility, .fast))
        func testInsertEmptyFields() {
            // ACT
            let result = DQLGenerator.generateInsert(collection: "items", fields: [])

            // ASSERT — placeholders string is empty
            #expect(result.contains("INSERT INTO items"))
            #expect(result.contains("DOCUMENTS"))
        }

        @Test("UPDATE with empty fields (minus _id) produces empty SET clause", .tags(.utility, .fast))
        func testUpdateEmptyFields() {
            // ACT
            let result = DQLGenerator.generateUpdate(collection: "records", fields: [])

            // ASSERT — SET clause has nothing to set
            #expect(result.contains("UPDATE records SET"))
            #expect(result.contains("WHERE _id"))
        }

        @Test("Collection name with underscore is preserved", .tags(.utility, .fast))
        func testCollectionNameWithUnderscore() {
            // ACT
            let selectResult = DQLGenerator.generateSelectAll(collection: "my_collection")
            let deleteResult = DQLGenerator.generateDelete(collection: "my_collection")
            let evictResult = DQLGenerator.generateEvict(collection: "my_collection")

            // ASSERT
            #expect(selectResult.contains("my_collection"))
            #expect(deleteResult.contains("my_collection"))
            #expect(evictResult.contains("my_collection"))
        }

        @Test("SELECT all differs from SELECT specific fields", .tags(.utility, .fast))
        func testSelectAllDiffersFromSpecific() {
            // ACT
            let allFields = DQLGenerator.generateSelectAll(collection: "users")
            let specificFields = DQLGenerator.generateSelect(collection: "users", fields: ["name"])

            // ASSERT
            #expect(allFields != specificFields)
            #expect(allFields.contains("*"))
            #expect(!specificFields.contains("*"))
        }

        @Test("Mixed field types in INSERT are handled correctly", .tags(.utility, .fast))
        func testInsertMixedTypes() {
            // ARRANGE
            let fields = ["_id", "name", "age", "isActive", "score", "metadata"]
            let fieldTypes: [String: TableCellValue] = [
                "name": .string(""),
                "age": .number(0),
                "isActive": .bool(false),
                "score": .number(0),
                "metadata": .nested("{}")
            ]

            // ACT
            let result = DQLGenerator.generateInsert(
                collection: "mixed",
                fields: fields,
                fieldTypes: fieldTypes
            )

            // ASSERT
            #expect(result.contains("\"_id\": \"<document-id>\""))
            #expect(result.contains("\"name\": \"<value>\""))
            #expect(result.contains("\"age\": 0"))
            #expect(result.contains("\"isActive\": true"))
            #expect(result.contains("\"score\": 0"))
            #expect(result.contains("\"metadata\": {}"))
        }

        @Test("DELETE and EVICT for same collection produce different SQL", .tags(.utility, .fast))
        func testDeleteVsEvict() {
            // ACT
            let deleteResult = DQLGenerator.generateDelete(collection: "users")
            let evictResult = DQLGenerator.generateEvict(collection: "users")

            // ASSERT
            #expect(deleteResult != evictResult)
            #expect(deleteResult.hasPrefix("DELETE"))
            #expect(evictResult.hasPrefix("EVICT"))
        }
    }
}
