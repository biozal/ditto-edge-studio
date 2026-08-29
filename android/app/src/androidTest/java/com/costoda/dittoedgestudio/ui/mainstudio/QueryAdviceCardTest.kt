package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.filter
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.QueryAdvice
import com.costoda.dittoedgestudio.domain.model.QueryIndexSuggestion
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueryAdviceCardTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val suggestion = QueryIndexSuggestion(
        collection = "atest",
        reason = "equality predicates on `e`",
        statement = "CREATE INDEX IF NOT EXISTS adv_atest_e ON default:`atest` (`e` ASC)",
    )

    @Test
    fun outcomeOnlyRendersOutcomeText() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryAdviceCard(
                    advice = QueryAdvice("SELECT * FROM t", "no keys to advise on", emptyList()),
                    onApply = { true },
                    onDismiss = {},
                )
            }
        }
        composeTestRule.onNodeWithText("no keys to advise on").assertIsDisplayed()
        composeTestRule.onNodeWithText("Apply").assertDoesNotExist()
    }

    @Test
    fun applyRequiresConfirmationThenMarksCreated() {
        var applied: QueryIndexSuggestion? = null
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryAdviceCard(
                    advice = QueryAdvice("SELECT * FROM atest WHERE e=1", null, listOf(suggestion)),
                    onApply = { applied = it; true },
                    onDismiss = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Apply").performClick()
        // Confirmation dialog shows the exact statement before executing
        // (it also appears in the card row, so assert both render).
        composeTestRule.onNodeWithText("Create index on atest?").assertIsDisplayed()
        composeTestRule.onAllNodesWithText(suggestion.statement)
            .assertCountEquals(2)
            .filter(hasAnyAncestor(isDialog()))
            .assertCountEquals(1)
        composeTestRule.onNodeWithText("Create Index").performClick()
        composeTestRule.waitForIdle()

        assertEquals(suggestion, applied)
        composeTestRule.onNodeWithText("✓ Created").assertIsDisplayed()
    }

    @Test
    fun failedApplyMarksFailed() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryAdviceCard(
                    advice = QueryAdvice("SELECT * FROM atest", null, listOf(suggestion)),
                    onApply = { false },
                    onDismiss = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Apply").performClick()
        composeTestRule.onNodeWithText("Create Index").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("✗ Failed").assertIsDisplayed()
    }

    @Test
    fun dismissCallbackFiresFromCloseButton() {
        var dismissed = false
        composeTestRule.setContent {
            EdgeStudioTheme {
                QueryAdviceCard(
                    advice = QueryAdvice("SELECT * FROM t", null, emptyList()),
                    onApply = { true },
                    onDismiss = { dismissed = true },
                )
            }
        }
        composeTestRule.onNodeWithContentDescription("Dismiss index advice").performClick()
        assertEquals(true, dismissed)
    }
}
