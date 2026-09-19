package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.SavedStateHandle
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.data.session.StudioUiState
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.MulticastConfig
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Rule
import org.junit.Test

/**
 * Compose UI tests for the Multicast (beta) fields in [TransportConfigContent]:
 * the toggle reveals/hides the group/port/interface fields, invalid input shows
 * errors and disables Apply, and a valid Apply round-trips a validated
 * [MulticastConfig] through the session.
 *
 * The view model is wired to a mocked [StudioSession] (`{ mockSession }`
 * sessionProvider, per the VM KDoc's test seam) so no Ditto instance, Room, or
 * Koin graph is required.
 */
class TransportConfigSheetTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    // The sheet renders exactly four toggleable switches (Bluetooth, LAN,
    // WiFi Aware, Multicast) in composition order — see TransportConfigContent.
    private val toggleableMatcher = SemanticsMatcher("is a Switch toggle") {
        it.config.getOrNull(SemanticsProperties.ToggleableState) != null
    }
    private fun multicastSwitch() = composeTestRule.onAllNodes(toggleableMatcher)[3]

    // Editable text fields in composition order: Group Address (0), Port (1),
    // Interface Name (2). Only present while multicast is enabled.
    private val editableMatcher = SemanticsMatcher("is an editable text field") {
        it.config.getOrNull(SemanticsProperties.EditableText) != null
    }
    private fun groupField() = composeTestRule.onAllNodes(editableMatcher)[0]
    private fun portField() = composeTestRule.onAllNodes(editableMatcher)[1]
    private fun interfaceField() = composeTestRule.onAllNodes(editableMatcher)[2]

    private fun mockSession(
        multicast: MulticastConfig = MulticastConfig(),
        applying: Boolean = false,
    ): StudioSession {
        val session = mockk<StudioSession>(relaxed = true)
        every { session.uiState } returns StudioUiState()
        every { session.syncEnabled } returns MutableStateFlow(true)
        every { session.transportBluetoothEnabled } returns MutableStateFlow(true)
        every { session.transportLanEnabled } returns MutableStateFlow(true)
        every { session.transportWifiAwareEnabled } returns MutableStateFlow(false)
        every { session.transportCloudSyncEnabled } returns MutableStateFlow(true)
        every { session.transportMulticastConfig } returns MutableStateFlow(multicast)
        every { session.isApplyingTransport } returns MutableStateFlow(applying)
        every { session.connectionsByTransport } returns
            MutableStateFlow(ConnectionsByTransport.Empty)
        return session
    }

    private fun setContent(session: StudioSession) {
        val viewModel = MainStudioViewModel(
            sessionProvider = { session },
            savedStateHandle = SavedStateHandle(),
        )
        composeTestRule.setContent {
            EdgeStudioTheme {
                TransportConfigContent(viewModel)
            }
        }
    }

    @Test
    fun multicastFieldsAreHiddenUntilEnabled() {
        val session = mockSession()
        setContent(session)

        composeTestRule.onNodeWithText("Multicast (beta)").assertIsDisplayed()
        composeTestRule.onNodeWithText("Group Address").assertDoesNotExist()
        composeTestRule.onNodeWithText("Port").assertDoesNotExist()

        multicastSwitch().performClick()

        composeTestRule.onNodeWithText("Group Address").assertIsDisplayed()
        composeTestRule.onNodeWithText("Port").assertIsDisplayed()
        composeTestRule.onNodeWithText("Interface Name (optional)").assertIsDisplayed()
        composeTestRule
            .onNodeWithText("● Multicast enabled — no multicast connections yet")
            .assertIsDisplayed()
    }

    @Test
    fun invalidGroupAddressShowsErrorAndDisablesApply() {
        val session = mockSession()
        setContent(session)
        multicastSwitch().performClick()

        // Replace the default group with a non class-D address.
        groupField().performTextReplacement("192.168.1.1")

        composeTestRule
            .onNodeWithText("Must be a class-D IPv4 address (224.0.0.0–239.255.255.255)")
            .assertIsDisplayed()
        composeTestRule.onNodeWithText("Apply Transport Settings").assertIsNotEnabled()

        // Restore a valid group — Apply re-enables (port default is valid).
        groupField().performTextReplacement("224.9.9.9")
        composeTestRule.onNodeWithText("Apply Transport Settings").assertIsEnabled()
    }

    @Test
    fun portOutOfRangeOrZeroShowsErrorAndDisablesApply() {
        val session = mockSession()
        setContent(session)
        multicastSwitch().performClick()

        // Port 0 is rejected on purpose: the SDK treats it as "any port" and
        // group rendezvous silently breaks.
        portField().performTextReplacement("0")
        composeTestRule
            .onNodeWithText("UDP port 1–65535 (all peers must match)")
            .assertIsDisplayed()
        composeTestRule.onNodeWithText("Apply Transport Settings").assertIsNotEnabled()

        portField().performTextReplacement("65536")
        composeTestRule.onNodeWithText("Apply Transport Settings").assertIsNotEnabled()

        portField().performTextReplacement("7001")
        composeTestRule.onNodeWithText("Apply Transport Settings").assertIsEnabled()
    }

    @Test
    fun applySendsValidatedMulticastConfigToSession() {
        val session = mockSession()
        setContent(session)
        multicastSwitch().performClick()

        groupField().performTextReplacement("224.9.9.9")
        portField().performTextReplacement("7001")
        interfaceField().performTextReplacement("wlan0")

        composeTestRule.onNodeWithText("Apply Transport Settings").performClick()

        // Bluetooth/LAN kept their initial enabled state, WiFi Aware stays off,
        // and the multicast fields round-trip as a validated MulticastConfig.
        verify {
            session.applyTransportSettings(
                true,
                true,
                false,
                MulticastConfig(
                    enabled = true,
                    groupAddress = "224.9.9.9",
                    port = 7001,
                    interfaceName = "wlan0",
                ),
            )
        }
    }

    @Test
    fun blankInterfaceNameAppliesAsOsDefault() {
        val session = mockSession()
        setContent(session)
        multicastSwitch().performClick()

        interfaceField().performTextReplacement("   ")

        composeTestRule.onNodeWithText("Apply Transport Settings").performClick()

        // Blank interface must not become an interface name — the SDK treats
        // null as "let the OS pick", a blank string would fail to bind.
        verify {
            session.applyTransportSettings(
                any(), any(), any(),
                match { it.enabled && it.interfaceName == null },
            )
        }
    }

    @Test
    fun applyDisabledAndShowingProgressWhileSessionApplies() {
        val session = mockSession(applying = true)
        setContent(session)

        // The Button merges its label, so the "Applying…" node is the button.
        composeTestRule.onNodeWithText("Applying…").assertIsDisplayed()
        composeTestRule.onNodeWithText("Applying…").assertIsNotEnabled()
    }
}
