package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.runtime.CompositionLocalProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueryWorkbenchTopToolbarTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun runButtonIsDisabledWhenQueryTextIsBlank() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsNotEnabled()
    }

    @Test
    fun runButtonIsEnabledWhenQueryTextIsNotBlankAndNotExecuting() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsEnabled().assertHasClickAction()
    }

    @Test
    fun runButtonIsDisabledWhileExecuting() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = true,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsNotEnabled()
    }

    @Test
    fun targetChipShowsCurrentMode() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "HTTP",
                    executeModes = listOf("Local", "HTTP"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").assertIsDisplayed()
    }

    @Test
    fun targetChipMenuExposesOnlyLocalWhenSingleMode() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.Local").assertIsDisplayed()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").assertDoesNotExist()
    }

    @Test
    fun targetChipMenuSwitchesToHttpWhenSelected() {
        val selectedMode = mutableStateOf("Local")
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = selectedMode.value,
                    executeModes = listOf("Local", "HTTP"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = { selectedMode.value = it },
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        rule.runOnIdle { assertEquals("HTTP", selectedMode.value) }
    }

    @Test
    fun optionsPopoverShowsTogglesAndReflectsInitialState() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = false,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").assertIsOff()
        rule.onNodeWithTag("QueryOptions.CaptureMetrics").assertIsOn()
    }

    @Test
    fun togglingProfilingSwitchInvokesCallback() {
        val profiling = mutableStateOf(true)
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = profiling.value,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = { profiling.value = it },
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").performClick()
        rule.runOnIdle { assertEquals(false, profiling.value) }
    }

    @Test
    fun runExplainMenuItemInvokesCallback() {
        var explained = false
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = { explained = true },
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.RunExplain").assertIsEnabled().performClick()
        rule.runOnIdle { assertTrue("onExplain must be invoked", explained) }
    }

    @Test
    fun runExplainMenuItemIsDisabledWhenQueryTextIsBlank() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onExplain = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.RunExplain").assertIsNotEnabled()
    }

    @Test
    fun tappingRunInvokesKeyboardHideAndOnRun() {
        var ranOnRun = false
        var hideInvoked = false
        val fakeController = object : SoftwareKeyboardController {
            override fun show() {}
            override fun hide() { hideInvoked = true }
        }
        rule.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalSoftwareKeyboardController provides fakeController) {
                    QueryWorkbenchTopToolbar(
                        queryText = "SELECT 1",
                        isExecuting = false,
                        executeMode = "Local",
                        executeModes = listOf("Local"),
                        captureProfilingData = true,
                        captureQueryMetrics = true,
                        onRun = { ranOnRun = true },
                        onExplain = {},
                        onModeSelect = {},
                        onCaptureProfilingDataChange = {},
                        onCaptureQueryMetricsChange = {},
                    )
                }
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        rule.runOnIdle {
            assertTrue("onRun must be invoked", ranOnRun)
            assertTrue("IME hide must be invoked before/with onRun", hideInvoked)
        }
    }
}
