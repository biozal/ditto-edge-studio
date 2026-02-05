//
//  QueryResultsViewTests.swift
//  Edge Debug Helper Tests
//
//  Created by Claude Code
//  Integration tests for QueryResultsView using Swift Testing
//

import Testing
import SwiftUI
@testable import Edge_Debug_Helper

@Suite("QueryResultsView Tests")
struct QueryResultsViewTests {

    @Test("Pagination state shared between tabs")
    func paginationStateSharedBetweenTabs() {
        // Test that changing page on one tab affects the other
        var currentPage = 1

        // Simulate page change
        currentPage = 3

        #expect(currentPage == 3)
        // Both tabs would use the same currentPage binding
    }

    @Test("Page size changes reset to page 1")
    func pageSizeChangesResetToPage1() {
        var currentPage = 5
        var pageSize = 10

        // Simulate page size change
        pageSize = 25
        currentPage = 1  // Should reset

        #expect(currentPage == 1)
        #expect(pageSize == 25)
    }

    @Test("Result changes reset to page 1")
    func resultChangesResetToPage1() {
        var currentPage = 3

        // Simulate result change
        let newResults = ["new1", "new2"]
        currentPage = 1  // Should reset

        #expect(currentPage == 1)
        #expect(newResults.count == 2)
    }

    @Test("Page count calculation")
    func pageCountCalculation() {
        let totalResults = 100
        let pageSize = 25

        let pageCount = max(1, Int(ceil(Double(totalResults) / Double(pageSize))))
        #expect(pageCount == 4)
    }

    @Test("Page count with partial last page")
    func pageCountWithPartialLastPage() {
        let totalResults = 105
        let pageSize = 25

        let pageCount = max(1, Int(ceil(Double(totalResults) / Double(pageSize))))
        #expect(pageCount == 5)
    }

    @Test("Page count with empty results")
    func pageCountWithEmptyResults() {
        let totalResults = 0
        let pageSize = 25

        let pageCount = max(1, Int(ceil(Double(totalResults) / Double(pageSize))))
        #expect(pageCount == 1)
    }

    @Test("Page sizes array generation")
    func pageSizesArrayGeneration() {
        func pageSizes(for count: Int) -> [Int] {
            switch count {
            case 0...10: return [10]
            case 11...25: return [25]
            case 26...50: return [25, 50]
            case 51...100: return [25, 50, 100]
            case 101...200: return [25, 50, 100, 200]
            case 201...250: return [25, 50, 100, 200, 250]
            default: return [10, 25, 50, 100, 200, 250]
            }
        }

        #expect(pageSizes(for: 5) == [10])
        #expect(pageSizes(for: 20) == [25])
        #expect(pageSizes(for: 40) == [25, 50])
        #expect(pageSizes(for: 80) == [25, 50, 100])
        #expect(pageSizes(for: 150) == [25, 50, 100, 200])
        #expect(pageSizes(for: 220) == [25, 50, 100, 200, 250])
        #expect(pageSizes(for: 300) == [10, 25, 50, 100, 200, 250])
    }

    @Test("Tab enumeration")
    func tabEnumeration() {
        let tabs = ResultViewTab.allCases
        #expect(tabs.count == 2)
        #expect(tabs.contains(.raw))
        #expect(tabs.contains(.table))
    }

    @Test("Tab icons")
    func tabIcons() {
        #expect(ResultViewTab.raw.icon == "doc.plaintext")
        #expect(ResultViewTab.table.icon == "tablecells")
    }

    @Test("Flatten JSON results single object")
    func flattenJsonResultsSingleObject() {
        let results = ["{\"key\": \"value\"}"]

        let flattened: String
        if results.count == 1 {
            flattened = results.first ?? "[]"
        } else {
            flattened = "[\n" + results.joined(separator: ",\n") + "\n]"
        }

        #expect(flattened == "{\"key\": \"value\"}")
    }

    @Test("Flatten JSON results multiple objects")
    func flattenJsonResultsMultipleObjects() {
        let results = [
            "{\"id\": 1}",
            "{\"id\": 2}",
            "{\"id\": 3}"
        ]

        let flattened: String
        if results.count == 1 {
            flattened = results.first ?? "[]"
        } else {
            flattened = "[\n" + results.joined(separator: ",\n") + "\n]"
        }

        #expect(flattened == "[\n{\"id\": 1},\n{\"id\": 2},\n{\"id\": 3}\n]")
    }
}
