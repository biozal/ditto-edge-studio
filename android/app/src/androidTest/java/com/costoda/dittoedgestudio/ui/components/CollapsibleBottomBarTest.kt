package com.costoda.dittoedgestudio.ui.components

import androidx.compose.material3.Text
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for [CollapsibleBottomBar] — the floating-bar chrome that lets the user
 * fold the pagination bar away (SwiftUI DetailBottomBar parity) so it stops covering
 * detail content like the Profile tab.
 */
@RunWith(AndroidJUnit4::class)
class CollapsibleBottomBarTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun setContent() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                CollapsibleBottomBar {
                    Text("Bar content")
                }
            }
        }
    }

    @Test
    fun barStartsExpandedWithContentVisible() {
        setContent()

        composeTestRule.onNodeWithText("Bar content").assertIsDisplayed()
        composeTestRule.onNodeWithTag("CollapseBottomBar").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ExpandBottomBar").assertDoesNotExist()
    }

    @Test
    fun collapseHidesContentAndShowsExpandPill() {
        setContent()

        composeTestRule.onNodeWithTag("CollapseBottomBar").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Bar content").assertDoesNotExist()
        composeTestRule.onNodeWithTag("ExpandBottomBar").assertIsDisplayed()
    }

    @Test
    fun expandRestoresContent() {
        setContent()

        composeTestRule.onNodeWithTag("CollapseBottomBar").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("ExpandBottomBar").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Bar content").assertIsDisplayed()
        composeTestRule.onNodeWithTag("CollapseBottomBar").assertIsDisplayed()
    }
}
