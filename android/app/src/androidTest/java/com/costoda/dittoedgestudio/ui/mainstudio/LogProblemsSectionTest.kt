package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.logging.LogPatternEngine
import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.costoda.dittoedgestudio.domain.model.LogPattern
import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LogProblemsSectionTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun matchAt(
        millis: Long,
        message: String,
        key: String = "deadlock_critical",
        severity: Int = 5,
    ): LogPatternEngine.Match {
        val body = LogPatternBody(pattern = "deadlock", severity = severity, recommendation = "rec")
        val pattern = LogPattern(key, body, severity, null, PatternSource.BUNDLED)
        val compiled = LogPatternEngine(mapOf(key to pattern)).compiled.single()
        return LogPatternEngine.Match(
            pattern = compiled,
            entry = LogEntry(
                timestamp = Date(millis),
                level = DittoLogLevel.Error,
                message = message,
                component = LogComponent.SYNC,
                source = LogEntrySource.DittoSDK,
                rawLine = "",
            ),
        )
    }

    @Test
    fun rendersNothingWithoutProblems() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                LogProblemsSection(problems = emptyList(), onJumpToEntry = {})
            }
        }
        composeTestRule.onNodeWithContentDescription("Show problems").assertDoesNotExist()
    }

    @Test
    fun headerSummarizesHitsAndExpandsToGroups() {
        val problems = listOf(matchAt(0, "deadlock elapsed=1"), matchAt(1, "deadlock elapsed=2"))
        composeTestRule.setContent {
            EdgeStudioTheme {
                LogProblemsSection(problems = problems, onJumpToEntry = {})
            }
        }

        composeTestRule.onNodeWithText("2 problems matched on 2 log lines").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Show problems").performClick()
        composeTestRule.onNodeWithText("deadlock_critical ×2").assertIsDisplayed()
        composeTestRule.onNodeWithText("rec").assertIsDisplayed()
    }

    @Test
    fun expandingGroupListsHitsAndJumpCallbackFires() {
        val problems = listOf(matchAt(0, "deadlock elapsed=1"), matchAt(1, "deadlock elapsed=2"))
        var jumpedTo: LogEntry? = null

        composeTestRule.setContent {
            EdgeStudioTheme {
                LogProblemsSection(problems = problems, onJumpToEntry = { jumpedTo = it })
            }
        }

        composeTestRule.onNodeWithContentDescription("Show problems").performClick()
        composeTestRule.onNodeWithContentDescription("Expand deadlock_critical").performClick()
        composeTestRule.onNodeWithText("deadlock elapsed=1").assertIsDisplayed()
        composeTestRule.onNodeWithText("deadlock elapsed=1").performClick()
        assertEquals("deadlock elapsed=1", jumpedTo?.message)
    }
}
