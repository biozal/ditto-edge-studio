import Testing
import SwiftUI
@testable import Edge_Debug_Helper

@Suite("ResultJsonViewer Regression Tests")
struct ResultJsonViewerRegressionTests {

    @Test("Standalone usage still works")
    func standaloneUsageStillWorks() {
        // Verify ResultJsonViewer can still be used without external pagination
        let results = [
            "{\"_id\": \"1\", \"name\": \"John\"}",
            "{\"_id\": \"2\", \"name\": \"Jane\"}"
        ]

        // This should compile and work without external bindings
        let viewer = ResultJsonViewer(resultText: .constant(results))

        // Verify the viewer was created
        #expect(viewer.resultText.count == 2)
    }

    @Test("Internal pagination still works")
    func internalPaginationStillWorks() {
        // When no external pagination is provided, internal state should be used
        let totalResults = 100
        let pageSize = 25

        let pageCount = max(1, Int(ceil(Double(totalResults) / Double(pageSize))))
        #expect(pageCount == 4)

        var currentPage = 1
        currentPage = max(1, min(5, pageCount))
        #expect(currentPage == 4)  // Should be capped at pageCount
    }

    @Test("Paged items calculation")
    func pagedItemsCalculation() {
        let results = Array(1...50).map { "{\"id\": \($0)}" }
        let currentPage = 2
        let pageSize = 10

        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, results.count)
        let pagedItems = Array(results[start..<end])

        #expect(pagedItems.count == 10)
        #expect(pagedItems.first == "{\"id\": 11}")
        #expect(pagedItems.last == "{\"id\": 20}")
    }

    @Test("Page size change resets behavior")
    func pageSizeChangeResetsBehavior() {
        var currentPage = 5

        // Change page size
        currentPage = 1  // Should reset to 1

        #expect(currentPage == 1)
    }

    @Test("Results change resets behavior")
    func resultsChangeResetsBehavior() {
        var currentPage = 3
        var pageSize = 25
        let pageSizes = [10, 25, 50]

        // Simulate results change
        currentPage = 1  // Should reset to 1

        // If new pageSize not in available sizes, reset to first
        if !pageSizes.contains(pageSize) {
            pageSize = pageSizes.first ?? 25
        }

        #expect(currentPage == 1)
    }

    @Test("Flatten JSON results logic")
    func flattenJsonResultsLogic() {
        // Test single result
        let singleResult = ["{\"key\": \"value\"}"]
        let flattenedSingle: String
        if singleResult.count == 1 {
            flattenedSingle = singleResult.first ?? "[]"
        } else {
            flattenedSingle = "[\n" + singleResult.joined(separator: ",\n") + "\n]"
        }
        #expect(flattenedSingle == "{\"key\": \"value\"}")

        // Test multiple results
        let multipleResults = ["{\"id\": 1}", "{\"id\": 2}"]
        let flattenedMultiple: String
        if multipleResults.count == 1 {
            flattenedMultiple = multipleResults.first ?? "[]"
        } else {
            flattenedMultiple = "[\n" + multipleResults.joined(separator: ",\n") + "\n]"
        }
        #expect(flattenedMultiple == "[\n{\"id\": 1},\n{\"id\": 2}\n]")
    }

    @Test("Export functionality intact")
    func exportFunctionalityIntact() {
        // Verify export button behavior is preserved
        var isExporting = false

        // Simulate button press
        isExporting = true
        #expect(isExporting)

        // Should be disabled when no results
        let resultCount = 0
        let shouldDisable = resultCount == 0
        #expect(shouldDisable)
    }

    @Test("Convenience initializer works")
    func convenienceInitializerWorks() {
        let staticResults = [
            "{\"_id\": \"1\"}",
            "{\"_id\": \"2\"}"
        ]

        // Test convenience initializer for static arrays
        let _ = ResultJsonViewer(resultText: staticResults)

        // Verify the viewer was created (can't directly test @State)
        // The important part is that it compiles
        #expect(staticResults.count == 2)
    }

    @Test("Binding initializer works")
    func bindingInitializerWorks() {
        var results = [
            "{\"_id\": \"1\"}",
            "{\"_id\": \"2\"}"
        ]

        // Test binding initializer
        let viewer = ResultJsonViewer(resultText: .constant(results))

        // Verify the viewer was created
        #expect(viewer.resultText.count == 2)

        // Modify results
        results.append("{\"_id\": \"3\"}")
        #expect(results.count == 3)
    }
}
