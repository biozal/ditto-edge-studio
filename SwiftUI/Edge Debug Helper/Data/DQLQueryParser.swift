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
}
