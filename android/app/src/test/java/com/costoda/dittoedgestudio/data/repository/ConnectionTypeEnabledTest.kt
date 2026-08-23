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
        // Default config: BLE on, LAN on, AWDL off, cloud on.
        assertTrue(ConnectionType.Bluetooth.isEnabledIn(allOn))
        assertTrue(ConnectionType.LAN.isEnabledIn(allOn))
        assertFalse(ConnectionType.P2PWiFi.isEnabledIn(allOn))
        assertTrue(ConnectionType.WebSocket.isEnabledIn(allOn))
        assertTrue(ConnectionType.Unknown.isEnabledIn(allOn))
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
