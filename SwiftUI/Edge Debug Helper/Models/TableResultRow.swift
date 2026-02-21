import Foundation

/// Represents a single row in the table view
struct TableResultRow: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let originalJson: String // For copying entire row
    let cells: [String: TableCellValue]
}

/// Represents different types of values that can appear in table cells
enum TableCellValue {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case nested(String) // Objects/arrays rendered as JSON strings

    /// Get the display string for this cell value
    var displayValue: String {
        switch self {
        case let .string(s):
            return s
        case let .number(n):
            // Format numbers cleanly (remove trailing zeros)
            return String(format: "%g", n)
        case let .bool(b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case let .nested(json):
            return json
        }
    }

    /// Check if this is a nested value (object or array)
    var isNested: Bool {
        if case .nested = self {
            return true
        }
        return false
    }
}
