//
//  DQLValueFormatterTests.swift
//  Edge Debug Helper Tests
//
//  Unit tests for DQL value formatting and type classification.
//
//  IMPORTANT: This file should be added to the test target manually in Xcode:
//  1. Open Xcode project
//  2. Select this file in Project Navigator
//  3. Open File Inspector (right sidebar)
//  4. Check "Edge Debug Helper Tests" under Target Membership
//

import Testing
import Foundation

@testable import Edge_Debug_Helper

struct DQLValueFormatterTests {

    // MARK: - String Formatting Tests

    @Test func formatSimpleString() throws {
        let result = try DQLValueFormatter.formatString("hello")
        #expect(result == "'hello'")
    }

    @Test func formatStringWithSingleQuote() throws {
        let result = try DQLValueFormatter.formatString("it's working")
        #expect(result == "'it''s working'")
    }

    @Test func formatStringWithMultipleQuotes() throws {
        let result = try DQLValueFormatter.formatString("'quoted' text 'here'")
        #expect(result == "'''quoted'' text ''here'''")
    }

    @Test func formatEmptyString() throws {
        let result = try DQLValueFormatter.formatString("")
        #expect(result == "''")
    }

    @Test func formatStringWithSpecialCharacters() throws {
        let result = try DQLValueFormatter.formatString("hello\nworld\ttab")
        #expect(result == "'hello\nworld\ttab'")
    }

    // MARK: - Boolean Formatting Tests

    @Test func formatBooleanTrue() throws {
        let result = DQLValueFormatter.formatBoolean(true)
        #expect(result == "true")
    }

    @Test func formatBooleanFalse() throws {
        let result = DQLValueFormatter.formatBoolean(false)
        #expect(result == "false")
    }

    // MARK: - Number Formatting Tests

