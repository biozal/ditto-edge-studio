package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import com.costoda.dittoedgestudio.domain.model.MeshEdge
import com.costoda.dittoedgestudio.domain.model.MeshPeer
import com.costoda.dittoedgestudio.domain.model.MeshTopology
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
    fun tapPeer_doesNotCrashAndExposesSemantics() {
        // The selection state itself isn't exposed via semantics (visual-only
        // dim/highlight on the canvas), so we exercise the click action and
        // confirm the semantics node still resolves afterward — i.e. that the
        // tap-driven recomposition path doesn't crash or remove the peer.
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

        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        // After tap-to-select, peer remains in the semantics tree.
        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed()
        // Local pill is announced for a11y but is NOT a tap target — exclusion
        // from hitTestPeer + clickable filter prevents the layout-anchor break.
        composeRule.onNodeWithContentDescription("Me").assertIsDisplayed()
    }

    @Test
    fun directOff_surfacesNonDirectMeshPeers() {
        // p1 is directly connected to local; p2 is in the raw mesh only
        // (connected to p1 but not to local). With Direct ON, p2 should not
        // appear; with Direct OFF, p2 should appear.
        val direct = remotePeer("p1", "Pixel 10a")
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                MeshPeer(peerKey = "p1", deviceName = "Pixel 10a"),
                MeshPeer(peerKey = "p2", deviceName = "Galaxy Tab"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.LAN),
                MeshEdge(peer1 = "p1", peer2 = "p2", type = ConnectionType.Bluetooth),
            ),
        )

        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(direct),
                        meshTopology = mesh,
                    ),
                    showDirectConnectedOnly = false,
                    onToggleDirectConnectedOnly = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Pixel 10a").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Galaxy Tab").assertIsDisplayed()
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
