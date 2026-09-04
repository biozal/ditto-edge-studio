package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Pixel 10a").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Galaxy Tab").assertIsDisplayed()
    }

    @Test
    fun focusMode_bannerAppearsOnTapInExpandedModeAndExits() {
        // Expanded (Direct OFF) mode: tapping a remote peer enters the focused-
        // neighbourhood view and shows the banner; the ✕ button exits and the
        // banner leaves the semantics tree. The focused id is hoisted state, so
        // the test threads a remember the way MainStudioViewModel does in app.
        composeRule.setContent {
            EdgeStudioTheme {
                val focusState = remember { mutableStateOf<String?>(null) }
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(remotePeer("p1", "Device 1")),
                    ),
                    showDirectConnectedOnly = false,
                    onToggleDirectConnectedOnly = {},
                    focusedPeerId = focusState.value,
                    onFocusedPeerChange = { focusState.value = it },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Exit focus").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
    }

    @Test
    fun focusMode_tappingContextPeerExitsFocus() {
        // Expanded mode: focus Device 1; Device 2 is connected only to local
        // (not to Device 1), so it renders as dimmed context. Tapping it falls
        // through to a canvas click (extension nodeAt parity: non-orbit nodes
        // are skipped by the hit-test) and exits focus instead of refocusing.
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                MeshPeer(peerKey = "p1", deviceName = "Device 1"),
                MeshPeer(peerKey = "p2", deviceName = "Device 2"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.LAN),
                MeshEdge(peer1 = "local", peer2 = "p2", type = ConnectionType.LAN),
            ),
        )
        composeRule.setContent {
            EdgeStudioTheme {
                val focusState = remember { mutableStateOf<String?>(null) }
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(
                            remotePeer("p1", "Device 1"),
                            remotePeer("p2", "Device 2"),
                        ),
                        meshTopology = mesh,
                    ),
                    showDirectConnectedOnly = false,
                    onToggleDirectConnectedOnly = {},
                    focusedPeerId = focusState.value,
                    onFocusedPeerChange = { focusState.value = it },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Device 2").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
    }

    @Test
    fun focusMode_directModeTapShowsNoBanner() {
        // Direct mode: a tap only dims (selection) — no focus banner.
        composeRule.setContent {
            EdgeStudioTheme {
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(remotePeer("p1", "Device 1")),
                    ),
                    showDirectConnectedOnly = true,
                    onToggleDirectConnectedOnly = {},
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
    }

    @Test
    fun modeToggle_withEqualProjection_discardsFocus() {
        // The direct star and the published mesh can project to the SAME graph
        // (all-direct mesh with matching order). A mode toggle must still run
        // the mode-change bookkeeping — discarding an active focus session —
        // even though graphModel/layout don't change shape.
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(MeshPeer(peerKey = "p1", deviceName = "Device 1")),
            edges = listOf(MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.LAN)),
        )
        composeRule.setContent {
            EdgeStudioTheme {
                val focusState = remember { mutableStateOf<String?>(null) }
                val directOnly = remember { mutableStateOf(false) }
                PresenceGraphView(
                    peersUiState = PeersUiState.Active(
                        localPeer = localPeer(),
                        remotePeers = listOf(remotePeer("p1", "Device 1")),
                        meshTopology = mesh,
                    ),
                    showDirectConnectedOnly = directOnly.value,
                    onToggleDirectConnectedOnly = { directOnly.value = !directOnly.value },
                    focusedPeerId = focusState.value,
                    onFocusedPeerChange = { focusState.value = it },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Expanded: tap the peer to enter focus.
        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertIsDisplayed()

        // Toggle Direct ON via the control switch — focus must be discarded even
        // though both projections contain the same single peer.
        composeRule.onNodeWithContentDescription("Direct Connected Only").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed()
    }

    @Test
    fun focusMode_reentryAfterSubtreeDispose_restoresFocus() {
        // The focused id is hoisted so it survives the Peers ↔ Viewer tab switch,
        // which disposes this subtree. On re-add the view must re-enter focus
        // (rebuilding the view-local orbit + pre-focus camera) instead of
        // dropping the session. Driven by a state-holder that removes/re-adds
        // the graph view, the way the tab `when` does.
        composeRule.setContent {
            EdgeStudioTheme {
                val focusState = remember { mutableStateOf<String?>(null) }
                val graphVisible = remember { mutableStateOf(true) }
                Box(
                    Modifier.semantics { contentDescription = "Toggle graph host" }
                        .clickable { graphVisible.value = !graphVisible.value },
                )
                if (graphVisible.value) {
                    PresenceGraphView(
                        peersUiState = PeersUiState.Active(
                            localPeer = localPeer(),
                            remotePeers = listOf(remotePeer("p1", "Device 1")),
                        ),
                        showDirectConnectedOnly = false,
                        onToggleDirectConnectedOnly = {},
                        focusedPeerId = focusState.value,
                        onFocusedPeerChange = { focusState.value = it },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }

        composeRule.onNodeWithContentDescription("Device 1").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertIsDisplayed()

        // Tab away: the subtree (banner included) leaves composition.
        composeRule.onNodeWithContentDescription("Toggle graph host").performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()

        // Tab back: the hoisted id survived, so focus re-enters and the banner
        // returns. If re-entry dropped the id instead, this would not reappear.
        composeRule.onNodeWithContentDescription("Toggle graph host").performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertIsDisplayed()

        // Focus is functional after re-entry — the exit affordance still works.
        composeRule.onNodeWithContentDescription("Exit focus").assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("Focused on Device 1").assertDoesNotExist()
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
                    focusedPeerId = null,
                    onFocusedPeerChange = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.onNodeWithContentDescription("Zoom level").assertIsDisplayed()
    }
}
