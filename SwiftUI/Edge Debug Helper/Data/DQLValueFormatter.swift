//
//  DQLValueFormatter.swift
//  Edge Debug Helper
//
//  Formats JSON values into DQL-compatible literals with proper type classification.
//

import Foundation

enum DQLValueFormatter {

    /// Formats any JSON value into a DQL-compatible literal string
    static func formatValue(_ value: Any) throws -> String {
        // Handle null first
        if value is NSNull {
            return "NULL"
        }

        // Check for special MongoDB types (must check before standard object handling)
        if let dict = value as? [String: Any] {
            // Only convert $date, not $oid - let $oid be stored as-is
            if let dateValue = extractMongoDBDate(from: dict) {
                return formatDate(dateValue)
            }
            // Treat as regular object (including $oid objects)
            return try formatObject(dict)
        }

        // Handle strings
        if let stringValue = value as? String {
            return formatString(stringValue)
        }

        // Handle arrays
        if let arrayValue = value as? [Any] {
            return try formatArray(arrayValue)
        }

        // Handle boolean BEFORE NSNumber (Bool is subclass of NSNumber in Swift/ObjC bridge)
        // Swift's type(of:) can distinguish true Bool from NSNumber
        if type(of: value) == type(of: true) {
            if let boolValue = value as? Bool {
                return formatBoolean(boolValue)
            }
        }

        // Handle numbers (after boolean check using type comparison)
        if let numberValue = value as? NSNumber {
            return formatNumber(numberValue)
        }

        throw DQLFormattingError.unsupportedType("Unsupported value type: \(type(of: value))")
    }

    // MARK: - Type-Specific Formatters

    /// Formats a string value with proper escaping
    static func formatString(_ value: String) -> String {
        // Escape single quotes by doubling them
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    /// Formats a boolean value
    static func formatBoolean(_ value: Bool) -> String {
        return value ? "true" : "false"
    }

    /// Formats a number value (int or double)
    static func formatNumber(_ value: NSNumber) -> String {
        // Just format as number - boolean detection is handled in formatValue()
        // using type comparison before this method is called
        return "\(value)"
    }

    /// Formats a date value (ISO 8601 string)
    static func formatDate(_ value: String) -> String {
        // DQL expects ISO 8601 date strings in single quotes
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    /// Formats an array value
    static func formatArray(_ value: [Any]) throws -> String {
        let elements = try value.map { element -> String in
            return try formatValue(element)
        }
        return "[\(elements.joined(separator: ", "))]"
    }

    /// Formats an object/dictionary value
    static func formatObject(_ value: [String: Any]) throws -> String {
        let pairs = try value.map { (key, val) -> String in
            let formattedValue = try formatValue(val)
            return "\(key): \(formattedValue)"
        }
        return "{\(pairs.joined(separator: ", "))}"
    }

    // MARK: - Special Type Handlers

    /// Extracts date string from MongoDB $date format
    /// Handles formats like: {"$date": "2009-04-01T00:00:00.000-0700"}
    static func extractMongoDBDate(from dict: [String: Any]) -> String? {
        // Check for MongoDB extended JSON date format
        if dict.count == 1, let dateValue = dict["$date"] as? String {
            return dateValue
        }
        return nil
    }

    /// Extracts ObjectId string from MongoDB $oid format
    /// Handles formats like: {"$oid": "50b59cd75bed76f46522c34e"}
    static func extractMongoDBObjectId(from dict: [String: Any]) -> String? {
        // Check for MongoDB extended JSON ObjectId format
        if dict.count == 1, let oidValue = dict["$oid"] as? String {
            return oidValue
        }
        return nil
    }

    /// Classifies the type of a value for debugging
    static func classifyType(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let dict = value as? [String: Any] {
            if extractMongoDBDate(from: dict) != nil {
                return "date"
            }
            return "object"
        }
        if value is Bool {
            return "boolean"
        }
        if let number = value as? NSNumber {
            let objCType = String(cString: number.objCType)
            if objCType == "c" || objCType == "B" {
                return "boolean"
            }
            return "number"
        }
        if value is String {
            return "string"
        }
        if value is [Any] {
            return "array"
        }
        return "unknown"
    }
}

// MARK: - Error Types

enum DQLFormattingError: LocalizedError {
    case unsupportedType(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let message),
             .invalidFormat(let message):
            return message
        }
    }
}
