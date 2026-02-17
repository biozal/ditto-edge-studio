import Foundation

/// Parsed table data ready for display
struct TableResultsData {
    let columns: [String]
    let rows: [TableResultRow]
    let isMutationResult: Bool // Flag to adjust UI if needed
}

/// Actor-based parser for converting JSON strings or mutation results into table data
actor TableResultsParser {
    static let shared = TableResultsParser()

    private init() {}

    /// Parse an array of result strings into table data
    /// - Parameter jsonStrings: Array of JSON strings or mutation result strings
    /// - Returns: Parsed table data with columns and rows
    func parseResults(_ jsonStrings: [String]) async -> TableResultsData {
        // Detect if these are mutation results or JSON results
        if isMutationResults(jsonStrings) {
            return parseMutationResults(jsonStrings)
        } else {
            return parseJsonResults(jsonStrings)
        }
    }

    // MARK: - Mutation Results

    /// Check if the strings are mutation results (Document ID / Commit ID format)
    private func isMutationResults(_ strings: [String]) -> Bool {
        guard !strings.isEmpty else { return false }

        // Check if strings match mutation format
        return strings.allSatisfy { string in
            string.hasPrefix("Document ID:") || string.hasPrefix("Commit ID:")
        }
    }

    /// Parse mutation results (INSERT/UPDATE/DELETE responses)
    /// Format: ["Document ID: [id]", "Commit ID: [id]"]
    private func parseMutationResults(_ strings: [String]) -> TableResultsData {
        let columns = ["Type", "Value"]

        let rows = strings.enumerated().map { index, string in
            var type = ""
            var value = ""

            if string.hasPrefix("Document ID:") {
                type = "Document ID"
                value = string.replacingOccurrences(of: "Document ID:", with: "").trimmingCharacters(in: .whitespaces)
            } else if string.hasPrefix("Commit ID:") {
                type = "Commit ID"
                value = string.replacingOccurrences(of: "Commit ID:", with: "").trimmingCharacters(in: .whitespaces)
            }

            let cells: [String: TableCellValue] = [
                "Type": .string(type),
                "Value": .string(value)
            ]

            return TableResultRow(
                rowIndex: index,
                originalJson: string,
                cells: cells
            )
        }

        return TableResultsData(columns: columns, rows: rows, isMutationResult: true)
    }

    // MARK: - JSON Results

    /// Parse JSON results (SELECT query responses)
    private func parseJsonResults(_ strings: [String]) -> TableResultsData {
        var allKeys = Set<String>()
        var rows: [TableResultRow] = []

        // First pass: extract all unique keys
        for (index, jsonString) in strings.enumerated() {
            guard let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    allKeys.formUnion(jsonObject.keys)

                    // Create row
                    let cells = parseCells(from: jsonObject)
                    let row = TableResultRow(
                        rowIndex: index,
                        originalJson: jsonString,
                        cells: cells
                    )
                    rows.append(row)
                }
            } catch {
                // Skip malformed JSON silently
                Log.warning("Skipping malformed JSON at index \(index): \(error.localizedDescription)")
                continue
            }
        }

        // Sort columns: _id first, then alphabetically
        let sortedColumns = sortColumns(Array(allKeys))

        return TableResultsData(
            columns: sortedColumns,
            rows: rows,
            isMutationResult: false
        )
    }

    /// Parse cells from a JSON object
    private func parseCells(from jsonObject: [String: Any]) -> [String: TableCellValue] {
        var cells: [String: TableCellValue] = [:]

        for (key, value) in jsonObject {
            cells[key] = parseValue(value)
        }

        return cells
    }

    /// Parse a JSON value into a TableCellValue
    private func parseValue(_ value: Any) -> TableCellValue {
        // Check for null
        if value is NSNull {
            return .null
        }

        // Check for boolean (must be done before NSNumber check)
        if let boolValue = value as? Bool {
            return .bool(boolValue)
        }

        // Check for number
        if let numberValue = value as? NSNumber {
            return .number(numberValue.doubleValue)
        }

        // Check for string
        if let stringValue = value as? String {
            return .string(stringValue)
        }

        // Check for array or dictionary (nested data)
        if let arrayValue = value as? [Any] {
            return .nested(convertToJsonString(arrayValue))
        }

        if let dictValue = value as? [String: Any] {
            return .nested(convertToJsonString(dictValue))
        }

        // Fallback: convert to string
        return .string(String(describing: value))
    }

    /// Convert a nested value (array or dict) to a JSON string
    private func convertToJsonString(_ value: Any) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            // Fallback to description
            return String(describing: value)
        }
        return String(describing: value)
    }

    /// Sort columns: _id first, then alphabetically
    private func sortColumns(_ columns: [String]) -> [String] {
        var sorted = columns.sorted()

        // Move _id to the front if it exists
        if let idIndex = sorted.firstIndex(of: "_id") {
            sorted.remove(at: idIndex)
            sorted.insert("_id", at: 0)
        }

        return sorted
    }
}
