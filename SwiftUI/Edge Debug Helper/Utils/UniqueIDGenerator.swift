//
//  UniqueIDGenerator.swift
//  Edge Studio
//

import Foundation

/// Utility for generating namespaced unique identifiers for tabs, queries, history, and favorites
enum UniqueIDGenerator {

    enum Namespace: String {
        case query = "query-"
        case history = "history-"
        case favorites = "favorites-"
    }

    /// Generate a new unique ID with the specified namespace
    /// - Parameter namespace: The namespace prefix to use
    /// - Returns: A string in the format "namespace-uuid"
    static func generate(namespace: Namespace) -> String {
        return namespace.rawValue + UUID().uuidString
    }

    /// Generate a query ID (e.g., "query-{uuid}")
    static func generateQueryID() -> String {
        return generate(namespace: .query)
    }

    /// Generate a history ID (e.g., "history-{uuid}")
    static func generateHistoryID() -> String {
        return generate(namespace: .history)
    }

    /// Generate a favorites ID (e.g., "favorites-{uuid}")
    static func generateFavoritesID() -> String {
        return generate(namespace: .favorites)
    }

    /// Extract the namespace from a unique ID
    /// - Parameter id: The unique ID string
    /// - Returns: The namespace if found, nil otherwise
    static func extractNamespace(from id: String) -> Namespace? {
        for namespace in [Namespace.query, .history, .favorites] {
            if id.hasPrefix(namespace.rawValue) {
                return namespace
            }
        }
        return nil
    }

    /// Check if an ID has a specific namespace
    /// - Parameters:
    ///   - id: The unique ID string
    ///   - namespace: The namespace to check for
    /// - Returns: True if the ID has the specified namespace
    static func hasNamespace(_ id: String, namespace: Namespace) -> Bool {
        return id.hasPrefix(namespace.rawValue)
    }

    /// Extract the UUID portion from a namespaced ID
    /// - Parameter id: The namespaced ID string
    /// - Returns: The UUID portion, or nil if not properly formatted
    static func extractUUID(from id: String) -> String? {
        guard let namespace = extractNamespace(from: id) else {
            return nil
        }
        return String(id.dropFirst(namespace.rawValue.count))
    }
}
