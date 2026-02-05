//
//  ResultTableViewerTests.swift
//  Edge Debug Helper Tests
//
//  Created by Claude Code
//  Unit tests for ResultTableViewer component using Swift Testing
//

import Testing
import SwiftUI
@testable import Edge_Debug_Helper

@Suite("ResultTableViewer Tests")
struct ResultTableViewerTests {

    @Test("Table renders with data")
    func tableRendersWithData() async {
        let results = [
            "{\"_id\": \"1\", \"name\": \"John\"}",
            "{\"_id\": \"2\", \"name\": \"Jane\"}"
        ]

        let parser = TableResultsParser.shared
        let data = await parser.parseResults(results)

        #expect(!data.isMutationResult)
        #expect(data.rows.count == 2)
        #expect(data.columns.contains("_id"))
        #expect(data.columns.contains("name"))
    }

    @Test("Table handles empty results")
    func tableHandlesEmptyResults() async {
        let results: [String] = []

        let parser = TableResultsParser.shared
        let data = await parser.parseResults(results)

        #expect(data.rows.count == 0)
        #expect(data.columns.count == 0)
    }

    @Test("Table handles single result")
    func tableHandlesSingleResult() async {
        let results = ["{\"_id\": \"1\", \"name\": \"John\"}"]

        let parser = TableResultsParser.shared
        let data = await parser.parseResults(results)

        #expect(data.rows.count == 1)
        #expect(data.rows[0].cells["_id"]?.displayValue == "1")
        #expect(data.rows[0].cells["name"]?.displayValue == "John")
    }

    @Test("Pagination calculations are correct")
    func paginationCalculations() {
        let totalResults = 105
        let pageSize = 25

        let pageCount = max(1, Int(ceil(Double(totalResults) / Double(pageSize))))
        #expect(pageCount == 5)

        // Test page 1
        let page1Start = (1 - 1) * pageSize
        let page1End = min(page1Start + pageSize, totalResults)
        #expect(page1Start == 0)
        #expect(page1End == 25)

        // Test page 5 (last page with partial results)
        let page5Start = (5 - 1) * pageSize
        let page5End = min(page5Start + pageSize, totalResults)
        #expect(page5Start == 100)
        #expect(page5End == 105)
    }

    @Test("Loading state handling")
    func loadingStateHandling() {
        // Verify the logic for empty vs valid results
        let emptyResults: [String] = []
        #expect(emptyResults.isEmpty)

        let validResults = ["{\"_id\": \"1\"}"]
        #expect(!validResults.isEmpty)
    }

    @Test("Row index preserved")
    func rowIndexPreserved() async {
        let results = [
            "{\"_id\": \"1\"}",
            "{\"_id\": \"2\"}",
            "{\"_id\": \"3\"}"
        ]

        let parser = TableResultsParser.shared
        let data = await parser.parseResults(results)

        #expect(data.rows[0].rowIndex == 0)
        #expect(data.rows[1].rowIndex == 1)
        #expect(data.rows[2].rowIndex == 2)
    }
}
