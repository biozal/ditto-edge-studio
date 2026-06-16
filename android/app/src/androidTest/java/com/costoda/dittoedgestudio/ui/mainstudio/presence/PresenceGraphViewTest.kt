package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.PeerConnectionInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import org.junit.Rule
import org.junit.Test

/**
 * Instrumented tests for [PresenceGraphView] — run with
 *     ANDROID_SERIAL=58300DLCR0000L ./gradlew connectedAndroidTest
 * on the wipe-safe Pixel 10a device only.
 *
 * The parallel semantics layer exposes each peer pill as a `Role.Button` node carrying
 * the peer's display name as its content description. These tests assert that layer
 * appears and updates correctly.
 */
class PresenceGraphViewTest {

    @get:Rule
    val composeRule = createComposeRule()

    private fun localPeer(isCloud: Boolean = false): LocalPeerInfo = LocalPeerInfo(
        peerId = "local",
        deviceName = "Pixel 10a",
        sdkLanguage = "Kotlin",
        sdkPlatform = "Android",
        sdkVersion = "5.0.0",
        isCloudConnected = isCloud,
    )

    private fun remotePeer(
        id: String,
        name: String,
        type: ConnectionType = ConnectionType.LAN,
    ): SyncStatusInfo = SyncStatusInfo(
        peerId = id,
        deviceName = name,
        dittoSdkVersion = "5.0.0",
        connections = listOf(PeerConnectionInfo(id = "$id-c0", type = type)),
    )

    @Test
    fun emptyState_showsOnlyMe() {
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = emptyList(),
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Me").assertIsDisplayed()
    }

    @Test
    fun fivePeers_rendersFiveRemoteSemanticsNodesPlusLocal() {
        val peers = (1..5).map { remotePeer("p$it", "Device $it") }
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = peers,
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onAllNodesWithContentDescription("Device 1").assertCountEquals(1)
        composeRule.onAllNodesWithContentDescription("Device 5").assertCountEquals(1)
        composeRule.onNodeWithContentDescription("Me").assertIsDisplayed()
    }

    @Test
    fun cloudConnection_showsCloudNode() {
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(isCloud = true),
                        remotePeers = emptyList(),
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription(CLOUD_NODE_DISPLAY_NAME).assertIsDisplayed()
    }

    @Test
    fun directConnectedToggle_isPresent() {
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(remotePeer("p1", "Device 1")),
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Direct Connected Only").assertIsDisplayed()
    }

    @Test
    fun zoomLevel_isExposedAsSemantics() {
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = emptyList(),
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.onNodeWithContentDescription("Zoom level").assertIsDisplayed()
    }
}
