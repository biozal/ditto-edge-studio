package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.EventFilterMode
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for the observer events pagination chrome (SwiftUI `PaginationControls`
 * parity): event count, prev/next paging, page-size menu, and page clamping.
 */
@RunWith(AndroidJUnit4::class)
class ObserverDetailScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val observer = DittoObservable(
        id = 7L,
        databaseId = "db1",
        name = "My Observer",
        query = "SELECT * FROM things",
    )

    private fun events(count: Int) = (1..count).map { i ->
        DittoObserveEvent(observeId = observer.id.toString(), eventTime = "2026-08-23T12:00:${"%02d".format(i % 60)}Z")
    }

    @Test
    fun paginationBarShowsEventCountAndCurrentPage() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ObserverDetailScreen(
                    selectedObserver = observer,
                    events = events(60),
                    selectedEvent = null,
                    filterMode = EventFilterMode.ALL,
                    onSelectEvent = {},
                    onFilterChange = {},
                    pageSize = 25,
                    currentPage = 0,
                )
            }
        }

        composeTestRule.onNodeWithText("60 events").assertIsDisplayed()
        composeTestRule.onNodeWithText("Pg 1 / 3").assertIsDisplayed()
    }

    @Test
    fun nextAndPreviousButtonsPageThroughEvents() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                var page by remember { mutableIntStateOf(0) }
                ObserverDetailScreen(
                    selectedObserver = observer,
                    events = events(60),
                    selectedEvent = null,
                    filterMode = EventFilterMode.ALL,
                    onSelectEvent = {},
                    onFilterChange = {},
                    pageSize = 25,
                    currentPage = page,
                    onPageChange = { page = it },
                )
            }
        }

        composeTestRule.onNodeWithContentDescription("Previous page").assertIsNotEnabled()
        composeTestRule.onNodeWithContentDescription("Next page").performClick()
        composeTestRule.onNodeWithText("Pg 2 / 3").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Previous page").assertIsEnabled()
        composeTestRule.onNodeWithContentDescription("Previous page").performClick()
        composeTestRule.onNodeWithText("Pg 1 / 3").assertIsDisplayed()
    }

    @Test
    fun noNextPageOnLastPage() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ObserverDetailScreen(
                    selectedObserver = observer,
                    events = events(30),
                    selectedEvent = null,
                    filterMode = EventFilterMode.ALL,
                    onSelectEvent = {},
                    onFilterChange = {},
                    pageSize = 25,
                    currentPage = 1,
                    onPageChange = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Pg 2 / 2").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Next page").assertIsNotEnabled()
    }

    @Test
    fun pageSizeMenuOffersOptionsAndResetsPaging() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                var page by remember { mutableIntStateOf(0) }
                var size by remember { mutableIntStateOf(25) }
                ObserverDetailScreen(
                    selectedObserver = observer,
                    events = events(60),
                    selectedEvent = null,
                    filterMode = EventFilterMode.ALL,
                    onSelectEvent = {},
                    onFilterChange = {},
                    pageSize = size,
                    currentPage = page,
                    onPageChange = { page = it },
                    onPageSizeChange = {
                        size = it
                        page = 0
                    },
                )
            }
        }

        composeTestRule.onNodeWithText("25").performClick()
        composeTestRule.onNodeWithText("10 per page").assertIsDisplayed()
        composeTestRule.onNodeWithText("10 per page").performClick()

        // 60 events at 10 per page = 6 pages.
        composeTestRule.onNodeWithText("Pg 1 / 6").assertIsDisplayed()
    }

    @Test
    fun outOfRangeCurrentPageIsClampedToLastPage() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ObserverDetailScreen(
                    selectedObserver = observer,
                    events = events(5),
                    selectedEvent = null,
                    filterMode = EventFilterMode.ALL,
                    onSelectEvent = {},
                    onFilterChange = {},
                    pageSize = 25,
                    currentPage = 4,
                )
            }
        }

        // Page 4 requested with only 1 page of data — clamps silently to page 1.
        composeTestRule.onNodeWithText("Pg 1 / 1").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Previous page").assertIsNotEnabled()
    }
}
