//
//  DQLQueryParserTests.swift
//  Edge Debug Helper Tests
//

//  IMPORTANT: This test file must be added to the "Edge Debug Helper Tests" target in Xcode.
//
//  To add this file to the test target:
//  1. Open Edge Debug Helper.xcodeproj in Xcode
//  2. Select this file in the Project Navigator
//  3. In the File Inspector (right sidebar), check "Edge Debug Helper Tests" under Target Membership
//  4. Uncheck "Edge Debug Helper" if it's checked
//  5. Build and run tests with Cmd+U
//

import Testing
@testable import Edge_Debug_Helper

struct DQLQueryParserTests {

    // MARK: - Collection Name Extraction Tests

    @Test("Extract collection name from basic SELECT query")
    func testExtractCollectionNameBasicSelect() async throws {
        let query = "SELECT * FROM cars"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == "cars")
    }

    @Test("Extract collection name with COLLECTION keyword")
    func testExtractCollectionNameWithKeyword() async throws {
        let query = "SELECT * FROM COLLECTION cars"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == "cars")
    }

    @Test("Extract collection name from DELETE query")
    func testExtractCollectionNameDelete() async throws {
        let query = "DELETE FROM COLLECTION users WHERE age > 30"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == "users")
    }

    @Test("Extract collection name from UPDATE query")
    func testExtractCollectionNameUpdate() async throws {
        let query = "UPDATE COLLECTION products SET price = 10"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == "products")
    }

    @Test("Extract collection name with mixed case")
    func testExtractCollectionNameMixedCase() async throws {
        let query = "select * from MyCollection where id = 1"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == "MyCollection")
    }

    @Test("Return nil for query without FROM clause")
    func testExtractCollectionNameNoFrom() async throws {
        let query = "SHOW TABLES"
        let result = DQLQueryParser.extractCollectionName(from: query)
        #expect(result == nil)
    }

    // MARK: - Aggregate Query Detection Tests

    @Test("Detect COUNT aggregate function")
    func testIsAggregateQueryCount() async throws {
        let query = "SELECT COUNT(*) FROM cars"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect COUNT with field aggregate")
    func testIsAggregateQueryCountField() async throws {
        let query = "SELECT COUNT(id) FROM users"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect AVG aggregate function")
    func testIsAggregateQueryAvg() async throws {
        let query = "SELECT AVG(price) FROM products"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect SUM aggregate function")
    func testIsAggregateQuerySum() async throws {
        let query = "SELECT SUM(quantity) FROM orders"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect MIN aggregate function")
    func testIsAggregateQueryMin() async throws {
        let query = "SELECT MIN(age) FROM users"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect MAX aggregate function")
    func testIsAggregateQueryMax() async throws {
        let query = "SELECT MAX(salary) FROM employees"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect GROUP BY clause")
    func testIsAggregateQueryGroupBy() async throws {
        let query = "SELECT make, COUNT(*) FROM cars GROUP BY make"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect DISTINCT keyword")
    func testIsAggregateQueryDistinct() async throws {
        let query = "SELECT DISTINCT category FROM products"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect query with LIMIT")
    func testIsAggregateQueryWithLimit() async throws {
        let query = "SELECT * FROM cars LIMIT 10"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect query with OFFSET")
    func testIsAggregateQueryWithOffset() async throws {
        let query = "SELECT * FROM cars OFFSET 50"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Detect query with LIMIT and OFFSET")
    func testIsAggregateQueryWithLimitAndOffset() async throws {
        let query = "SELECT * FROM cars LIMIT 10 OFFSET 20"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Non-aggregate simple SELECT query")
    func testIsNotAggregateSimpleSelect() async throws {
        let query = "SELECT make FROM cars"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Non-aggregate SELECT with WHERE clause")
    func testIsNotAggregateSelectWithWhere() async throws {
        let query = "SELECT * FROM cars WHERE make = 'Toyota'"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Non-aggregate SELECT with JOIN")
    func testIsNotAggregateSelectWithJoin() async throws {
        let query = "SELECT cars.make, owners.name FROM cars JOIN owners ON cars.owner_id = owners.id"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Non-aggregate SELECT with ORDER BY")
    func testIsNotAggregateSelectWithOrderBy() async throws {
        let query = "SELECT * FROM cars ORDER BY price DESC"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Case insensitive aggregate detection")
    func testIsAggregateCaseInsensitive() async throws {
        let query = "select count(*) from cars"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Mixed case GROUP BY detection")
    func testIsAggregateGroupByMixedCase() async throws {
        let query = "SELECT make FROM cars Group By make"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    // MARK: - Pagination Detection Tests

    @Test("Has pagination - LIMIT only")
    func testHasPaginationLimit() async throws {
        let query = "SELECT * FROM cars LIMIT 100"
        let result = DQLQueryParser.hasPagination(query)
        #expect(result == true)
    }

    @Test("Has pagination - OFFSET only")
    func testHasPaginationOffset() async throws {
        let query = "SELECT * FROM cars OFFSET 50"
        let result = DQLQueryParser.hasPagination(query)
        #expect(result == true)
    }

    @Test("Has pagination - LIMIT and OFFSET")
    func testHasPaginationBoth() async throws {
        let query = "SELECT * FROM cars LIMIT 100 OFFSET 200"
        let result = DQLQueryParser.hasPagination(query)
        #expect(result == true)
    }

    @Test("No pagination")
    func testHasNoPagination() async throws {
        let query = "SELECT * FROM cars WHERE make = 'Honda'"
        let result = DQLQueryParser.hasPagination(query)
        #expect(result == false)
    }

    @Test("Has pagination - case insensitive")
    func testHasPaginationCaseInsensitive() async throws {
        let query = "select * from cars limit 10"
        let result = DQLQueryParser.hasPagination(query)
        #expect(result == true)
    }

    // MARK: - Edge Cases and Complex Queries

    @Test("Complex query with subquery containing COUNT")
    func testComplexQueryWithSubqueryCount() async throws {
        let query = "SELECT * FROM (SELECT COUNT(*) as total FROM cars)"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Query with COUNT in field name should not be aggregate")
    func testCountInFieldName() async throws {
        // This is a tricky case - "counter" field shouldn't trigger aggregate detection
        let query = "SELECT counter FROM stats"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Multiple aggregates in one query")
    func testMultipleAggregates() async throws {
        let query = "SELECT COUNT(*), AVG(price), MAX(year) FROM cars"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    @Test("Empty query string")
    func testEmptyQuery() async throws {
        let query = ""
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Whitespace only query")
    func testWhitespaceQuery() async throws {
        let query = "   \n\t  "
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false)
    }

    @Test("Query with LIMIT in comment should still be detected")
    func testLimitInString() async throws {
        // If LIMIT appears anywhere in the query string, it's detected
        let query = "SELECT description FROM rules WHERE text LIKE '%LIMIT%'"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true)
    }

    // MARK: - Real-World Query Examples

    @Test("Real-world: Simple car inventory query")
    func testRealWorldCarInventory() async throws {
        let query = "SELECT make, model, year FROM cars WHERE year > 2020"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false) // Should use pagination for large results
    }

    @Test("Real-world: Count by category")
    func testRealWorldCountByCategory() async throws {
        let query = "SELECT category, COUNT(*) as total FROM products GROUP BY category"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true) // Already returns small result set
    }

    @Test("Real-world: Average price calculation")
    func testRealWorldAveragePrice() async throws {
        let query = "SELECT AVG(price) as avg_price FROM products WHERE category = 'electronics'"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == true) // Single result, no pagination needed
    }

    @Test("Real-world: User list query")
    func testRealWorldUserList() async throws {
        let query = "SELECT email, name, created_at FROM users WHERE active = true"
        let result = DQLQueryParser.isAggregateOrPaginatedQuery(query)
        #expect(result == false) // Could return many results, pagination beneficial
    }
}
