package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.PeersUiState
import org.junit.Rule
import org.junit.Test

class ConnectedPeersScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun `Initializing state shows progress indicator`() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Initializing,
                    networkInterfaces = emptyList(),
                    p2pTransports = emptyList(),
                    onLoadDiagnostics = {},
                )
            }
        }

        // CircularProgressIndicator is shown — verify by checking no peer content appears
        composeTestRule.onNodeWithText("This Device").assertDoesNotExist()
    }

    @Test
    fun `Active state with localPeer shows LocalPeerCard with device name`() {
        val localPeer = LocalPeerInfo(
            peerId = "abc123",
            deviceName = "Google Pixel 9",
            sdkLanguage = "Kotlin",
            sdkPlatform = "Android",
            sdkVersion = "5.0.0",
        )

        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Active(localPeer = localPeer, remotePeers = emptyList()),
                    networkInterfaces = emptyList(),
                    p2pTransports = emptyList(),
                    onLoadDiagnostics = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Google Pixel 9").assertIsDisplayed()
        composeTestRule.onNodeWithText("This Device").assertIsDisplayed()
    }

    @Test
    fun `Active state with remote peer shows RemotePeerCard`() {
        val remotePeer = SyncStatusInfo(
            peerId = "remote-peer-key",
            deviceName = "iPhone 16",
            dittoSdkVersion = "5.0.0",
        )

        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Active(localPeer = null, remotePeers = listOf(remotePeer)),
                    networkInterfaces = emptyList(),
                    p2pTransports = emptyList(),
                    onLoadDiagnostics = {},
                )
            }
        }

        composeTestRule.onNodeWithText("iPhone 16").assertIsDisplayed()
    }

    @Test
    fun `WiFi interface card shows location permission warning when permission denied`() {
        val wifiIface = makeWifiInterface(locationPermissionGranted = false)

        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Active(localPeer = null, remotePeers = emptyList()),
                    networkInterfaces = listOf(wifiIface),
                    p2pTransports = emptyList(),
                    onLoadDiagnostics = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Location permission needed for SSID/BSSID").assertIsDisplayed()
    }

    @Test
    fun `WiFi interface card shows RSSI when available`() {
        val wifiIface = makeWifiInterface(rssi = -65, signalLevel = 3, locationPermissionGranted = false)

        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Active(localPeer = null, remotePeers = emptyList()),
                    networkInterfaces = listOf(wifiIface),
                    p2pTransports = emptyList(),
                    onLoadDiagnostics = {},
                )
            }
        }

        composeTestRule.onNodeWithText("-65 dBm").assertIsDisplayed()
    }

    @Test
    fun `P2P transport cards appear when hardware is available`() {
        val wifiAware = P2PTransportInfo(
            kind = P2PTransportInfo.Kind.WifiAware,
            isHardwareAvailable = true,
            isEnabled = true,
            statusDetail = "Hardware ready — Ditto uses this for P2P sync",
        )

        composeTestRule.setContent {
            EdgeStudioTheme {
                ConnectedPeersScreen(
                    peersUiState = PeersUiState.Active(localPeer = null, remotePeers = emptyList()),
                    networkInterfaces = emptyList(),
                    p2pTransports = listOf(wifiAware),
                    onLoadDiagnostics = {},
                )
            }
        }

        composeTestRule.onNodeWithText("WiFi Aware (NAN)").assertIsDisplayed()
    }

    private fun makeWifiInterface(
        rssi: Int? = null,
        signalLevel: Int? = null,
        locationPermissionGranted: Boolean = false,
    ) = NetworkInterfaceInfo(
        id = "wlan0",
        interfaceName = "wlan0",
        kind = NetworkInterfaceInfo.InterfaceKind.Wifi,
        isActive = true,
        hardwareAddress = "02:00:00:00:00:00",
        mtu = 1500,
        ipv4Address = "192.168.1.100",
        ipv6Address = null,
        gatewayAddress = "192.168.1.1",
        ssid = if (locationPermissionGranted) "MyNetwork" else null,
        bssid = if (locationPermissionGranted) "aa:bb:cc:dd:ee:ff" else null,
        rssi = rssi,
        signalLevel = signalLevel,
        linkSpeedMbps = 150,
        txLinkSpeedMbps = null,
        rxLinkSpeedMbps = null,
        frequencyMhz = 2412,
        frequencyBandLabel = "2.4 GHz",
        wifiStandardLabel = "WiFi 4 (802.11n)",
        ethernetBandwidthKbps = null,
        locationPermissionGranted = locationPermissionGranted,
    )
}