    @Test func formatInteger() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: 42))
        #expect(result == "42")
    }

    @Test func formatNegativeInteger() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: -100))
        #expect(result == "-100")
    }

    @Test func formatZero() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: 0))
        #expect(result == "0")
    }

    @Test func formatDouble() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: 3.14159))
        #expect(result == "3.14159")
    }

    @Test func formatNegativeDouble() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: -99.99))
        #expect(result == "-99.99")
    }

    @Test func formatLargeNumber() throws {
        let result = DQLValueFormatter.formatNumber(NSNumber(value: 1_000_000))
        #expect(result == "1000000")
    }

    // MARK: - Null Formatting Tests

    @Test func formatNullValue() throws {
        let result = try DQLValueFormatter.formatValue(NSNull())
        #expect(result == "NULL")
    }

    // MARK: - Array Formatting Tests

    @Test func formatEmptyArray() throws {
        let result = try DQLValueFormatter.formatArray([])
        #expect(result == "[]")
    }

    @Test func formatArrayOfStrings() throws {
        let result = try DQLValueFormatter.formatArray(["apple", "banana", "cherry"])
        #expect(result == "['apple', 'banana', 'cherry']")
    }

    @Test func formatArrayOfNumbers() throws {
        let result = try DQLValueFormatter.formatArray([1, 2, 3, 4, 5])
        #expect(result == "[1, 2, 3, 4, 5]")
    }

    @Test func formatArrayOfBooleans() throws {
        let result = try DQLValueFormatter.formatArray([true, false, true])
        #expect(result == "[true, false, true]")
    }

    @Test func formatMixedArray() throws {
        let mixed: [Any] = ["text", 42, true, NSNull()]
        let result = try DQLValueFormatter.formatArray(mixed)
        #expect(result == "['text', 42, true, NULL]")
    }

    @Test func formatNestedArray() throws {
        let nested: [Any] = [1, [2, 3], 4]
        let result = try DQLValueFormatter.formatArray(nested)
        #expect(result == "[1, [2, 3], 4]")
    }

    // MARK: - Object Formatting Tests

    @Test func formatEmptyObject() throws {
        let result = try DQLValueFormatter.formatObject([:])
        #expect(result == "{}")
    }

    @Test func formatSimpleObject() throws {
        let obj: [String: Any] = ["name": "Alice", "age": 30]
        let result = try DQLValueFormatter.formatObject(obj)

        // Since dictionary order is not guaranteed, check both possible orders
        let valid1 = "{name: 'Alice', age: 30}"
        let valid2 = "{age: 30, name: 'Alice'}"
        #expect(result == valid1 || result == valid2)
    }

    @Test func formatObjectWithMixedTypes() throws {
        let obj: [String: Any] = [
            "name": "Bob",
            "age": 25,
            "active": true,
            "score": 99.5,
            "notes": NSNull()
        ]
        let result = try DQLValueFormatter.formatObject(obj)

        // Check that result contains all expected key-value pairs
        #expect(result.contains("name: 'Bob'"))
        #expect(result.contains("age: 25"))
        #expect(result.contains("active: true"))
        #expect(result.contains("score: 99.5"))
        #expect(result.contains("notes: NULL"))
    }

    @Test func formatNestedObject() throws {
        let obj: [String: Any] = [
            "user": ["name": "Charlie", "age": 35],
            "active": true
        ]
        let result = try DQLValueFormatter.formatObject(obj)

        // Check for nested structure
        #expect(result.contains("user: {"))
        #expect(result.contains("name: 'Charlie'"))
        #expect(result.contains("age: 35"))
        #expect(result.contains("active: true"))
    }

    // MARK: - MongoDB Date Tests

    @Test func extractMongoDBDateFormat() throws {
        let dateDict: [String: Any] = ["$date": "2009-04-01T00:00:00.000-0700"]
        let result = DQLValueFormatter.extractMongoDBDate(from: dateDict)
        #expect(result == "2009-04-01T00:00:00.000-0700")
    }

    @Test func extractMongoDBDateReturnsNilForRegularObject() throws {
        let regularDict: [String: Any] = ["date": "2009-04-01", "name": "test"]
        let result = DQLValueFormatter.extractMongoDBDate(from: regularDict)
        #expect(result == nil)
    }

    @Test func formatMongoDBDate() throws {
        let dateDict: [String: Any] = ["$date": "2009-04-01T00:00:00.000-0700"]
        let result = try DQLValueFormatter.formatValue(dateDict)
        #expect(result == "'2009-04-01T00:00:00.000-0700'")
    }

    @Test func formatMongoDBDateWithTimezone() throws {
        let dateDict: [String: Any] = ["$date": "2024-01-15T14:30:00.000Z"]
        let result = try DQLValueFormatter.formatValue(dateDict)
        #expect(result == "'2024-01-15T14:30:00.000Z'")
    }

    @Test func formatMongoDBObjectIdAsObject() throws {
        // MongoDB $oid should be stored as-is (not converted)
        let oidDict: [String: Any] = ["$oid": "50b59cd75bed76f46522c34e"]
        let result = try DQLValueFormatter.formatValue(oidDict)
        #expect(result == "{$oid: '50b59cd75bed76f46522c34e'}")
    }

    @Test func formatNestedObjectWithOid() throws {
        // Test that $oid in nested objects remains as object
        let doc: [String: Any] = [
            "_id": ["$oid": "50b59cd75bed76f46522c34e"],
            "name": "test"
        ]
        let result = try DQLValueFormatter.formatValue(doc)

        // Check that result contains both fields
        #expect(result.contains("_id: {$oid: '50b59cd75bed76f46522c34e'}"))
        #expect(result.contains("name: 'test'"))
    }

    // MARK: - Type Classification Tests

    @Test func classifyString() throws {
        let type = DQLValueFormatter.classifyType("hello")
        #expect(type == "string")
    }

    @Test func classifyBoolean() throws {
        let type = DQLValueFormatter.classifyType(true)
        #expect(type == "boolean")
    }

    @Test func classifyNumber() throws {
        let type = DQLValueFormatter.classifyType(42)
        #expect(type == "number")
    }

    @Test func classifyNull() throws {
        let type = DQLValueFormatter.classifyType(NSNull())
        #expect(type == "null")
    }

    @Test func classifyArray() throws {
        let type = DQLValueFormatter.classifyType([1, 2, 3])
        #expect(type == "array")
    }

    @Test func classifyObject() throws {
        let type = DQLValueFormatter.classifyType(["key": "value"])
        #expect(type == "object")
    }

    @Test func classifyMongoDBDate() throws {
        let dateDict: [String: Any] = ["$date": "2009-04-01T00:00:00.000-0700"]
        let type = DQLValueFormatter.classifyType(dateDict)
        #expect(type == "date")
    }

    @Test func classifyMongoDBObjectIdAsObject() throws {
        // $oid should be classified as object (not special type)
        let oidDict: [String: Any] = ["$oid": "50b59cd75bed76f46522c34e"]
        let type = DQLValueFormatter.classifyType(oidDict)
        #expect(type == "object")
    }

    // MARK: - Integration Tests (formatValue)

    @Test func formatValueWithString() throws {
        let result = try DQLValueFormatter.formatValue("test")
        #expect(result == "'test'")
    }

    @Test func formatValueWithNumber() throws {
        let result = try DQLValueFormatter.formatValue(123)
        #expect(result == "123")
    }

    @Test func formatValueWithBoolean() throws {
        let result = try DQLValueFormatter.formatValue(true)
        #expect(result == "true")
    }

    @Test func formatValueWithNull() throws {
        let result = try DQLValueFormatter.formatValue(NSNull())
        #expect(result == "NULL")
    }

    @Test func formatValueWithArray() throws {
        let result = try DQLValueFormatter.formatValue([1, 2, 3])
        #expect(result == "[1, 2, 3]")
    }

    @Test func formatValueWithObject() throws {
        let obj: [String: Any] = ["id": 1]
        let result = try DQLValueFormatter.formatValue(obj)
        #expect(result == "{id: 1}")
    }

    // MARK: - Edge Cases

    @Test func formatComplexNestedStructure() throws {
        let complex: [String: Any] = [
            "title": "Book Title",
            "author": ["name": "John Doe", "age": 45],
            "tags": ["fiction", "bestseller"],
            "available": true,
            "price": 29.99,
            "notes": NSNull(),
            "publishedDate": ["$date": "2009-04-01T00:00:00.000-0700"],
            "_id": ["$oid": "50b59cd75bed76f46522c34e"]
        ]

        let result = try DQLValueFormatter.formatValue(complex)

        // Verify all components are present
        #expect(result.contains("title: 'Book Title'"))
        #expect(result.contains("author: {"))
        #expect(result.contains("name: 'John Doe'"))
        #expect(result.contains("age: 45"))
        #expect(result.contains("tags: ['fiction', 'bestseller']"))
        #expect(result.contains("available: true"))
        #expect(result.contains("price: 29.99"))
        #expect(result.contains("notes: NULL"))
        #expect(result.contains("publishedDate: '2009-04-01T00:00:00.000-0700'"))
        #expect(result.contains("_id: {$oid: '50b59cd75bed76f46522c34e'}"))
    }

    @Test func distinguishBooleanFromNumber() throws {
        // Test that boolean true/false are not confused with 1/0
        let boolTrue = try DQLValueFormatter.formatValue(true)
        let boolFalse = try DQLValueFormatter.formatValue(false)
        let numOne = try DQLValueFormatter.formatValue(1)
        let numZero = try DQLValueFormatter.formatValue(0)

        #expect(boolTrue == "true")
        #expect(boolFalse == "false")
        #expect(numOne == "1")
        #expect(numZero == "0")
    }
}
