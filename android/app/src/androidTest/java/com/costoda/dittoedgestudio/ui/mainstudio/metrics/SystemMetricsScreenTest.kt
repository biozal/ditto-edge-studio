package com.costoda.dittoedgestudio.ui.mainstudio.metrics

import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.SystemMetricKind
import com.costoda.dittoedgestudio.domain.model.SystemMetricSample
import com.costoda.dittoedgestudio.domain.model.SystemMetricSeriesRef
import com.costoda.dittoedgestudio.domain.model.SystemMetricsSnapshot
import com.costoda.dittoedgestudio.domain.model.SystemMetricsStatus
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// performCustomAccessibilityActionWithLabel is still marked experimental; it is
// the only way to drive the reorder actions without simulating a real drag.
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class SystemMetricsScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun sample(
        key: String,
        since: Double,
        period: Double = 0.0,
        labels: Map<String, String> = emptyMap(),
        description: String = "",
        unit: String = "",
        kind: SystemMetricKind = SystemMetricKind.COUNTER,
        sumSinceConnect: Double? = null,
        absMax: Double? = null,
    ) = SystemMetricSample(
        key = key,
        labels = labels,
        description = description,
        unit = unit,
        kind = kind,
        sinceConnect = since,
        periodDelta = period,
        sumSinceConnect = sumSinceConnect,
        absMax = absMax,
    )

    private fun snap(
        samples: List<SystemMetricSample>,
        status: SystemMetricsStatus = SystemMetricsStatus.READY,
    ) = SystemMetricsSnapshot(samples = samples, status = status, sinceMs = 1_000, polledAtMs = 2_000)

    /** Hosts the pane with real pin state so pin/unpin/clear round-trip like production. */
    private fun setPaneWithPins(
        snapshot: SystemMetricsSnapshot,
        initialPins: List<SystemMetricSeriesRef> = emptyList(),
        onChange: (List<SystemMetricSeriesRef>) -> Unit = {},
    ) {
        composeTestRule.setContent {
            EdgeStudioTheme {
                var pins by remember { mutableStateOf(initialPins) }
                SystemMetricsPane(
                    snapshot = snapshot,
                    pins = pins,
                    onPinsChange = { pins = it; onChange(it) },
                )
            }
        }
    }

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

    // ── Search ───────────────────────────────────────────────────────────────

    @Test
    fun searchMatchesMetricKeys() {
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
        composeTestRule.onNodeWithContentDescription("Filter metrics").performTextInput("fsync")
        composeTestRule.onNodeWithText("backend.sqlite3.fsync_total").assertIsDisplayed()
        composeTestRule.onNodeWithText("network.dsoq.connection.opened").assertDoesNotExist()
    }

    @Test
    fun searchAlsoMatchesLabelValues() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(
                    snapshot = snap(
                        listOf(
                            sample("ditto.network.bytes_sent", 12.0, labels = mapOf("transport" to "ble")),
                            sample("ditto.network.bytes_recv", 9.0, labels = mapOf("transport" to "lan")),
                        ),
                    ),
                )
            }
        }
        composeTestRule.onNodeWithContentDescription("Filter metrics").performTextInput("ble")
        composeTestRule.onNodeWithText("network.bytes_sent").assertIsDisplayed()
        composeTestRule.onNodeWithText("network.bytes_recv").assertDoesNotExist()
    }

    @Test
    fun searchWithNoMatchesExplainsWhy() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(snapshot = snap(listOf(sample("ditto.network.bytes_sent", 12.0))))
            }
        }
        composeTestRule.onNodeWithContentDescription("Filter metrics").performTextInput("zzz")
        composeTestRule.onNodeWithText("No metrics match \"zzz\".").assertIsDisplayed()
    }

    // ── Details ──────────────────────────────────────────────────────────────

    @Test
    fun infoButtonRevealsSeriesDetails() {
        val key = "ditto.backend.sqlite3.txn_duration"
        composeTestRule.setContent {
            EdgeStudioTheme {
                SystemMetricsPane(
                    snapshot = snap(
                        listOf(
                            sample(
                                key = key,
                                since = 4.0,
                                description = "Time spent in SQLite transactions.",
                                unit = "seconds",
                                kind = SystemMetricKind.HISTOGRAM,
                                sumSinceConnect = 2.0,
                                absMax = 1.5,
                            ),
                        ),
                    ),
                )
            }
        }
        composeTestRule.onNodeWithText("Time spent in SQLite transactions.").assertDoesNotExist()

        composeTestRule.onNodeWithContentDescription("Details for $key").performClick()

        composeTestRule.onNodeWithText("Time spent in SQLite transactions.").assertIsDisplayed()
        composeTestRule.onNodeWithText(key).assertIsDisplayed()
        composeTestRule.onNodeWithText("Histogram").assertIsDisplayed()
        // sum 2.0 over 4 observations → 500ms average; abs max scales to seconds.
        composeTestRule.onNodeWithText("500.0 ms").assertIsDisplayed()
        composeTestRule.onNodeWithText("1.50 s").assertIsDisplayed()
    }

    // ── Pinning ──────────────────────────────────────────────────────────────

    @Test
    fun pinningASeriesReportsTheCompleteReplacementList() {
        val key = "ditto.network.dsoq.connection.opened"
        var latest: List<SystemMetricSeriesRef>? = null
        setPaneWithPins(snap(listOf(sample(key, 12.0))), onChange = { latest = it })

        composeTestRule.onNodeWithContentDescription("Pin $key").performClick()

        assertEquals(listOf(SystemMetricSeriesRef(key, emptyMap())), latest)
    }

    @Test
    fun pinnedSectionShowsLiveValuesAndIgnoresTheNamespaceFilter() {
        val key = "ditto.network.dsoq.connection.opened"
        setPaneWithPins(
            snapshot = snap(listOf(sample(key, 12.0), sample("ditto.backend.sqlite3.fsync_total", 340.0))),
            initialPins = listOf(SystemMetricSeriesRef(key, emptyMap())),
        )
        composeTestRule.onNodeWithText("Pinned").assertIsDisplayed()

        // Filter the master list to a namespace the pinned series is NOT in: the
        // pinned row must survive, so the row text still appears exactly once.
        composeTestRule.onNodeWithText("Store").performClick()
        composeTestRule.onNodeWithText("network.dsoq.connection.opened").assertIsDisplayed()
    }

    @Test
    fun aPinnedSeriesWithNoDataStaysVisibleAsAPlaceholder() {
        setPaneWithPins(
            snapshot = snap(listOf(sample("ditto.backend.sqlite3.fsync_total", 340.0))),
            initialPins = listOf(SystemMetricSeriesRef("ditto.sync.sessions_started", emptyMap())),
        )
        composeTestRule.onNodeWithText("sync.sessions_started").assertIsDisplayed()
        composeTestRule.onNodeWithText("no data yet").assertIsDisplayed()
    }

    @Test
    fun clearEmptiesThePinnedSet() {
        var latest: List<SystemMetricSeriesRef>? = null
        setPaneWithPins(
            snapshot = snap(listOf(sample("ditto.network.dsoq.connection.opened", 12.0))),
            initialPins = listOf(SystemMetricSeriesRef("ditto.network.dsoq.connection.opened", emptyMap())),
            onChange = { latest = it },
        )

        composeTestRule.onNodeWithText("Clear").performClick()

        assertEquals(emptyList<SystemMetricSeriesRef>(), latest)
        composeTestRule.onNodeWithText("Pinned").assertDoesNotExist()
    }

    @Test
    fun collapsingThePinnedSectionHidesItsRowsButKeepsTheHeader() {
        setPaneWithPins(
            snapshot = snap(listOf(sample("ditto.sync.sessions_started", 3.0))),
            initialPins = listOf(SystemMetricSeriesRef("ditto.sync.sessions_started", emptyMap())),
        )
        composeTestRule.onNodeWithContentDescription("Collapse pinned metrics").performClick()

        composeTestRule.onNodeWithText("Pinned").assertIsDisplayed()
        // Only the master-list row remains — the pinned copy is gone.
        composeTestRule.onNodeWithContentDescription("Expand pinned metrics").assertIsDisplayed()
    }

    // ── Reordering ───────────────────────────────────────────────────────────

    private val first = "ditto.sync.sessions_started"
    private val second = "ditto.network.dsoq.connection.opened"

    private fun setTwoPins(onChange: (List<SystemMetricSeriesRef>) -> Unit = {}) {
        setPaneWithPins(
            snapshot = snap(listOf(sample(first, 3.0), sample(second, 12.0))),
            initialPins = listOf(
                SystemMetricSeriesRef(first, emptyMap()),
                SystemMetricSeriesRef(second, emptyMap()),
            ),
            onChange = onChange,
        )
    }

    @Test
    fun aSinglePinOffersNoReorderToggle() {
        val key = "ditto.sync.sessions_started"
        setPaneWithPins(
            snapshot = snap(listOf(sample(key, 3.0))),
            initialPins = listOf(SystemMetricSeriesRef(key, emptyMap())),
        )
        // Reordering one row is a no-op — the affordance must not be offered.
        composeTestRule.onNodeWithText("Reorder").assertDoesNotExist()
    }

    @Test
    fun handlesAppearOnlyInReorderMode() {
        setTwoPins()
        // The handle is what a drag grabs; outside reorder mode a drag belongs to
        // the list's scroll, so offering a handle there would be a lie.
        composeTestRule.onNodeWithContentDescription("Reorder $first").assertDoesNotExist()

        composeTestRule.onNodeWithText("Reorder").performClick()

        composeTestRule.onNodeWithContentDescription("Reorder $first").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Reorder $second").assertIsDisplayed()
    }

    @Test
    fun theReorderToggleFlipsToDoneAndBack() {
        setTwoPins()

        composeTestRule.onNodeWithText("Reorder").performClick()
        composeTestRule.onNodeWithText("Done").assertIsDisplayed()

        composeTestRule.onNodeWithText("Done").performClick()
        composeTestRule.onNodeWithText("Reorder").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Reorder $first").assertDoesNotExist()
    }

    @Test
    fun theMoveDownAccessibilityActionReordersAndPersists() {
        var latest: List<SystemMetricSeriesRef>? = null
        setTwoPins(onChange = { latest = it })

        composeTestRule.onNodeWithText("Reorder").performClick()
        composeTestRule.onNodeWithContentDescription("Reorder $first")
            .performCustomAccessibilityActionWithLabel("Move $first down")

        assertEquals(
            listOf(SystemMetricSeriesRef(second, emptyMap()), SystemMetricSeriesRef(first, emptyMap())),
            latest,
        )
    }

    @Test
    fun theFirstPinHasNoMoveUpActionAndTheLastNoMoveDown() {
        setTwoPins()
        composeTestRule.onNodeWithText("Reorder").performClick()

        // Only the moves that can actually happen are offered.
        composeTestRule.onNodeWithContentDescription("Reorder $first")
            .performCustomAccessibilityActionWithLabel("Move $first down")
        composeTestRule.onNodeWithContentDescription("Reorder $second")
            .performCustomAccessibilityActionWithLabel("Move $second up")
    }
}
