//
//  DQLQueryParser.swift
//  Edge Studio
//
//  Created by Claude Code on 10/18/25.
//

import Foundation

/// Utility for parsing Ditto Query Language (DQL) queries
struct DQLQueryParser {

    /// Extracts the collection name from a DQL query
    /// - Parameter query: The DQL query string
    /// - Returns: The collection name if found, nil otherwise
    ///
    /// Supports various DQL query formats:
    /// - `SELECT * FROM COLLECTION collection_name` → "collection_name"
    /// - `SELECT * FROM collection_name` → "collection_name"
    /// - `DELETE FROM COLLECTION collection_name` → "collection_name"
    /// - `UPDATE COLLECTION collection_name` → "collection_name"
    static func extractCollectionName(from query: String) -> String? {
        // Pattern handles both "FROM COLLECTION name" and "FROM name"
        // (?:COLLECTION\s+)? is a non-capturing optional group for the COLLECTION keyword
        let pattern = #"FROM\s+(?:COLLECTION\s+)?(\w+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else {
            return nil
        }

        return String(query[range])
    }

    /// Determines if a query is an aggregate query that doesn't benefit from server-side pagination
    /// - Parameter query: The DQL query string
    /// - Returns: True if the query uses aggregate functions, GROUP BY, or already has LIMIT/OFFSET
    ///
    /// Examples of aggregate queries:
    /// - `SELECT COUNT(*) FROM cars` → true
    /// - `SELECT AVG(price) FROM cars` → true
    /// - `SELECT make, COUNT(*) FROM cars GROUP BY make` → true
    /// - `SELECT * FROM cars LIMIT 10` → true (already paginated)
    /// - `SELECT make FROM cars` → false (can benefit from pagination)
    static func isAggregateOrPaginatedQuery(_ query: String) -> Bool {
        let upperQuery = query.uppercased()

        // Check if query already has LIMIT or OFFSET
        if upperQuery.contains("LIMIT") || upperQuery.contains("OFFSET") {
            return true
        }

        // Check for aggregate functions: COUNT, SUM, AVG, MIN, MAX
        let aggregateFunctions = ["COUNT(", "SUM(", "AVG(", "MIN(", "MAX("]
        for function in aggregateFunctions {
            if upperQuery.contains(function) {
                return true
            }
        }

        // Check for GROUP BY clause
        if upperQuery.contains("GROUP BY") {
            return true
        }

        // Check for DISTINCT (often returns smaller result sets)
        if upperQuery.contains("SELECT DISTINCT") {
            return true
        }

        return false
    }

    /// Checks if the query already has pagination clauses
    /// - Parameter query: The DQL query string
    /// - Returns: True if the query contains LIMIT or OFFSET
    static func hasPagination(_ query: String) -> Bool {
        let upperQuery = query.uppercased()
        return upperQuery.contains("LIMIT") || upperQuery.contains("OFFSET")
    }
}
