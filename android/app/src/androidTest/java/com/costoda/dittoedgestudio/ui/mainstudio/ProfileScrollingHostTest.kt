package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.isDisplayed
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes
import com.costoda.dittoedgestudio.domain.model.QueryResult
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Reproduction test: the Profile tab must scroll when hosted inside the real
 * QueryResultsView container (not just standalone). Renders the actual host with a
 * plan taller than the viewport and scrolls the card list to its footer.
 */
@RunWith(AndroidJUnit4::class)
class ProfileScrollingHostTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val tallPlan: QueryProfileOperator = (1..30).fold(
        QueryProfileOperator(
            id = "op-leaf",
            name = "leaf",
            stats = null,
            attributes = listOf("collection" to "movies"),
            children = emptyList(),
        ),
    ) { child, i ->
        QueryProfileOperator(
            id = "op-$i",
            name = "node$i",
            stats = null,
            attributes = emptyList(),
            children = listOf(child),
        )
    }

    private val profile = QueryProfile(
        id = "p1",
        appId = "db1",
        featureFlags = "0x83a",
        queryType = "select",
        requestType = "SDK",
        resultCount = 1,
        state = "completed",
        text = "PROFILE SELECT * FROM movies",
        times = QueryProfileTimes(1_000_000, 2_000, 3_000, ""),
        plan = tallPlan,
        capturedAtMs = 1_787_179_553_747,
    )

    @Test
    fun profileTabScrollsInsideQueryResultsView() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryResultsView(
                    queryResult = QueryResult(
                        documents = listOf(mapOf("_id" to "1")),
                        totalCount = 1,
                        executionTimeMs = 5,
                        profile = profile,
                    ),
                    displayedDocuments = listOf(mapOf("_id" to "1")),
                    isExecuting = false,
                    executionError = null,
                    captureProfilingData = true,
                    lastQueryText = "SELECT * FROM movies",
                    onDocumentSelected = {},
                    onAddConfirm = { _, _, _, _, _, _ -> },
                    onDeleteConfirm = { _, _, _ -> },
                )
            }
        }

        // Switch to the PROFILE tab.
        composeTestRule.onNodeWithText("PROFILE").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("ProfileFooter").performScrollTo()
        composeTestRule.onNodeWithTag("ProfileFooter").assertIsDisplayed()
    }

    @Test
    fun profileTabScrollsWithRealSwipeGestures() {
        // Semantics-based performScrollToNode bypasses touch handling, so it cannot
        // catch a parent eating vertical drags. This test swipes like a user does.
        setHostContent()

        composeTestRule.onNodeWithText("PROFILE").performClick()
        composeTestRule.waitForIdle()

        // Card mode: swipe up on the page until the footer appears.
        val footer = composeTestRule.onNodeWithTag("ProfileFooter")
        repeat(15) {
            if (footer.isDisplayed()) return@repeat
            composeTestRule.onNodeWithTag("ProfileScroll")
                .performTouchInput { swipeUp() }
            composeTestRule.waitForIdle()
        }
        footer.assertIsDisplayed()
    }

    @Test
    fun planModeScrollsWithRealSwipeGestures() {
        setHostContent()

        composeTestRule.onNodeWithText("PROFILE").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Plan").performClick()
        composeTestRule.waitForIdle()

        val footer = composeTestRule.onNodeWithTag("ProfileFooter")
        repeat(15) {
            if (footer.isDisplayed()) return@repeat
            composeTestRule.onNodeWithTag("ProfileScroll")
                .performTouchInput { swipeUp() }
            composeTestRule.waitForIdle()
        }
        footer.assertIsDisplayed()
    }

    private fun setHostContent() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryResultsView(
                    queryResult = QueryResult(
                        documents = listOf(mapOf("_id" to "1")),
                        totalCount = 1,
                        executionTimeMs = 5,
                        profile = profile,
                    ),
                    displayedDocuments = listOf(mapOf("_id" to "1")),
                    isExecuting = false,
                    executionError = null,
                    captureProfilingData = true,
                    lastQueryText = "SELECT * FROM movies",
                    onDocumentSelected = {},
                    onAddConfirm = { _, _, _, _, _, _ -> },
                    onDeleteConfirm = { _, _, _ -> },
                )
            }
        }
    }

    @Test
    fun profileTabScrollsInSmallFoldSizedViewport() {
        // The Fold's cover display leaves the results pane small and narrow: the
        // summary cards wrap to several rows, squeezing the plan list. The list must
        // still scroll rather than clip.
        composeTestRule.setContent {
            EdgeStudioTheme {
                Box(modifier = Modifier.size(360.dp, 320.dp)) {
                    QueryResultsView(
                        queryResult = QueryResult(
                            documents = listOf(mapOf("_id" to "1")),
                            totalCount = 1,
                            executionTimeMs = 5,
                            profile = profile,
                        ),
                        displayedDocuments = listOf(mapOf("_id" to "1")),
                        isExecuting = false,
                        executionError = null,
                        captureProfilingData = true,
                        lastQueryText = "SELECT * FROM movies",
                        onDocumentSelected = {},
                        onAddConfirm = { _, _, _, _, _, _ -> },
                        onDeleteConfirm = { _, _, _ -> },
                    )
                }
            }
        }

        composeTestRule.onNodeWithText("PROFILE").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("ProfileFooter").performScrollTo()
        composeTestRule.onNodeWithTag("ProfileFooter").assertIsDisplayed()
    }
}
