//
//  TableResultsParserTests.swift
//  Edge Debug Helper Tests
//
//  Created by Claude Code
//  Unit tests for TableResultsParser using Swift Testing
//

import Testing
@testable import Edge_Debug_Helper

@Suite("TableResultsParser Tests")
struct TableResultsParserTests {
    let parser = TableResultsParser.shared

    // MARK: - Mutation Results Tests

    @Test("Parse mutation results with Document IDs and Commit ID")
    func parseMutationResults() async {
        let input = [
            "Document ID: 621ff30d2a3e781873fcb65c",
            "Document ID: 621ff30d2a3e781873fcb65d",
            "Commit ID: abc123def456"
        ]

        let result = await parser.parseResults(input)

        #expect(result.isMutationResult)
        #expect(result.columns == ["Type", "Value"])
        #expect(result.rows.count == 3)

        // Verify first row
        #expect(result.rows[0].cells["Type"]?.displayValue == "Document ID")
        #expect(result.rows[0].cells["Value"]?.displayValue == "621ff30d2a3e781873fcb65c")
        #expect(result.rows[0].originalJson == "Document ID: 621ff30d2a3e781873fcb65c")

        // Verify last row (Commit ID)
        #expect(result.rows[2].cells["Type"]?.displayValue == "Commit ID")
        #expect(result.rows[2].cells["Value"]?.displayValue == "abc123def456")
    }

    @Test("Parse mutation results with extra spaces")
    func parseMutationResultsWithExtraSpaces() async {
        let input = [
            "Document ID:   621ff30d2a3e781873fcb65c   "
        ]

        let result = await parser.parseResults(input)

        #expect(result.isMutationResult)
        #expect(result.rows[0].cells["Value"]?.displayValue == "621ff30d2a3e781873fcb65c")
    }

    // MARK: - JSON Results Tests

