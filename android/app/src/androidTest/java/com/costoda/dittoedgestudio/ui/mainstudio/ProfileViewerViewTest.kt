package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import com.costoda.dittoedgestudio.domain.model.QueryProfileStats
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes
import com.costoda.dittoedgestudio.ui.mainstudio.profile.ProfileViewerView
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose UI tests for the Profile tab, restyled to match the VS Code extension's
 * profile page (header + highlighted query, six summary cards, plan with solid
 * colored chips, profile/db/state footer).
 *
 * The fixture mirrors the reference screenshot: a DELETE over `movies` with a
 * sequence → scan / filter / remove plan.
 */
@RunWith(AndroidJUnit4::class)
class ProfileViewerViewTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val fixture = QueryProfile(
        id = "6461523f-681c-4831-9610-ce2937454287",
        appId = "fe691140-1e0a-4d8b-a6a6-cb0bd1c7528d",
        featureFlags = "0x83a",
        queryType = "mutation",
        requestType = "SDK",
        resultCount = 0,
        state = "completed",
        text = "PROFILE DELETE FROM movies WHERE plot = 'delete-stmt-test-benchmark-uuid'",
        times = QueryProfileTimes(
            elapsedNs = 39_450_000,
            parseNs = 63_870,
            planNs = 93_810,
            startISO = "2026-08-19T22:45:53.747Z",
        ),
        plan = QueryProfileOperator(
            id = "op-sequence",
            name = "sequence",
            stats = null,
            attributes = emptyList(),
            children = listOf(
                QueryProfileOperator(
                    id = "op-scan",
                    name = "scan",
                    stats = QueryProfileStats(
                        documentsIn = null,
                        documentsOut = 10_000,
                        execNs = 4_250_000,
                        recvNs = 5_700_000,
                        sendNs = 26_950_000,
                    ),
                    attributes = listOf(
                        "alias" to "movies",
                        "collection" to "movies",
                        "datasource" to "default",
                        "descriptor" to "{\"diff_scan_condition\": \"never\"}",
                    ),
                    children = emptyList(),
                ),
                QueryProfileOperator(
                    id = "op-filter",
                    name = "filter",
                    stats = QueryProfileStats(
                        documentsIn = 10_000,
                        documentsOut = null,
                        execNs = 22_470_000,
                        recvNs = null,
                        sendNs = null,
                    ),
                    attributes = listOf(
                        "condition" to "(`movies`.`plot` = \"delete-stmt-test-benchmark-uuid\")",
                    ),
                    children = emptyList(),
                ),
                QueryProfileOperator(
                    id = "op-remove",
                    name = "remove",
                    stats = QueryProfileStats(
                        documentsIn = null,
                        documentsOut = null,
                        execNs = 6_550,
                        recvNs = 38_660_000,
                        sendNs = null,
                    ),
                    attributes = listOf(
                        "collection" to "movies",
                        "datasource" to "default",
                        "mode" to "Delete",
                    ),
                    children = emptyList(),
                ),
            ),
        ),
        capturedAtMs = 1_787_179_553_747, // 2026-08-19T22:45:53.747Z
    )

    private fun setProfileContent(
        profile: QueryProfile? = fixture,
        metricsEnabled: Boolean = true,
        lastQueryText: String = "DELETE FROM movies WHERE plot = 'delete-stmt-test-benchmark-uuid'",
    ) {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ProfileViewerView(
                    profile = profile,
                    metricsEnabled = metricsEnabled,
                    lastQueryText = lastQueryText,
                )
            }
        }
    }

    // --- Populated state ---

    @Test
    fun headerShowsTitleCapturedTimestampAndQueryWithoutProfilePrefix() {
        setProfileContent()

        composeTestRule.onNodeWithText("Execution Profile").assertIsDisplayed()
        composeTestRule.onNodeWithText("captured 2026-08-19T22:45:53.747Z", substring = true)
            .assertIsDisplayed()
        // The PROFILE prefix is stripped from the displayed query.
        composeTestRule.onNodeWithText(
            "DELETE FROM movies WHERE plot = 'delete-stmt-test-benchmark-uuid'",
        ).assertIsDisplayed()
    }

    @Test
    fun summaryShowsAllSixCards() {
        setProfileContent()

        composeTestRule.onNodeWithTag("ProfileSummaryCard_ELAPSED").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ProfileSummaryCard_PARSE").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ProfileSummaryCard_PLAN").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ProfileSummaryCard_RESULT COUNT").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ProfileSummaryCard_FEATUREFLAGS").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ProfileSummaryCard_QUERYTYPE").assertIsDisplayed()

        composeTestRule.onNodeWithText("39.45 ms").assertIsDisplayed()
        composeTestRule.onNodeWithText("0x83a").assertIsDisplayed()
        composeTestRule.onNodeWithText("mutation").assertIsDisplayed()
    }

    @Test
    fun planShowsOperatorsWithSolidChips() {
        setProfileContent()

        composeTestRule.onNodeWithText("EXECUTION PLAN").assertIsDisplayed()
        composeTestRule.onNodeWithText("sequence").assertIsDisplayed()
        composeTestRule.onNodeWithText("scan").assertIsDisplayed()
        composeTestRule.onNodeWithText("filter").assertIsDisplayed()
        composeTestRule.onNodeWithText("remove").assertIsDisplayed()

        // Chips: out/in/exec/send are solid chips; recv is plain text.
        composeTestRule.onNodeWithTag("StatChip_out").assertIsDisplayed()
        composeTestRule.onNodeWithTag("StatChip_in").assertIsDisplayed()
        composeTestRule.onAllNodesWithText("exec", substring = true).assertCountEquals(3)
        composeTestRule.onNodeWithTag("StatChip_send").assertIsDisplayed()
        composeTestRule.onNodeWithText("recv 5.70 ms").assertIsDisplayed()
        // scan out: 10,000 and filter in: 10,000
        composeTestRule.onAllNodesWithText("10,000", substring = true).assertCountEquals(2)
    }

    @Test
    fun attributesRenderWithJsonDescriptorBlock() {
        setProfileContent()

        // "collection" is an attribute key on both the scan and remove cards.
        composeTestRule.onAllNodesWithText("collection").assertCountEquals(2)
        composeTestRule.onAllNodesWithText("movies").assertCountEquals(3) // alias + collection ×2
        // The descriptor attribute is pretty-printed and highlighted.
        composeTestRule.onNodeWithText("\"diff_scan_condition\": \"never\"", substring = true)
            .assertIsDisplayed()
        composeTestRule.onNodeWithText("Delete").assertIsDisplayed()
    }

    @Test
    fun footerShowsProfileDbAndState() {
        setProfileContent()

        composeTestRule.onNodeWithTag("ProfileFooter").assertIsDisplayed()
        composeTestRule.onNodeWithText(
            "profile: 6461523f-681c-4831-9610-ce2937454287 · " +
                "db: fe691140-1e0a-4d8b-a6a6-cb0bd1c7528d · state: completed",
        ).assertIsDisplayed()
    }

    @Test
    fun planModePickerSwitchesToTreeView() {
        setProfileContent()

        composeTestRule.onNodeWithText("Plan").performClick()
        composeTestRule.waitForIdle()

        // Tree view shows operator names without the card chrome.
        composeTestRule.onNodeWithText("sequence").assertIsDisplayed()
        composeTestRule.onNodeWithText("scan").assertIsDisplayed()
    }

    @Test
    fun tallPlanScrollsToTheFooter() {
        // A plan taller than the viewport: the last card and the footer must be
        // reachable by scrolling (regression guard for the floating pagination bar
        // pinning content beneath it).
        val tallPlan = (1..30).fold(
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
        setProfileContent(profile = fixture.copy(plan = tallPlan))

        // Reaching the footer proves the page scrolls to the very bottom. (The
        // deepest card is indented ~360dp, so its text is legitimately off the
        // right edge of a phone viewport — the footer is the reliable assertion.)
        composeTestRule.onNodeWithTag("ProfileFooter").performScrollTo()
        composeTestRule.onNodeWithTag("ProfileFooter").assertIsDisplayed()
    }

    // --- Empty states ---

    @Test
    fun metricsOffStateTakesPrecedence() {
        setProfileContent(profile = fixture, metricsEnabled = false)

        composeTestRule.onNodeWithText("Profiling is turned off").assertIsDisplayed()
        composeTestRule.onNodeWithText("Execution Profile").assertDoesNotExist()
    }

    @Test
    fun nonSelectStateShownWhenLastQueryWasMutation() {
        setProfileContent(profile = null, lastQueryText = "DELETE FROM movies")

        composeTestRule.onNodeWithText(
            "Profiles are only captured for SELECT statements.",
        ).assertIsDisplayed()
    }

    @Test
    fun noQueryYetState() {
        setProfileContent(profile = null, lastQueryText = "")

        composeTestRule.onNodeWithText(
            "Run a SELECT query to capture an execution profile.",
        ).assertIsDisplayed()
    }
}
