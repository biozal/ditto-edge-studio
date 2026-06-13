package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.core.layout.WindowSizeClass
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.data.session.StudioUiState
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Regression tests for [StudioScaffold]'s two structural layout modes.
 *
 * ## Why these tests exist
 *
 * The bug shipped in FU-6 was caused by StudioScaffold being composed *per-pane* inside scene
 * entries — two scaffolds appeared side-by-side instead of one wrapping the NavDisplay. A
 * direct structural test on the scaffold at the two breakpoints catches this entire class of
 * regression: if a future change moves the scaffold call back inside an entry provider, the
 * "expanded" test would fail because both the hamburger (from one scaffold) and the persistent
 * rail (from the other) might exist simultaneously, or neither would match the expected state.
 *
 * ## Layout contract under test
 *
 *  - **Compact (<840dp)**: Hamburger button (contentDescription "Open menu") is visible.
 *    Persistent [NavigationRail] (testTag "StudioRail") is NOT visible — it lives inside the
 *    modal drawer instead.
 *  - **Expanded (≥840dp)**: Persistent [NavigationRail] (testTag "StudioRail") is visible.
 *    Hamburger button does NOT exist.
 *
 * ## Fake session
 *
 * [StudioSession] has many constructor dependencies (Ditto, Room, Koin). We use MockK's relaxed
 * instrumented mock so the scaffold can read `session.uiState` and `session.syncEnabled` without
 * wiring up the full session lifecycle.
 */
@RunWith(AndroidJUnit4::class)
class StudioScaffoldLayoutTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    /** Build a WindowSizeClass for testing. The height is irrelevant for studio breakpoints. */
    private fun wsc(widthDp: Int, heightDp: Int = 800) = WindowSizeClass(widthDp, heightDp)

    /** Build a minimal relaxed mock of StudioSession sufficient for StudioScaffold. */
    private fun fakeSession(): StudioSession {
        val session = mockk<StudioSession>(relaxed = true)
        every { session.uiState } returns StudioUiState()
        every { session.syncEnabled } returns MutableStateFlow(false)
        return session
    }

    // ---------------------------------------------------------------------------
    // Test 1: Compact mode (400×800dp) — hamburger visible, rail absent
    // ---------------------------------------------------------------------------

    @Test
    fun compact_showsHamburger_and_railIsNotVisible() {
        composeTestRule.setContent {
            MaterialTheme {
                StudioScaffold(
                    currentSection = StudioNavItem.SUBSCRIPTIONS,
                    session = fakeSession(),
                    onBack = {},
                    onSectionSelect = {},
                    windowSizeClass = wsc(400),
                ) {
                    Text("CONTENT_SLOT_COMPACT")
                }
            }
        }

        // Hamburger must be present and visible in compact/drawer mode.
        composeTestRule
            .onNodeWithContentDescription("Open menu")
            .assertExists()
            .assertIsDisplayed()

        // The persistent NavigationRail must NOT be displayed — it folds into the modal drawer.
        // The testTag "StudioRail" is applied to the NavigationRail in StudioScaffold's
        // multi-pane branch only; in drawer mode the composable is never placed in the tree,
        // so assertDoesNotExist() is the correct assertion (not just assertIsNotDisplayed()).
        composeTestRule
            .onNodeWithTag("StudioRail")
            .assertDoesNotExist()

        // Content slot must render in the Scaffold body.
        composeTestRule.onNodeWithText("CONTENT_SLOT_COMPACT").assertIsDisplayed()
    }

    // ---------------------------------------------------------------------------
    // Test 2: Expanded mode (1000×700dp) — rail visible, hamburger absent
    // ---------------------------------------------------------------------------

    @Test
    fun expanded_showsRail_and_hamburgerAbsent() {
        composeTestRule.setContent {
            MaterialTheme {
                StudioScaffold(
                    currentSection = StudioNavItem.SUBSCRIPTIONS,
                    session = fakeSession(),
                    onBack = {},
                    onSectionSelect = {},
                    windowSizeClass = wsc(1000, 700),
                ) {
                    Text("CONTENT_SLOT_EXPANDED")
                }
            }
        }

        // Persistent NavigationRail must be visible in multi-pane mode.
        composeTestRule
            .onNodeWithTag("StudioRail")
            .assertIsDisplayed()

        // Hamburger must not exist — there is no modal drawer in multi-pane mode.
        composeTestRule
            .onNodeWithContentDescription("Open menu")
            .assertDoesNotExist()

        // Content slot renders in the center column.
        composeTestRule.onNodeWithText("CONTENT_SLOT_EXPANDED").assertIsDisplayed()
    }

    // ---------------------------------------------------------------------------
    // Test 3: Compact mode — opening the drawer reveals the dataPanelContent slot
    // ---------------------------------------------------------------------------

    @Test
    fun compact_openDrawer_showsDataPanelContent() {
        composeTestRule.setContent {
            MaterialTheme {
                StudioScaffold(
                    currentSection = StudioNavItem.QUERY,
                    session = fakeSession(),
                    onBack = {},
                    onSectionSelect = {},
                    windowSizeClass = wsc(400),
                    dataPanelContent = { _ ->
                        // A recognizable marker text. The scaffold renders this inside the modal
                        // drawer below the nav items, so it is only reachable after opening.
                        Text("DATA_PANEL_MARKER")
                    },
                ) {
                    Text("CONTENT_SLOT_DRAWER_TEST")
                }
            }
        }

        // Data panel content lives inside the closed modal drawer — not yet visible.
        // (The drawer is lazy; the content may not be composed until opened.)

        // Open the drawer by clicking the hamburger.
        composeTestRule
            .onNodeWithContentDescription("Open menu")
            .performClick()

        // After opening the drawer, the data panel marker must appear.
        composeTestRule
            .onNodeWithText("DATA_PANEL_MARKER")
            .assertIsDisplayed()
    }
}