    @Test("Parse single JSON document")
    func parseSingleJsonDocument() async {
        let input = [
            "{\"_id\": \"1\", \"name\": \"John\", \"age\": 30}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(result.columns == ["_id", "age", "name"]) // _id first, then alphabetical
        #expect(result.rows.count == 1)

        let row = result.rows[0]
        #expect(row.cells["_id"]?.displayValue == "1")
        #expect(row.cells["name"]?.displayValue == "John")
        #expect(row.cells["age"]?.displayValue == "30")
    }

    @Test("Parse multiple documents with varying schemas")
    func parseMultipleDocumentsWithVaryingSchemas() async {
        let input = [
            "{\"_id\": \"1\", \"name\": \"John\", \"age\": 30}",
            "{\"_id\": \"2\", \"name\": \"Jane\", \"city\": \"NYC\"}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(Set(result.columns) == Set(["_id", "name", "age", "city"]))
        #expect(result.rows.count == 2)

        // First row should have age but no city
        #expect(result.rows[0].cells["age"] != nil)
        #expect(result.rows[0].cells["city"] == nil)

        // Second row should have city but no age
        #expect(result.rows[1].cells["city"] != nil)
        #expect(result.rows[1].cells["age"] == nil)
    }

    @Test("Handle nested objects")
    func handleNestedObjects() async {
        let input = [
            "{\"_id\": \"1\", \"user\": {\"name\": \"John\", \"age\": 30}}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(result.columns == ["_id", "user"])

        let userCell = result.rows[0].cells["user"]
        #expect(userCell != nil)
        #expect(userCell?.isNested == true)

        // Should contain JSON representation
        let displayValue = userCell?.displayValue ?? ""
        #expect(displayValue.contains("name"))
        #expect(displayValue.contains("John"))
    }

    @Test("Handle nested arrays")
    func handleNestedArrays() async {
        let input = [
            "{\"_id\": \"1\", \"tags\": [\"swift\", \"ios\", \"macos\"]}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(result.columns == ["_id", "tags"])

        let tagsCell = result.rows[0].cells["tags"]
        #expect(tagsCell != nil)
        #expect(tagsCell?.isNested == true)

        let displayValue = tagsCell?.displayValue ?? ""
        #expect(displayValue.contains("swift"))
        #expect(displayValue.contains("ios"))
    }

    @Test("Handle different data types")
    func handleDifferentDataTypes() async {
        let input = [
            "{\"_id\": \"1\", \"name\": \"John\", \"age\": 30, \"active\": true, \"score\": 95.5, \"metadata\": null}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        let row = result.rows[0]

        // String
        if case .string(let value) = row.cells["name"] {
            #expect(value == "John")
        } else {
            Issue.record("Expected string type for name")
        }

        // Number (integer)
        if case .number(let value) = row.cells["age"] {
            #expect(value == 30)
        } else {
            Issue.record("Expected number type for age")
        }

        // Boolean
        if case .bool(let value) = row.cells["active"] {
            #expect(value == true)
        } else {
            Issue.record("Expected bool type for active")
        }

        // Number (decimal)
        if case .number(let value) = row.cells["score"] {
            #expect(value == 95.5)
        } else {
            Issue.record("Expected number type for score")
        }

        // Null
        if case .null = row.cells["metadata"] {
            // Success
        } else {
            Issue.record("Expected null type for metadata")
        }
    }

    @Test("Handle malformed JSON")
    func handleMalformedJson() async {
        let input = [
            "{\"_id\": \"1\", \"name\": \"John\"}",
            "{invalid json}",
            "{\"_id\": \"2\", \"name\": \"Jane\"}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        // Should skip the malformed JSON
        #expect(result.rows.count == 2)
        #expect(result.rows[0].cells["_id"]?.displayValue == "1")
        #expect(result.rows[1].cells["_id"]?.displayValue == "2")
    }

    @Test("Handle empty results")
    func handleEmptyResults() async {
        let input: [String] = []

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(result.columns.count == 0)
        #expect(result.rows.count == 0)
    }

    @Test("Column sorting with _id first")
    func columnSorting() async {
        let input = [
            "{\"_id\": \"1\", \"zebra\": \"z\", \"apple\": \"a\", \"banana\": \"b\"}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        // _id should be first, then alphabetical
        #expect(result.columns == ["_id", "apple", "banana", "zebra"])
    }

    @Test("Column sorting without _id")
    func columnSortingWithoutId() async {
        let input = [
            "{\"zebra\": \"z\", \"apple\": \"a\", \"banana\": \"b\"}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        // Just alphabetical without _id
        #expect(result.columns == ["apple", "banana", "zebra"])
    }

    @Test("Handle missing fields")
    func missingFields() async {
        let input = [
            "{\"_id\": \"1\", \"name\": \"John\", \"age\": 30}",
            "{\"_id\": \"2\", \"name\": \"Jane\"}",
            "{\"_id\": \"3\", \"age\": 25}"
        ]

        let result = await parser.parseResults(input)

        #expect(!result.isMutationResult)
        #expect(result.rows.count == 3)

        // First row has all fields
        #expect(result.rows[0].cells["name"] != nil)
        #expect(result.rows[0].cells["age"] != nil)

        // Second row missing age
        #expect(result.rows[1].cells["name"] != nil)
        #expect(result.rows[1].cells["age"] == nil)

        // Third row missing name
        #expect(result.rows[2].cells["name"] == nil)
        #expect(result.rows[2].cells["age"] != nil)
    }

    @Test("Original JSON preserved")
    func originalJsonPreserved() async {
        let originalJson = "{\"_id\": \"1\", \"name\": \"John\"}"
        let input = [originalJson]

        let result = await parser.parseResults(input)

        #expect(result.rows[0].originalJson == originalJson)
    }

    @Test("Detect mutation vs JSON correctly")
    func detectMutationVsJsonCorrectly() async {
        // JSON results should not be detected as mutation
        let jsonInput = ["{\"_id\": \"1\"}"]
        let jsonResult = await parser.parseResults(jsonInput)
        #expect(!jsonResult.isMutationResult)

        // Mutation results should be detected
        let mutationInput = ["Document ID: 123"]
        let mutationResult = await parser.parseResults(mutationInput)
        #expect(mutationResult.isMutationResult)
    }
}
