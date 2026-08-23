package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for the bottom-bar connections counter (SwiftUI DetailBottomBar parity):
 * antenna icon + monospaced total, popover with colored-dot rows per active
 * transport, and the empty state.
 */
@RunWith(AndroidJUnit4::class)
class ConnectionsMenuButtonTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun setContent(connections: ConnectionsByTransport) {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectionsMenuButton(connections = connections)
            }
        }
    }

    @Test
    fun buttonShowsTotalWithoutChipChrome() {
        setContent(ConnectionsByTransport(bluetooth = 1, webSocket = 2))

        composeTestRule.onNodeWithTag("ConnectionsMenuButton").assertIsDisplayed()
        composeTestRule.onNodeWithText("3").assertIsDisplayed()
    }

    @Test
    fun popoverListsActiveTransportsInSwiftUIOrder() {
        setContent(
            ConnectionsByTransport(
                bluetooth = 1,
                lan = 2,
                p2pWifi = 1,
                webSocket = 3,
                dittoServer = 1,
            ),
        )

        composeTestRule.onNodeWithTag("ConnectionsMenuButton").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Connections").assertIsDisplayed()
        composeTestRule.onNodeWithTag("ConnectionsMenu_WebSocket").assertIsDisplayed()
        composeTestRule.onNodeWithText("WebSocket: 3").assertIsDisplayed()
        composeTestRule.onNodeWithText("Bluetooth: 1").assertIsDisplayed()
        composeTestRule.onNodeWithText("P2P WiFi: 1").assertIsDisplayed()
        composeTestRule.onNodeWithText("LAN: 2").assertIsDisplayed()
        composeTestRule.onNodeWithText("Ditto Server: 1").assertIsDisplayed()
    }

    @Test
    fun popoverOmitsZeroCountTransports() {
        setContent(ConnectionsByTransport(bluetooth = 2))

        composeTestRule.onNodeWithTag("ConnectionsMenuButton").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Bluetooth: 2").assertIsDisplayed()
        composeTestRule.onNodeWithText("WebSocket: 0").assertDoesNotExist()
        composeTestRule.onNodeWithText("Ditto Server: 0").assertDoesNotExist()
    }

    @Test
    fun popoverShowsEmptyStateWhenNoConnections() {
        setContent(ConnectionsByTransport.Empty)

        composeTestRule.onNodeWithTag("ConnectionsMenuButton").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("No Active Connections").assertIsDisplayed()
    }
}
