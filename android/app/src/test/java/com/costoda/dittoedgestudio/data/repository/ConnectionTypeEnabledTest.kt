package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The disabled-transport filter behind the bottom-bar connections counter
 * (SDK bug workaround: the presence graph retains stale connections after
 * transport config changes). Mirrors SwiftUI `isConnectionTypeEnabled`.
 */
class ConnectionTypeEnabledTest {

    private val allOn = DittoDatabase(name = "t", databaseId = "d")

    @Test
    fun `all transports enabled by default config`() {
        // Default config: BLE on, LAN on, AWDL off, cloud on, multicast off.
        assertTrue(ConnectionType.Bluetooth.isEnabledIn(allOn))
        assertTrue(ConnectionType.LAN.isEnabledIn(allOn))
        assertFalse(ConnectionType.P2PWiFi.isEnabledIn(allOn))
        assertTrue(ConnectionType.WebSocket.isEnabledIn(allOn))
        assertFalse(ConnectionType.Multicast.isEnabledIn(allOn))
        assertTrue(ConnectionType.Unknown.isEnabledIn(allOn))
    }

    @Test
    fun `multicast follows the per-database flag`() {
        // Multicast (beta, SDK 5.1.0) filters against the per-database
        // isMulticastEnabled flag (default OFF), like every other transport —
        // mirrors SwiftUI isConnectionTypeEnabled.
        assertFalse(ConnectionType.Multicast.isEnabledIn(allOn))
        assertTrue(ConnectionType.Multicast.isEnabledIn(allOn.copy(isMulticastEnabled = true)))
    }

    @Test
    fun `disabled transports are filtered`() {
        val config = allOn.copy(
            isBluetoothLeEnabled = false,
            isLanEnabled = false,
            isCloudSyncEnabled = false,
        )
        assertFalse(ConnectionType.Bluetooth.isEnabledIn(config))
        assertFalse(ConnectionType.LAN.isEnabledIn(config))
        assertFalse(ConnectionType.WebSocket.isEnabledIn(config))
    }
}
