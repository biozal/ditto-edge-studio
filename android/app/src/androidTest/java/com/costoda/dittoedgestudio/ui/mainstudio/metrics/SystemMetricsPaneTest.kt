package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.SystemMetricKind
import com.costoda.dittoedgestudio.domain.model.SystemMetricSample
import com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot
import com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SystemMetricsPaneTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun sample(key: String, since: Double, period: Double = 0.0) = SystemMetricSample(
        key = key,
        labels = emptyMap(),
        description = "",
        unit = "",
        kind = SystemMetricKind.COUNTER,
        sinceConnect = since,
        periodDelta = period,
    )

    private fun snap(
        samples: List<SystemMetricSample>,
        status: SystemMetricsStatus = SystemMetricsStatus.READY,
    ) = SystemMetricsSnapshot(samples = samples, status = status, sinceMs = 1_000, polledAtMs = 2_000)

    @Test
    fun settingDisabledExplainsNextOpenSemantics() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(snapshot = snap(emptyList(), SystemMetricsStatus.SETTING_DISABLED))
            }
        }
        composeTestRule.onNodeWithText(
            "System metrics collection is off. Enable \"Collect system metrics\" in Settings — " +
                "it takes effect the next time you open a database.",
        ).assertIsDisplayed()
    }

    @Test
    fun exporterDisabledGuidesReopen() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(snapshot = snap(emptyList(), SystemMetricsStatus.EXPORTER_DISABLED))
            }
        }
        composeTestRule.onNodeWithText(
            "The SDK exporter wasn't enabled for this session. " +
                "Close and re-open the database after enabling \"Collect system metrics\".",
        ).assertIsDisplayed()
    }

    @Test
    fun tableShowsAccumulatedTotalsAndPeriodDeltas() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(
                    snapshot = snap(
                        listOf(
                            sample("ditto.network.dsoq.connection.opened", 12.0, 1.0),
                            sample("ditto.backend.sqlite3.fsync_total", 340.0),
                        ),
                    ),
                )
            }
        }
        composeTestRule.onNodeWithText("network.dsoq.connection.opened").assertIsDisplayed()
        composeTestRule.onNodeWithText("12").assertIsDisplayed()
        composeTestRule.onNodeWithText("▲ +1").assertIsDisplayed()
        // No divergence: opened present without closed → no banner.
        composeTestRule.onNodeWithText("possible connection leak", substring = true).assertDoesNotExist()
    }

    @Test
    fun divergenceBannerWhenOpenedDiffersFromClosed() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(
                    snapshot = snap(
                        listOf(
                            sample("ditto.network.dsoq.connection.opened", 12.0),
                            sample("ditto.network.dsoq.connection.closed", 11.0),
                        ),
                    ),
                )
            }
        }
        composeTestRule.onNodeWithText("possible connection leak", substring = true).assertIsDisplayed()
    }

    @Test
    fun namespaceFilterNarrowsRows() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(
                    snapshot = snap(
                        listOf(
                            sample("ditto.network.dsoq.connection.opened", 12.0),
                            sample("ditto.backend.sqlite3.fsync_total", 340.0),
                        ),
                    ),
                )
            }
        }
        composeTestRule.onNodeWithText("Store").performClick()
        composeTestRule.onNodeWithText("backend.sqlite3.fsync_total").assertIsDisplayed()
        composeTestRule.onNodeWithText("network.dsoq.connection.opened").assertDoesNotExist()
    }
}
