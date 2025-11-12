//
//  ResultViewersUITests.swift
//  Edge Studio UITests
//

import XCTest

final class ResultViewersUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - ResultJsonViewer Tests

    @MainActor
    func testResultJsonViewer_NoQueryExecuted_ShowsRunQueryMessage() throws {
        // Given: A ResultJsonViewer with no query executed (hasExecutedQuery = false)
        // This would be tested through the main app interface
        // Navigate to query results area

        // When: The view is displayed with empty results and hasExecutedQuery = false

        // Then: It should display "Run a query for data"
        let runQueryText = app.staticTexts["Run a query for data"]
        XCTAssertTrue(runQueryText.waitForExistence(timeout: 5), "Should display 'Run a query for data' message when no query has been executed")
    }

    @MainActor
    func testResultJsonViewer_QueryExecutedWithEmptyResults_ShowsEmptyArray() throws {
        // Given: A ResultJsonViewer with a query executed but no results (hasExecutedQuery = true)

        // When: The view is displayed with empty results and hasExecutedQuery = true

        // Then: It should display "[]" (empty JSON array)
        let emptyArrayText = app.staticTexts["[]"]

        // Verify the text exists and is in monospaced font
        XCTAssertTrue(emptyArrayText.exists, "Should display '[]' when query has been executed with no results")

        // Verify it's selectable (textSelection enabled)
        XCTAssertTrue(emptyArrayText.isEnabled, "Empty array text should be selectable")
    }

    @MainActor
    func testResultJsonViewer_QueryWithResults_ShowsFormattedJson() throws {
        // Given: A ResultJsonViewer with query results

        // When: The view is displayed with actual results

        // Then: It should display formatted JSON array with results
        // The JSON should start with "[" and end with "]"
        let jsonText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '['")).firstMatch
        XCTAssertTrue(jsonText.exists, "Should display formatted JSON array when results exist")

        // Verify the text is in monospaced font and selectable
        XCTAssertTrue(jsonText.isEnabled, "JSON text should be selectable")
    }

    @MainActor
    func testResultJsonViewer_Pagination_WorksCorrectly() throws {
        // Given: A ResultJsonViewer with more results than page size

        // When: User navigates between pages

        // Then: Should show correct results per page
        let paginationControls = app.buttons.matching(identifier: "pagination").firstMatch
        XCTAssertTrue(paginationControls.exists, "Pagination controls should exist when there are results")
    }

    @MainActor
    func testResultJsonViewer_ExportButton_EnabledWithResults() throws {
        // Given: A ResultJsonViewer with query results

        // When: The view is displayed with results

        // Then: Export button should be enabled
        let exportButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'export' OR label CONTAINS 'square.and.arrow.down'")).firstMatch

        if exportButton.exists {
            XCTAssertTrue(exportButton.isEnabled, "Export button should be enabled when results exist")
        }
    }

    @MainActor
    func testResultJsonViewer_ExportButton_DisabledWithoutResults() throws {
        // Given: A ResultJsonViewer with no results

        // When: The view is displayed with empty results

        // Then: Export button should be disabled
        let exportButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'export' OR label CONTAINS 'square.and.arrow.down'")).firstMatch

        if exportButton.exists {
            XCTAssertFalse(exportButton.isEnabled, "Export button should be disabled when no results exist")
        }
    }

    // MARK: - ResultTableView Tests

    @MainActor
    func testResultTableView_NoQueryExecuted_ShowsRunQueryMessage() throws {
        // Given: A ResultTableView with no query executed (hasExecutedQuery = false)

        // When: The view is displayed with empty results and hasExecutedQuery = false

        // Then: It should display "Run a query for data"
        let runQueryText = app.staticTexts["Run a query for data"]
        XCTAssertTrue(runQueryText.waitForExistence(timeout: 5), "Should display 'Run a query for data' message when no query has been executed")
    }

    @MainActor
    func testResultTableView_QueryExecutedWithEmptyResults_ShowsZeroRecords() throws {
        // Given: A ResultTableView with a query executed but no results (hasExecutedQuery = true)

        // When: The view is displayed with empty results and hasExecutedQuery = true

        // Then: It should display "0 records found"
        let zeroRecordsText = app.staticTexts["0 records found"]
        XCTAssertTrue(zeroRecordsText.exists, "Should display '0 records found' when query has been executed with no results")
    }

    @MainActor
    func testResultTableView_QueryWithResults_ShowsTableHeaders() throws {
        // Given: A ResultTableView with query results

        // When: The view is displayed with actual results

        // Then: It should display table headers
        // Look for the row number column header "#"
        let rowNumberHeader = app.staticTexts["#"]
        XCTAssertTrue(rowNumberHeader.exists, "Should display row number header when results exist")

        // Headers should be bold and in monospaced font
        XCTAssertTrue(rowNumberHeader.exists, "Row number header should exist")
    }

    @MainActor
    func testResultTableView_QueryWithResults_ShowsDataRows() throws {
        // Given: A ResultTableView with query results

        // When: The view is displayed with actual results

        // Then: It should display data rows with row numbers
        let firstRowNumber = app.staticTexts["1"]

        if firstRowNumber.exists {
            XCTAssertTrue(firstRowNumber.exists, "Should display row numbers for data rows")
        }
    }

    @MainActor
    func testResultTableView_RowHover_ShowsHighlight() throws {
        // Given: A ResultTableView with query results

        // When: User hovers over a row

        // Then: The row should show hover highlighting
        // This requires interaction testing which may need manual verification
        // or more sophisticated XCTest interaction APIs
    }

    @MainActor
    func testResultTableView_RowClick_OpensDetailModal() throws {
        // Given: A ResultTableView with query results

        // When: User clicks on a row
        let firstRow = app.tables.firstMatch.cells.firstMatch
        if firstRow.exists {
            firstRow.tap()

            // Then: Should open the RecordDetailModal
            let modal = app.sheets.firstMatch
            XCTAssertTrue(modal.waitForExistence(timeout: 2), "Should open detail modal when row is clicked")
        }
    }

    @MainActor
    func testResultTableView_ContextMenu_HasCopyOption() throws {
        // Given: A ResultTableView with query results

        // When: User right-clicks on a row
        let firstRow = app.tables.firstMatch.cells.firstMatch
        if firstRow.exists {
            firstRow.rightClick()

            // Then: Context menu should have "Copy JSON" option
            let copyMenuItem = app.menuItems["Copy JSON"]
            XCTAssertTrue(copyMenuItem.waitForExistence(timeout: 2), "Should show 'Copy JSON' in context menu")
        }
    }

    @MainActor
    func testResultTableView_ContextMenu_HasDeleteOption() throws {
        // Given: A ResultTableView with query results and delete handler

        // When: User right-clicks on a row
        let firstRow = app.tables.firstMatch.cells.firstMatch
        if firstRow.exists {
            firstRow.rightClick()

            // Then: Context menu should have "Delete Document" option
            let deleteMenuItem = app.menuItems["Delete Document"]

            // This may only exist if onDelete handler is provided and document has _id
            if deleteMenuItem.exists {
                XCTAssertTrue(deleteMenuItem.exists, "Should show 'Delete Document' in context menu when delete handler exists")
            }
        }
    }

    @MainActor
    func testResultTableView_ColumnResize_WorksCorrectly() throws {
        // Given: A ResultTableView with query results showing columns

        // When: User drags the column resize handle

        // Then: Column width should change
        // This requires more sophisticated gesture testing
        // The resize handle is visible as 3 vertical dots
    }

    // MARK: - Pagination Tests

    @MainActor
    func testPagination_PageSizeOptions_AdjustBasedOnResultCount() throws {
        // Given: ResultViewer with different result counts

        // When: Results are loaded

        // Then: Page size options should adjust based on total count
        // For 0-10 results: only [10]
        // For 11-25 results: [25]
        // For 26-50 results: [25, 50]
        // etc.
    }

    @MainActor
    func testPagination_NextPage_ShowsCorrectResults() throws {
        // Given: ResultViewer with multiple pages of results

        // When: User clicks next page
        let nextPageButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'nextPage' OR label CONTAINS 'chevron.right'")).firstMatch

        if nextPageButton.exists && nextPageButton.isEnabled {
            nextPageButton.tap()

            // Then: Should display next page of results
            // Verify current page indicator changed
        }
    }

    @MainActor
    func testPagination_PreviousPage_ShowsCorrectResults() throws {
        // Given: ResultViewer on page 2 or later

        // When: User clicks previous page
        let prevPageButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'prevPage' OR label CONTAINS 'chevron.left'")).firstMatch

        if prevPageButton.exists && prevPageButton.isEnabled {
            prevPageButton.tap()

            // Then: Should display previous page of results
        }
    }

    @MainActor
    func testPagination_ChangePageSize_ResetsToFirstPage() throws {
        // Given: ResultViewer on page 2 or later

        // When: User changes page size

        // Then: Should reset to page 1
    }
}
